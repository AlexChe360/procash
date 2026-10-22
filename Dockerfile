# syntax=docker/dockerfile:1
FROM node:24-alpine AS frontend
WORKDIR /src
COPY package.json package-lock.json ./
RUN --mount=type=secret,id=build_ca \
    if [ -f /run/secrets/build_ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/build_ca; fi; \
    npm ci --no-audit --no-fund
COPY web ./web
RUN npm run build

FROM golang:1.27.3-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=secret,id=build_ca \
    if [ -f /run/secrets/build_ca ]; then export SSL_CERT_FILE=/run/secrets/build_ca; fi; \
    go mod download && go mod verify
COPY . .
COPY --from=frontend /src/web/static ./web/static
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o /out/procash ./cmd/procash

FROM scratch AS production
WORKDIR /app
COPY --from=build /out/procash /usr/local/bin/procash
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENV PATH=/usr/local/bin
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/procash"]
CMD ["serve"]
