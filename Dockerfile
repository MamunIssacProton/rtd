# ═══════════════════════════════════════════════════════════════════════════════
# Stage 1 — deps
#   Install ALL dependencies (prod + dev) so the builder stage can compile and
#   run tests without re-downloading anything.
# ═══════════════════════════════════════════════════════════════════════════════
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine AS deps

# Install OS-level build tools needed by some native npm addons
RUN apk add --no-cache libc6-compat

WORKDIR /app

# Copy only the manifests first to maximise layer-cache hits
COPY package.json package-lock.json ./

# ci is faster than install and produces a clean, deterministic tree
RUN npm ci

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 2 — builder
#   Compile TypeScript → JS  and run the unit-test suite.
#   If tests fail the image build fails — tests are a hard gate.
# ═══════════════════════════════════════════════════════════════════════════════
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine AS builder

WORKDIR /app

# Bring in the full node_modules from the deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy the rest of the source tree
COPY . .

# Compile
RUN npm run build

# Run unit tests — a failing test aborts the build
RUN npm test

# ═══════════════════════════════════════════════════════════════════════════════
# Stage 3 — production
#   Minimal, hardened runtime image.
#   Only production dependencies and compiled output are included.
# ═══════════════════════════════════════════════════════════════════════════════
ARG NODE_VERSION=22
FROM node:${NODE_VERSION}-alpine AS production

# Security: run as non-root user
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app

ENV NODE_ENV=production

# Copy package manifests and install ONLY production deps
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy compiled output from builder stage
COPY --from=builder /app/dist ./dist

# Switch to non-root user
USER appuser

EXPOSE 3000

CMD ["node", "dist/main"]
