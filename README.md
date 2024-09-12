

Let's start with the Docker Compose file for the ELK stack:

```yaml
version: '3.8'

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.10.2
    container_name: elasticsearch
    environment:
      - node.name=elasticsearch
      - cluster.name=es-docker-cluster
      - discovery.type=single-node
      - bootstrap.memory_lock=true
      - "ES_JAVA_OPTS=-Xms1g -Xmx1g"
      - xpack.security.enabled=true
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - esdata:/usr/share/elasticsearch/data
      - ./elasticsearch.yml:/usr/share/elasticsearch/config/elasticsearch.yml:ro
      - ./certs:/usr/share/elasticsearch/config/certs
    ports:
      - "9200:9200"
    networks:
      - elk
    healthcheck:
      test: ["CMD-SHELL", "curl -s -f https://localhost:9200/_cluster/health || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5

  logstash:
    image: docker.elastic.co/logstash/logstash:8.10.2
    container_name: logstash
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline:ro
      - ./logstash/config/logstash.yml:/usr/share/logstash/config/logstash.yml:ro
      - ./certs:/usr/share/logstash/config/certs
      - /var/ossec/logs/alerts:/var/ossec/logs/alerts:ro
    ports:
      - "5044:5044"
      - "5000:5000/tcp"
      - "5000:5000/udp"
      - "9600:9600"
    environment:
      LS_JAVA_OPTS: "-Xmx256m -Xms256m"
    networks:
      - elk
    depends_on:
      - elasticsearch

  kibana:
    image: docker.elastic.co/kibana/kibana:8.10.2
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=https://elasticsearch:9200
      - ELASTICSEARCH_USERNAME=kibana_system
      - ELASTICSEARCH_PASSWORD=${KIBANA_PASSWORD}
    volumes:
      - ./kibana.yml:/usr/share/kibana/config/kibana.yml:ro
      - ./certs:/usr/share/kibana/config/certs
    ports:
      - "5601:5601"
    networks:
      - elk
    depends_on:
      - elasticsearch
    healthcheck:
      test: ["CMD-SHELL", "curl -s -f http://localhost:5601/api/status || exit 1"]
      interval: 30s
      timeout: 10s
      retries: 5

networks:
  elk:
    driver: bridge

volumes:
  esdata:
    driver: local

```

Now, let's create the necessary configuration files:

1. Elasticsearch configuration (elasticsearch.yml):

```yaml
cluster.name: "docker-cluster"
network.host: 0.0.0.0

xpack.security.enabled: true
xpack.security.transport.ssl.enabled: true
xpack.security.transport.ssl.verification_mode: certificate
xpack.security.transport.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.transport.ssl.truststore.path: certs/elastic-certificates.p12

xpack.security.http.ssl.enabled: true
xpack.security.http.ssl.keystore.path: certs/elastic-certificates.p12
xpack.security.http.ssl.truststore.path: certs/elastic-certificates.p12

discovery.type: single-node

```

2. Logstash configuration (logstash.yml):

```yaml
http.host: "0.0.0.0"
xpack.monitoring.elasticsearch.hosts: [ "https://elasticsearch:9200" ]
xpack.monitoring.elasticsearch.ssl.certificate_authority: /usr/share/logstash/config/certs/ca.crt
xpack.monitoring.elasticsearch.username: logstash_system
xpack.monitoring.elasticsearch.password: ${LOGSTASH_SYSTEM_PASSWORD}

```

3. Logstash pipeline configuration (logstash/pipeline/wazuh-elasticsearch.conf):

```conf
input {
  file {
    path => "/var/ossec/logs/alerts/alerts.json"
    codec => "json"
    type => "wazuh-alerts"
    start_position => "beginning"
    stat_interval => "1 second"
    mode => "tail"
    ecs_compatibility => "disabled"
  }
}

filter {
  if [type] == "wazuh-alerts" {
    date {
      match => ["timestamp", "ISO8601"]
      target => "@timestamp"
    }
    mutate {
      remove_field => ["timestamp", "beat", "input_type", "tags", "count", "offset", "host", "type"]
    }
  }
}

output {
  if [type] == "wazuh-alerts" {
    elasticsearch {
      hosts => ["https://elasticsearch:9200"]
      index => "wazuh-alerts-4.x-%{+YYYY.MM.dd}"
      user => "${ELASTICSEARCH_USERNAME}"
      password => "${ELASTICSEARCH_PASSWORD}"
      ssl => true
      ssl_certificate_verification => true
      cacert => "/usr/share/logstash/config/certs/ca.crt"
    }
  }
}

```

4. Kibana configuration (kibana.yml):

```yaml
server.name: kibana
server.host: "0.0.0.0"
elasticsearch.hosts: [ "https://elasticsearch:9200" ]
elasticsearch.ssl.certificateAuthorities: [ "/usr/share/kibana/config/certs/ca.crt" ]
elasticsearch.username: kibana_system
elasticsearch.password: ${KIBANA_PASSWORD}
xpack.security.encryptionKey: ${KIBANA_ENCRYPTION_KEY}
xpack.encryptedSavedObjects.encryptionKey: ${KIBANA_ENCRYPTION_KEY}

```

Now, let's create a script to set up the necessary certificates and passwords:

```bash
#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Generate certificates
docker-compose run --rm elasticsearch bin/elasticsearch-certutil cert -out config/certs/elastic-certificates.p12 -pass ""

# Set permissions
sudo chown -R root:root config/certs
sudo chmod -R 644 config/certs

# Generate .env file with passwords
cat << EOF > .env
ELASTIC_PASSWORD=$(openssl rand -base64 32)
KIBANA_PASSWORD=$(openssl rand -base64 32)
KIBANA_ENCRYPTION_KEY=$(openssl rand -hex 32)
LOGSTASH_SYSTEM_PASSWORD=$(openssl rand -base64 32)
EOF

# Start Elasticsearch
docker-compose up -d elasticsearch

# Wait for Elasticsearch to start
until curl -s --cacert config/certs/ca.crt https://localhost:9200 >/dev/null; do
    sleep 5
done

# Set up users and roles
docker-compose exec -T elasticsearch bin/elasticsearch-users useradd logstash_system -p ${LOGSTASH_SYSTEM_PASSWORD} -r logstash_system
docker-compose exec -T elasticsearch bin/elasticsearch-users useradd kibana_system -p ${KIBANA_PASSWORD} -r kibana_system

# Start the rest of the stack
docker-compose up -d

echo "ELK stack is now set up and running."

```

To set up this production-ready ELK stack with Wazuh integration, follow these steps:

1. Install Docker and Docker Compose on your server.

2. Create a new directory for your ELK stack and navigate to it.

3. Create the Docker Compose file and all configuration files mentioned above in their respective locations.

4. Create the setup script and make it executable:
   ```
   chmod +x setup-elk.sh
   ```

5. Run the setup script:
   ```
   ./setup-elk.sh
   ```

6. Once the stack is up and running, configure Wazuh to send logs to Logstash:
   - Edit `/var/ossec/etc/ossec.conf` on your Wazuh server
   - Add or modify the `<global>` section:
     ```xml
     <global>
       <json_output>yes</json_output>
       <alerts_log>yes</alerts_log>
       <logall>no</logall>
     </global>
     ```

7. Restart the Wazuh manager:
   ```
   sudo systemctl restart wazuh-manager
   ```

8. Import Wazuh dashboards in Kibana:
   - Download the dashboard file:
     ```
     wget https://packages.wazuh.com/integrations/elastic/4.x-8.x/dashboards/wz-es-4.x-8.x-dashboards.ndjson
     ```
   - In Kibana, go to Management > Stack Management > Saved Objects
   - Click Import and select the downloaded file

Additional production-ready considerations:

1. Implement proper backup strategies for your Elasticsearch data and configurations.
2. Set up log rotation for Docker container logs.
3. Monitor the health and performance of your Docker containers and the ELK stack.
4. Regularly update the ELK stack and Wazuh to their latest compatible versions.
5. Implement network segmentation to isolate your ELK stack.
6. Use a reverse proxy (e.g., Nginx) in front of Kibana for additional security layers.
7. Implement proper firewall rules to restrict access to your ELK stack.
8. Regularly review and rotate all passwords and SSL certificates.
9. Consider scaling out Elasticsearch to a cluster for larger deployments.
10. Implement alerting based on Elasticsearch and Wazuh data for proactive monitoring.

This setup provides a strong foundation for a production-ready ELK stack running on Docker with Wazuh integration. Remember to adapt these configurations to your specific environment and security requirements.