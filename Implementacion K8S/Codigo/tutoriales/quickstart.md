# Quickstart K8s - PharmaGo

```bash
# 1. Minikube
minikube start --memory=8192 --cpus=4

# 2. Imágenes (desde Implementacion K8S/Codigo)
cd k8s
./build-images.sh

# 3. Desplegar
./apply-k8s.sh

# 4. Port-forward (Windows: usar 127.0.0.1)
./port-forward.sh
```

**URLs:**

- UI: http://127.0.0.1:4200
- API Gateway: http://127.0.0.1:5000
- Grafana (con alerting provisionado): http://127.0.0.1:3000
- Kibana: http://127.0.0.1:5601
- Prometheus: http://127.0.0.1:9090
- Jaeger (trazas): http://127.0.0.1:16686

**Componentes desplegados por `apply-k8s.sh`:**

- App: UI, API Gateway, Users Service, Pharmacy Service, SQL Server.
- Telemetría: OTel collector, Prometheus, Grafana (con dashboards + 5 reglas de alerta), Elasticsearch, Kibana, Fluent Bit (logs), Node Exporter (host), kube-state-metrics (pods/deployments), Jaeger (trazas).
