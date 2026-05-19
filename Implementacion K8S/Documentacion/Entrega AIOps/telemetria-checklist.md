# Telemetria - Checklist de requerimientos

## Logs estructurados en JSON

| Requerimiento | Estado | Detalle |
|---|---|---|
| Logs en formato JSON | OK | .NET Console JSON formatter en los 3 microservicios (`appsettings.json`) |
| Campos estructurados (timestamp, level, service) | OK | `StructuredLogger.cs` agrega `timestamp_utc`, `level`, `service`, `correlation_id` |
| Eventos de negocio con tokens | OK | Tokens como `EVTLGOK` (login), `EVTPUCR` (purchase), etc. |
| Recoleccion de logs | OK | Fluent Bit como DaemonSet, parsea JSON de .NET y envia a Elasticsearch |
| Consulta de logs en Kibana | OK | Index pattern `pharmago-logs-*`, campos buscables via KQL |

## Trazas OTLP

| Requerimiento | Estado | Detalle |
|---|---|---|
| Propagacion de contexto | OK | `X-Correlation-ID` generado en API Gateway y propagado a servicios via YARP |
| Correlation ID en logs | OK | Incluido como campo `correlation_id` en todos los logs JSON |
| OTLP Collector recibe telemetria | OK | gRPC en puerto 4317 |
| Pipeline de traces en collector | FALTA | El collector solo tiene pipeline de metricas, no exporta traces a ningun backend |
| Backend de traces (Jaeger/Zipkin) | FALTA | No hay componente desplegado para almacenar/visualizar traces |

## Metricas de aplicacion (minimo 5)

| # | Metrica | Tipo | Estado |
|---|---|---|---|
| 1 | `login_invocations` | Counter | OK |
| 2 | `pharmago_http_requests_total` | Counter (endpoint/method/status) | OK |
| 3 | `pharmago_http_errors_total` | Counter (endpoint/error_type) | OK |
| 4 | `request_duration` | Histogram (ms) | OK |
| 5 | `pharmago_http_request_duration_milliseconds` | Histogram (endpoint/method) | OK |
| 6 | `active_user_count` | Gauge | OK |

## Metricas de infraestructura - nodo (minimo 5)

| # | Metrica | Fuente | Estado |
|---|---|---|---|
| 1 | CPU usage % | Node Exporter | OK |
| 2 | Memory usage % | Node Exporter | OK |
| 3 | Disk available % | Node Exporter | OK |
| 4 | Filesystem stats | Node Exporter | OK |
| 5 | Network stats | Node Exporter | OK |

## Metricas de infraestructura - pod/contenedor (minimo 5)

| # | Metrica | Fuente | Estado |
|---|---|---|---|
| 1 | CPU por pod | cAdvisor (kubernetes-cadvisor) | OK |
| 2 | Memory por pod | cAdvisor (kubernetes-cadvisor) | OK |
| 3 | Network rx/tx por pod | cAdvisor (kubernetes-cadvisor) | OK |
| 4 | Filesystem usage por pod | cAdvisor (kubernetes-cadvisor) | OK |
| 5 | Container restarts | cAdvisor (kubernetes-cadvisor) | OK |

## Recoleccion y visualizacion

| Requerimiento | Estado | Detalle |
|---|---|---|
| Metricas recolectadas con OTLP | OK | Servicios exportan via OTLP gRPC al collector, que expone en :8889 |
| Prometheus scraping | OK | Scrape cada 5s a: otel-collector, 3 servicios, node-exporter, cadvisor |
| Retencion Prometheus | OK | 30 dias |
| Dashboard Grafana - aplicacion | OK | `pharmago-overview.json`: requests/s, latencia, error rate, throughput, 429s, status codes |
| Dashboard Grafana - infra | OK | `pharmago-infra.json`: CPU nodo, memoria nodo, disco, CPU/memoria por pod |
| Logs en Elasticsearch | OK | Elasticsearch 8.11, indices `pharmago-logs-YYYY.MM.DD` |
| Logs consultables en Kibana | OK | Kibana 8.11, data view `pharmago-logs-*` |

### Dashboard Grafana - Overview
![Dashboard Grafana - Overview](imagenes/grafana-overview-dashboard.png)

### Dashboard Grafana - Infra
![Dashboard Grafana - Infra](imagenes/grafana-infra-dashboard.png)

## Alertas en Grafana (minimo 5)

| # | Alerta | Estado |
|---|---|---|
| 1 | - | FALTA |
| 2 | - | FALTA |
| 3 | - | FALTA |
| 4 | - | FALTA |
| 5 | - | FALTA |

## Resumen

| Categoria | Estado |
|---|---|
| Logs estructurados JSON | OK |
| Trazas OTLP | PARCIAL - falta pipeline de traces en collector |
| Metricas aplicacion (5+) | OK (6 metricas) |
| Metricas infra nodo (5+) | OK (Node Exporter) |
| Metricas infra pod (5+) | OK (cAdvisor) |
| OTLP -> Prometheus -> Grafana | OK |
| Logs en Kibana + ES | OK |
| 5 alertas en Grafana | FALTA |
