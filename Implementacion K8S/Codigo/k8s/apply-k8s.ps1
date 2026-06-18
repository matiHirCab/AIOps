# Script de despliegue para Kubernetes (Minikube)
# Uso: .\apply-k8s.ps1

Write-Host "=== Desplegando PharmaGo en Kubernetes ===" -ForegroundColor Green

# Verificar que kubectl está disponible
if (-not (Get-Command kubectl -ErrorAction SilentlyContinue)) {
    Write-Host "Error: kubectl no está instalado o no está en el PATH" -ForegroundColor Red
    exit 1
}

# Verificar que el cluster Kubernetes está accesible
$nodes = kubectl get nodes -o jsonpath='{.items[*].metadata.name}' 2>&1
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($nodes)) {
    Write-Host "Error: No hay cluster Kubernetes accesible. Si usas Minikube: minikube start (o minikube start --nodes 3)" -ForegroundColor Red
    exit 1
}

# Etiquetar nodos (requerido para que los pods de telemetría se programen)
Write-Host "`n1. Etiquetando nodos..." -ForegroundColor Yellow
$nodeList = $nodes.Trim().Split(" ", [StringSplitOptions]::RemoveEmptyEntries)
if ($nodeList.Count -eq 1) {
    Write-Host "   Cluster de 1 nodo detectado. Etiquetando $($nodeList[0]) con node-type=all" -ForegroundColor Cyan
    kubectl label nodes $nodeList[0] node-type=all --overwrite 2>$null
} elseif ($nodeList.Count -ge 3) {
    Write-Host "   Cluster multi-nodo detectado. Etiquetando nodos..." -ForegroundColor Cyan
    kubectl label nodes minikube node-type=frontend --overwrite 2>$null
    kubectl label nodes minikube-m02 node-type=backend --overwrite 2>$null
    kubectl label nodes minikube-m03 node-type=ops --overwrite 2>$null
} else {
    $firstNode = $nodeList[0]
    Write-Host "   Etiquetando nodo $firstNode con node-type=all (compatibilidad)" -ForegroundColor Cyan
    kubectl label nodes $firstNode node-type=all --overwrite 2>$null
}
Write-Host "   Verificar: kubectl get nodes --show-labels" -ForegroundColor Gray

Write-Host "`n2. Creando namespace..." -ForegroundColor Yellow
kubectl apply -f namespace.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n3. Creando secrets..." -ForegroundColor Yellow
kubectl apply -f secrets\db-secret.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n4. Creando configmaps..." -ForegroundColor Yellow
kubectl apply -f configmaps\prometheus-config.yaml
kubectl apply -f configmaps\otel-collector-config.yaml
kubectl apply -f configmaps\grafana-provisioning.yaml
kubectl apply -f configmaps\grafana-dashboards.yaml
kubectl apply -f configmaps\grafana-dashboard-infra.yaml
kubectl apply -f configmaps\grafana-alerting.yaml
kubectl apply -f configmaps\fluent-bit-config.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n5. Creando StorageClass y PersistentVolumes..." -ForegroundColor Yellow
kubectl apply -f persistent-volumes\storage-class.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

# Eliminar solo PVs huerfanos. No borrar PVs Bound: kubectl delete puede
# quedar bloqueado porque todavia estan asociados a PVCs activos.
Write-Host "   Limpiando PVs huerfanos (Released/Failed)..." -ForegroundColor Cyan
$pvManifests = @{
    "sql-pv" = "persistent-volumes\sql-pv.yaml"
    "elasticsearch-pv" = "persistent-volumes\elasticsearch-pv.yaml"
    "prometheus-pv" = "persistent-volumes\prometheus-pv.yaml"
    "grafana-pv" = "persistent-volumes\grafana-pv.yaml"
}
$pvNames = $pvManifests.Keys
$pvsToApply = @()
foreach ($pv in $pvNames) {
    $phase = kubectl get pv $pv -o jsonpath='{.status.phase}' 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($phase)) {
        $pvsToApply += $pv
        continue
    }

    if ($phase -eq "Released" -or $phase -eq "Failed") {
        kubectl delete pv $pv --ignore-not-found=true 2>$null
        $pvsToApply += $pv
    } else {
        Write-Host "   Conservando $pv ($phase)" -ForegroundColor Gray
    }
}
Start-Sleep -Seconds 2

foreach ($pv in $pvsToApply) {
    kubectl apply -f $pvManifests[$pv]
    if ($LASTEXITCODE -ne 0) { exit 1 }
}

Write-Host "`n6. Desplegando base de datos..." -ForegroundColor Yellow
kubectl apply -f services\ops\db-service.yaml
kubectl apply -f deployments\ops\db-deployment.yaml
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n   Esperando a que la base de datos esté lista..." -ForegroundColor Yellow
kubectl wait --for=condition=available deployment/pharmago-db -n pharmago --timeout=300s
if ($LASTEXITCODE -eq 0) {
    Write-Host "   Base de datos lista!" -ForegroundColor Green
} else {
    Write-Host "   Timeout esperando la base de datos. Continuando..." -ForegroundColor Yellow
}

Write-Host "`n7. Desplegando servicios de observabilidad..." -ForegroundColor Yellow
# Elasticsearch primero
kubectl apply -f services\ops\elasticsearch-service.yaml
kubectl apply -f deployments\ops\elasticsearch-deployment.yaml

# Esperar a que Elasticsearch esté listo
Write-Host "   Esperando a que Elasticsearch esté listo..." -ForegroundColor Yellow
kubectl wait --for=condition=available deployment/elasticsearch -n pharmago --timeout=300s
if ($LASTEXITCODE -eq 0) {
    Write-Host "   Elasticsearch listo!" -ForegroundColor Green
} else {
    Write-Host "   Timeout esperando Elasticsearch. Continuando..." -ForegroundColor Yellow
}

# Jaeger (backend de trazas): debe estar antes del OTel collector,
# que exporta trazas a jaeger:4317.
kubectl apply -f services\ops\jaeger-service.yaml
kubectl apply -f deployments\ops\jaeger-deployment.yaml
Write-Host "   Jaeger desplegado (UI en puerto 16686)." -ForegroundColor Cyan

# OTel collector
kubectl apply -f services\ops\otel-collector-service.yaml
kubectl apply -f deployments\ops\otel-collector-deployment.yaml

# kube-state-metrics: métricas a nivel de pod/deployment (restarts, ready, ...).
# Se aplica antes de Prometheus para que el job 'kube-state-metrics' tenga target.
kubectl apply -f deployments\ops\kube-state-metrics-serviceaccount.yaml
kubectl apply -f deployments\ops\kube-state-metrics-clusterrole.yaml
kubectl apply -f deployments\ops\kube-state-metrics-clusterrolebinding.yaml
kubectl apply -f deployments\ops\kube-state-metrics-deployment.yaml
Write-Host "   kube-state-metrics desplegado (servicio en puerto 8080)." -ForegroundColor Cyan

kubectl apply -f deployments\ops\prometheus-serviceaccount.yaml
kubectl apply -f deployments\ops\prometheus-clusterrole.yaml
kubectl apply -f deployments\ops\prometheus-clusterrolebinding.yaml
kubectl apply -f services\ops\prometheus-service.yaml
kubectl apply -f deployments\ops\prometheus-deployment.yaml
kubectl apply -f services\ops\node-exporter-service.yaml
kubectl apply -f deployments\ops\node-exporter-daemonset.yaml

# Grafana: el ConfigMap grafana-alerting ya fue aplicado en el paso 4,
# por lo que las reglas se montan al iniciar el pod.
kubectl apply -f services\ops\grafana-service.yaml
kubectl apply -f deployments\ops\grafana-deployment.yaml

# Si Grafana ya estaba corriendo en un despliegue anterior, reiniciar para que
# recargue las reglas de alerting provisionadas.
kubectl rollout restart deployment/grafana -n pharmago 2>$null

kubectl apply -f services\ops\kibana-service.yaml
kubectl apply -f deployments\ops\kibana-deployment.yaml

if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n8. Desplegando servicios backend..." -ForegroundColor Yellow
kubectl apply -f services\backend\users-service-service.yaml
kubectl apply -f deployments\backend\users-service-deployment.yaml

kubectl apply -f services\backend\pharmacy-service-service.yaml
kubectl apply -f deployments\backend\pharmacy-service-deployment.yaml

kubectl apply -f services\backend\api-gateway-service.yaml
kubectl apply -f deployments\backend\api-gateway-deployment.yaml

if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n9. Desplegando frontend..." -ForegroundColor Yellow
kubectl apply -f services\frontend\ui-service.yaml
kubectl apply -f deployments\frontend\ui-deployment.yaml

if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "`n=== Despliegue completado ===" -ForegroundColor Green
Write-Host "`nVerificando estado de los pods..." -ForegroundColor Yellow
kubectl get pods -n pharmago -o wide

Write-Host "`nPara ver los servicios expuestos:" -ForegroundColor Cyan
Write-Host "  Frontend:     minikube service pharmago-ui -n pharmago --url" -ForegroundColor White
Write-Host "  Grafana:      minikube service grafana -n pharmago --url" -ForegroundColor White
Write-Host "  Kibana:       minikube service kibana -n pharmago --url" -ForegroundColor White
Write-Host "  Prometheus:   minikube service prometheus -n pharmago --url" -ForegroundColor White
Write-Host "  Jaeger:       minikube service jaeger -n pharmago --url" -ForegroundColor White

