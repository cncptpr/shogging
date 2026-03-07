# Stage 1: Build the Gleam application
FROM ghcr.io/gleam-lang/gleam:v1.14.0-erlang-alpine AS builder

WORKDIR /app/server

# Copy the library first

# Dependencies first
COPY shogg/gleam.toml shogg/manifest.toml ../shogg/
COPY server/gleam.toml server/manifest.toml ./
RUN apk add git && gleam deps download

# Copy source and build for production
# NOTE: Don't forget to add priv/ here, if it is ever needed
COPY shogg/src/ ../shogg/src/
COPY server/src/ src/
RUN gleam build

# Collect the Erlang release
RUN gleam export erlang-shipment

# Stage 2: Minimal Erlang runtime
FROM erlang:29-alpine AS runner

WORKDIR /app

# Install runtime dependencies
RUN apk add --no-cache libstdc++ openssl ncurses-libs

# Copy the Erlang release from builder
COPY --from=builder /app/server/build/erlang-shipment /app

# Create non-root user
RUN adduser -D -H gleamuser
USER gleamuser

EXPOSE 1234

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Run the Erlang release
CMD ["/app/entrypoint.sh", "run"]
