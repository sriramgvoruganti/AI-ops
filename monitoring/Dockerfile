# Prometheus image for AWS: the config is baked in because Fargate can't bind-mount files.
FROM prom/prometheus:latest
COPY prometheus.aws.yml /etc/prometheus/prometheus.yml
