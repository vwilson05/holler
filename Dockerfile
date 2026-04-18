FROM oven/bun:1 AS deps
WORKDIR /app
COPY server/package.json server/bun.lock* ./server/
RUN cd server && (bun install --frozen-lockfile || bun install --production)

FROM oven/bun:1-slim AS runtime
WORKDIR /app
COPY --from=deps /app/server/node_modules ./server/node_modules
COPY server/ ./server/
COPY web/ ./web/

ENV NODE_ENV=production
EXPOSE 3000

WORKDIR /app/server
CMD ["bun", "run", "index.ts"]
