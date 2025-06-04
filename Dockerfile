# Use Alpine as base image
FROM alpine:3

# Install dependencies and kubectl
RUN apk add --no-cache tzdata curl bash jq netcat-openbsd ca-certificates && curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && chmod +x kubectl && mv kubectl /usr/local/bin/.

# Deploy the container
COPY helaseid.sh /usr/local/bin/helaseid.sh
RUN chmod +x /usr/local/bin/helaseid.sh
CMD ["/usr/local/bin/helaseid.sh"]
