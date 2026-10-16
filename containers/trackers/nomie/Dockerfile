# Nomie 6 from source: build the web app, then serve the static files.
FROM node:16-alpine AS builder
RUN apk add --no-cache git
RUN git clone https://github.com/open-nomie/nomie6-oss.git /app
WORKDIR /app
RUN npm install
RUN npm run vbuild

FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 80
