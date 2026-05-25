# Telemetría — Requerimiento 4 (Resumen para el equipo)

Documento de la branch `feature/telemetry-req-4`: qué pedía la rúbrica de **Telemetría**, qué ya existía, qué agregamos y cómo verificarlo.

Checklist detallado con screenshots: [`telemetria-checklist.md`](telemetria-checklist.md).

> **Criterio:** *"Ya teníamos"* = al empezar esta branch. *"Agregamos"* = trabajo nuevo en `feature/telemetry-req-4`.

---

## 1. Qué pedía el requerimiento

### Texto de la rúbrica (Telemetría — 5 pts)

La aplicación debe contar con:

| # | Ítem | Detalle |
|---|---|---|
| 1 | **Logs estructurados JSON** | Consultables en Kibana + Elasticsearch |
| 2 | **Trazas OTLP** | Con propagación de contexto (OpenTelemetry) |
| 3 | **Métricas de aplicación** | Mínimo **5**, recolectadas vía OTLP → Prometheus → Grafana |
| 4 | **Métricas de infraestructura** | Mínimo **5** a nivel pod/contenedor y **5** a nivel nodo (CPU, memoria, storage, red) |
| 5 | **Alertas en Grafana** | Mínimo **5**, sobre las métricas definidas |

### Qué cubría esta branch

Al iniciar `feature/telemetry-req-4` **logs y métricas de aplicación ya estaban OK**, pero faltaban piezas para cerrar el requerimiento completo. Esta branch completó:

| Gap al iniciar la branch | Trabajo de la branch |
|---|---|
| Trazas OTLP sin backend ni pipeline | Jaeger + `WithTracing()` + pipeline `traces` |
| Métricas pod incompletas (faltaban restarts, pods ready) | kube-state-metrics + dashboard infra ampliado |
| 0 alertas en Grafana | 5 alertas provisionadas vía ConfigMap |
| Documentación dispersa | Checklist + diagrama + este resumen |

---

## 2. Qué teníamos y qué no teníamos

### ✅ Ya teníamos (al iniciar la branch)

| Ítem | Qué había | Estado respecto a la rúbrica |
|---|---|---|
| **Logs JSON** | Formatter JSON en .NET, `StructuredLogger.cs`, Fluent Bit → ES → Kibana, correlation ID | **Cumplido** — no fue foco de esta branch |
| **Métricas de aplicación** | 6 métricas en `CustomMetrics.cs`, export OTLP/Prometheus, dashboard overview en Grafana | **Cumplido** (mínimo 5) |
| **Métricas de nodo** | node-exporter: CPU, memoria, disco (+ red e I/O agregados en dashboard) | **Cumplido** (mínimo 5) |
| **Métricas de pod (parcial)** | cAdvisor: CPU y memoria por pod | **Parcial** — faltaban métricas de estado K8s (restarts, ready) |
| **OTLP → Prometheus → Grafana** | Collector, Prometheus (scrape 5s), dashboards app e infra base | **Cumplido** |
| **Correlation ID** | Gateway genera `X-Correlation-ID`, propagado vía YARP, presente en logs | **Cumplido** para logs; **no alcanzaba** para trazas OTel |
| **Instrumentación HTTP en métricas** | `AddAspNetCoreInstrumentation()` / `AddHttpClientInstrumentation()` dentro de `WithMetrics()` | Solo generaba **métricas**, no spans |

### ❌ Lo que faltaba (al iniciar la branch)

| Ítem | Qué faltaba |
|---|---|
| **Trazas OTLP** | `WithTracing()`, export OTLP de spans, pipeline `traces` en collector, Jaeger |
| **Propagación cross-service (trazas)** | Trace context W3C (`traceparent`) entre Gateway y microservicios |
| **Métricas pod (completar mínimo 5)** | Pod restarts y pods ready (requieren kube-state-metrics) |
| **Alertas Grafana** | Ninguna alerta provisionada (checklist decía "Pendiente de implementación") |

---

## 3. Qué agregamos en esta branch (con justificación)

### 3.1 Trazas OTLP

| Qué agregamos | Archivo(s) | Justificación |
|---|---|---|
| **Jaeger all-in-one v1.54** (UI `:16686`, OTLP `:4317`) | `jaeger-deployment.yaml`, `jaeger-service.yaml` | Backend para almacenar y visualizar trazas (ítem #2 de la rúbrica) |
| **Pipeline `traces`** en el collector | `otel-collector-config.yaml` | Reenvía spans OTLP de servicios → Jaeger |
| **`WithTracing()`** en Gateway, Users, Pharmacy | `Program.cs` (Gateway), `TelemetryExtensions.cs` (Factory de cada servicio) | Activa generación de spans en los 3 deployments de K8s |
| **`AddAspNetCoreInstrumentation()`** en bloque de trazas | Mismos archivos | Span automático por request HTTP entrante |
| **`AddHttpClientInstrumentation()`** en bloque de trazas | Mismos archivos | Spans en llamadas salientes + header `traceparent` para propagación cross-service |
| **`AddOtlpExporter()`** para trazas | Mismos archivos | Cumple "trazas de acuerdo a OTLP" |
| **Paquete OTLP exporter** en ApiGateway | `PharmaGo.ApiGateway.csproj` | El gateway no tenía el exportador; sin él no enviaba trazas |
| **Upgrade / alineación paquetes OTel 1.7.x** | `.csproj` de Gateway, Users, Pharmacy, Factory | Versiones viejas/mezcladas impedían que el `TracerProvider` arrancara en runtime |
| **Rebuild imágenes Docker (`:v2`)** | Operación de despliegue | Imágenes viejas no incluían el DLL del exportador OTLP de trazas |

**Qué no agregamos:** spans custom de negocio (`ActivitySource`). La rúbrica pide propagación **entre servicios**; la instrumentación HTTP automática cubre Gateway → microservicio sin código extra en controllers.

**Qué aparece en Jaeger** (automático, por request HTTP):

| Servicio | Ejemplos de operaciones |
|---|---|
| `PharmaGo.ApiGateway` | `GET /api/pharmacy/{**catch-all}` |
| `PharmaGo.PharmacyService` | `GET /api/pharmacy`, `POST /api/purchases` |
| `PharmaGo.UsersService` | `POST /api/login`, `GET /api/users` |

### 3.2 Métricas de infraestructura (completar mínimo pod)

| Qué agregamos | Archivo(s) | Justificación |
|---|---|---|
| **kube-state-metrics** (Deployment, RBAC, Service) | `kube-state-metrics-*.yaml` | Expone métricas de estado K8s (restarts, ready) que cAdvisor no tiene |
| **Scrape de kube-state-metrics** en Prometheus | `prometheus-config.yaml` | Para que Prometheus recolecte las nuevas métricas |
| **Paneles en dashboard infra** — pod restarts, pods ready, red/IO de nodo | `grafana-dashboard-infra.yaml` | Visualizar las métricas faltantes; cierra el mínimo de 5 métricas pod |

Métricas pod habilitadas por este trabajo:

| Métrica | Fuente | ¿Nueva en branch? |
|---|---|---|
| CPU por pod | cAdvisor | No — pre-existente |
| Memoria por pod | cAdvisor | No — pre-existente |
| Pod restarts | kube-state-metrics | **Sí** |
| Pods ready | kube-state-metrics | **Sí** |
| Red rx/tx por pod | cAdvisor | Pre-existente en Prometheus; no en dashboard |

### 3.3 Alertas en Grafana (mínimo 5)

| # | Alerta | Umbral | Justificación |
|---|---|---|---|
| 1 | CPU nodo > 80% | 2 min | Detecta saturación de infra |
| 2 | Memoria nodo > 85% | 2 min | Detecta presión de memoria en el nodo |
| 3 | Pod restarts > 3 en 5 min | Inmediato | Detecta inestabilidad de pods (usa kube-state-metrics) |
| 4 | Error rate HTTP > 5% | 1 min | Detecta degradación de la aplicación |
| 5 | Latencia promedio > 500 ms | 2 min | Detecta requests lentos |

Provisionadas vía ConfigMap: `grafana-alerting.yaml`, montadas en el deployment de Grafana.

### 3.4 Documentación e infra visual

| Qué agregamos | Archivo(s) | Justificación |
|---|---|---|
| Checklist de telemetría con estado y screenshots | `telemetria-checklist.md`, `imagenes/` | Evidencia para la entrega y la defensa |
| Diagrama de despliegue con Jaeger, kube-state-metrics y flujos de telemetría | `diagrama-despliegue-k8s.puml` | Documentar componentes y conexiones de la plataforma |

---

## 4. Qué tenemos ahora

| Ítem de la rúbrica | Estado | Evidencia |
|---|---|---|
| Logs JSON en Kibana | OK | [`telemetria-checklist.md`](telemetria-checklist.md) § Logs + screenshot Kibana |
| Trazas OTLP + propagación cross-service | OK | Jaeger — 3 servicios, trazas multi-span Gateway → microservicio |
| Métricas aplicación (≥ 5) | OK | 6 métricas en `CustomMetrics.cs`, dashboard overview |
| Métricas nodo (≥ 5) | OK | node-exporter, dashboard infra |
| Métricas pod (≥ 5) | OK | cAdvisor + kube-state-metrics |
| OTLP → Prometheus → Grafana | OK | Collector `:8889`, scrape 5s |
| Alertas Grafana (≥ 5) | OK | 5 reglas en `grafana-alerting.yaml` |

---

## 5. Cómo probarlo

### Prerrequisitos

```bash
kubectl get pods -n pharmago
```

Pods clave: `jaeger`, `otlp-collector`, `prometheus`, `grafana`, `kube-state-metrics`, `elasticsearch`, `kibana`.

### Trazas — Jaeger

```bash
kubectl port-forward -n pharmago deployment/jaeger 16686:16686 &
kubectl port-forward -n pharmago deployment/pharmago-api-gateway 5000:80 &
curl http://localhost:5000/api/pharmacy
```

Abrir `http://localhost:16686` → Service `PharmaGo.ApiGateway` → Find Traces → verificar **más de un span** (Gateway + microservicio).

Opcional — confirmar collector:

```bash
kubectl logs -n pharmago deployment/otlp-collector --tail=20 | grep traces
```

### Métricas — Prometheus y Grafana

```bash
kubectl port-forward -n pharmago deployment/prometheus 9090:9090 &
kubectl port-forward -n pharmago deployment/grafana 3000:3000 &
```

- **Prometheus** (`http://localhost:9090`): probar queries como `kube_pod_status_ready{namespace="pharmago"}` o `pharmago_http_requests_total`.
- **Grafana** (`http://localhost:3000`, admin/admin): dashboards *PharmaGo Overview* e *Infra*.

### Logs — Kibana

```bash
kubectl port-forward -n pharmago deployment/kibana 5601:5601 &
```

Abrir `http://localhost:5601` → data view `pharmago-logs-*` → filtrar por `correlation_id` o `service`.

### Alertas — Grafana

En Grafana → **Alerting** → **Alert rules**: deben aparecer las 5 reglas provisionadas (CPU nodo, memoria nodo, pod restarts, error rate, latencia).

---

## Resumen

| Ítem | Al iniciar la branch | Agregamos en `feature/telemetry-req-4` |
|---|---|---|
| Logs JSON / Kibana | OK | — (ya cumplido) |
| Métricas aplicación (≥ 5) | OK | — (ya cumplido) |
| Métricas nodo (≥ 5) | OK | Paneles red/IO de nodo en dashboard |
| Métricas pod (≥ 5) | Parcial | kube-state-metrics + paneles restarts/ready |
| Trazas OTLP | Faltaba | Jaeger + pipeline + `WithTracing()` en .NET |
| Alertas Grafana (≥ 5) | Faltaba | 5 reglas provisionadas |
| Documentación | Parcial | Checklist, diagrama, este resumen |
