FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm install --no-fund --no-audit
COPY src/ ./src/
COPY tsconfig.json ./
RUN npm run build

FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev --no-fund --no-audit
COPY --from=builder /app/dist ./dist
COPY src/data/ ./dist/data/
ENV PORT=8080
CMD ["node", "dist/index.js"]
