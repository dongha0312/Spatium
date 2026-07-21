FROM node:22-bookworm-slim AS build

WORKDIR /workspace

COPY spatium-frontend/package.json spatium-frontend/package-lock.json ./

RUN npm ci

COPY spatium-frontend/ ./

RUN npm run build


FROM nginx:stable-alpine

COPY deploy/nginx/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /workspace/build /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
