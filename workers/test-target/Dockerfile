# The provided deliberately vulnerable API (test-target.js), used as the
# demo target. It must never be reachable from the internet.
# Build it from the REPO ROOT (see README Step 5).
FROM node:22-slim
WORKDIR /app
COPY pentest/backend/package*.json ./
RUN npm install --omit=dev
COPY pentest/backend/ ./
USER node
EXPOSE 4000
CMD ["node", "test-target.js"]
