# Multi-stage build for the XBAND modem-replacement server.
# Stage 1: compile a static binary with the pinned Go toolchain.
FROM golang:1.24-alpine AS build
WORKDIR /src

# Module files first for layer caching (no external deps: stdlib only).
COPY go.mod ./
RUN go mod download

COPY . .
# CGO disabled → a fully static binary that runs in scratch.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" \
    -o /out/xbandserver ./cmd/xbandserver

# Stage 2: minimal runtime image.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/xbandserver /xbandserver
EXPOSE 7654
ENV XBAND_LISTEN=:7654
USER nonroot:nonroot
ENTRYPOINT ["/xbandserver"]
