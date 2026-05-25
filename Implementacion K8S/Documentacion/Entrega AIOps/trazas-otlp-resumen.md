# Trazas OTLP - Resumen de implementacion

## Estado previo

La infraestructura de telemetria ya tenia metricas funcionando end-to-end (servicios .NET -> OTLP collector -> Prometheus -> Grafana), pero las **trazas no llegaban** al collector. Los servicios tenian `WithTracing()` configurado, compilaban sin errores, y los DLLs de OpenTelemetry estaban presentes en los contenedores. Sin embargo, Jaeger no recibia ninguna traza.

## Que habia que hacer

Agregar trazas distribuidas segun OTLP: los microservicios .NET debian enviar spans al OTLP collector, que los reenviara a Jaeger para visualizacion. Ademas, las trazas debian propagar contexto entre servicios (trace propagation cross-service).

## Que se hizo

### 1. Fix de versiones en `PharmaGo.Factory.csproj`

El proyecto Factory (usado por WebApi) tenia versiones mezcladas de OpenTelemetry:
- `OpenTelemetry` 1.8.0, `Extensions.Hosting` 1.6.0, `Instrumentation.AspNetCore` 1.8.1
- Faltaba el paquete `OpenTelemetry.Instrumentation.Http`

Esto causaba que el `TracerProvider` fallara silenciosamente al inicializarse. Se alinearon todas las versiones a 1.7.0/1.7.1 (compatible con .NET 6).

### 2. Rebuild de imagenes Docker

Las imagenes anteriores no incluian `OpenTelemetry.Exporter.OpenTelemetryProtocol.dll` en el output publicado. El `AddOtlpExporter()` para trazas fallaba en runtime porque el DLL no estaba. Las metricas funcionaban porque usaban `AddPrometheusExporter()` (cuyo DLL si estaba presente).

Se reconstruyeron las 3 imagenes (ApiGateway, UsersService, PharmacyService) y se cargaron en minikube con tag `:v2`.

### 3. Componentes de infraestructura (ya existentes)

- **Jaeger all-in-one v1.54**: desplegado en el nodo ops, recibe trazas via OTLP gRPC en puerto 4317, UI en puerto 16686.
- **OTLP Collector**: pipeline `traces` con `receivers: [otlp]`, `exporters: [otlp/jaeger, debug]`.

## Como verificar que funciona

1. **Iniciar minikube** y verificar que los pods estan corriendo:
   ```bash
   kubectl get pods -n pharmago
   ```

2. **Port-forward a Jaeger y al gateway**:
   ```bash
   kubectl port-forward -n pharmago deployment/jaeger 16686:16686 &
   kubectl port-forward -n pharmago deployment/pharmago-api-gateway 5000:80 &
   ```

3. **Generar trafico** (cualquier request al gateway):
   ```bash
   curl http://localhost:5000/api/pharmacy
   ```

4. **Abrir Jaeger UI** en `http://localhost:16686`:
   - En el dropdown "Service" deben aparecer: `PharmaGo.ApiGateway`, `PharmaGo.PharmacyService`, `PharmaGo.UsersService`
   - Al buscar trazas del ApiGateway con operacion `GET /api/pharmacy/{**catch-all}`, se deben ver spans multi-servicio (Gateway -> PharmacyService)

5. **Verificar en el collector** que esta exportando trazas:
   ```bash
   kubectl logs -n pharmago deployment/otlp-collector --tail=10
   ```
   Deben aparecer lineas con `"otelcol.signal": "traces"`.

## Archivos clave

| Archivo | Descripcion |
|---|---|
| `Backend/PharmaGo.Factory/TelemetryExtensions.cs` | Config de metricas y trazas para WebApi |
| `Backend/PharmaGo.UsersService.Factory/TelemetryExtensions.cs` | Config para UsersService |
| `Backend/PharmaGo.PharmacyService.Factory/TelemetryExtensions.cs` | Config para PharmacyService |
| `Backend/PharmaGo.ApiGateway/Program.cs` | Config inline para el API Gateway |
| `k8s/configmaps/otel-collector-config.yaml` | Pipeline del collector (metricas + traces) |
| `k8s/deployments/ops/jaeger-deployment.yaml` | Deployment de Jaeger |
| `k8s/services/ops/jaeger-service.yaml` | Service de Jaeger (UI + OTLP) |
