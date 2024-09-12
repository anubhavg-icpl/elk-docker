#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Generate SSL certificates
mkdir -p certs
docker run --rm -v $(pwd)/certs:/certs docker.elastic.co/elasticsearch/elasticsearch:8.10.2 \
  bin/elasticsearch-certutil cert --out /certs/elastic-certificates.p12 --pass ""

# Generate CA certificate
docker run --rm -v $(pwd)/certs:/certs docker.elastic.co/elasticsearch/elasticsearch:8.10.2 \
  bin/elasticsearch-certutil ca --out /certs/ca.zip --pass ""
unzip certs/ca.zip -d certs

# Set up .env file
cat << EOF > .env
ELASTIC_PASSWORD=$(openssl rand -base64 32)
KIBANA_PASSWORD=$(openssl rand -base64 32)
LOGSTASH_SYSTEM_PASSWORD=$(openssl rand -base64 32)
KIBANA_ENCRYPTION_KEY=$(openssl rand -hex 32)
EOF

# Set correct permissions
chmod 600 .env
chmod 644 certs/elastic-certificates.p12 certs/ca.crt

echo "ELK stack setup complete. Please review the .env file and update passwords as needed."