FROM node:20-alpine
ARG APP_VERSION=1.0
ENV APP_VERSION=${APP_VERSION}
WORKDIR /app
COPY package.json .
RUN npm install --omit=dev
COPY server.js .
USER node
EXPOSE 8080
HEALTHCHECK --interval=20s --timeout=3s CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
CMD ["node", "server.js"]
