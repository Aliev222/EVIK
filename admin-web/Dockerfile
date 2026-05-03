# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -tags netgo -ldflags "-s -w" -o admin-web .

# Runtime stage
FROM alpine:3.20

RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /app/admin-web .

EXPOSE 5174
CMD ["./admin-web"]

