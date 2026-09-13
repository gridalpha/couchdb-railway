FROM caddy:2-alpine

# The build context is the repo root when a service selects its Dockerfile with
# RAILWAY_DOCKERFILE_PATH, so the source path is prefixed.
COPY proxy/Caddyfile /etc/caddy/Caddyfile

# Every {$VAR} in the file carries a default, so this validates at build time with
# nothing set and a config typo fails the build instead of crash-looping a container.
RUN caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
