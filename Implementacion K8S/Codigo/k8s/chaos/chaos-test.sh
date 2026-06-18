#!/bin/bash
# =============================================================================
# chaos-test.sh — Script de ingeniería del caos para PharmaGo
# =============================================================================
#
# Ejecuta 6 escenarios de caos requeridos por la rúbrica:
#   1. Inyección de requests (flood)
#   2. Sobrecarga de CPU
#   3. Sobrecarga de memoria
#   4. Sobrecarga de storage
#   5. Interrupción de tráfico de red
#   6. Desconexión de componentes internos
#
# Uso:
#   ./chaos-test.sh                   # Ejecutar todos los escenarios
#   ./chaos-test.sh --scenario 3      # Ejecutar solo el escenario 3
#   ./chaos-test.sh --duration 30     # Duración por escenario (default: 60s)
#   ./chaos-test.sh --dry-run         # Solo mostrar qué haría
#
# Prerequisitos:
#   - kubectl configurado contra el cluster con namespace pharmago
#   - port-forward activo (./port-forward.sh) para el escenario 1
#   - hey instalado (go install github.com/rakyll/hey@latest) para el escenario 1
#     Si no está instalado, se usa curl como fallback
# =============================================================================

set -euo pipefail

NAMESPACE="pharmago"
DURATION="${DURATION:-60}"
PAUSE="${PAUSE:-30}"
SCENARIO="${SCENARIO:-all}"
DRY_RUN=false
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_URL="${API_URL:-http://127.0.0.1:5000}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- Argumentos ---
while [[ $# -gt 0 ]]; do
    case $1 in
        --scenario) SCENARIO="$2"; shift 2 ;;
        --duration) DURATION="$2"; shift 2 ;;
        --pause)    PAUSE="$2"; shift 2 ;;
        --dry-run)  DRY_RUN=true; shift ;;
        --help|-h)
            head -25 "$0" | tail -18
            exit 0
            ;;
        *) echo "Argumento desconocido: $1"; exit 1 ;;
    esac
done

# --- Helpers ---
log()     { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*"; }

separator() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

run_scenario() {
    local num="$1" name="$2"
    separator
    echo -e "${YELLOW}  ESCENARIO $num/6: $name${NC}"
    echo -e "  Duración: ${DURATION}s"
    separator
}

wait_recovery() {
    log "Esperando recuperación del sistema (${PAUSE}s)..."
    if ! $DRY_RUN; then
        sleep "$PAUSE"
        # Verificar estado de pods
        kubectl get pods -n "$NAMESPACE" -l 'app in (pharmago-api-gateway,pharmago-users-service,pharmago-pharmacy-service,pharmago-db)' \
            --no-headers 2>/dev/null | while read line; do
            echo "  $line"
        done
    fi
    ok "Pausa de recuperación completada"
}

should_run() {
    [[ "$SCENARIO" == "all" || "$SCENARIO" == "$1" ]]
}

check_pods_ready() {
    log "Verificando estado inicial de pods..."
    kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | while read line; do
        echo "  $line"
    done
    echo ""
}

# =============================================================================
# ESCENARIO 1: Inyección de requests (flood)
# Objetivo: saturar el API Gateway con requests concurrentes
# Alertas esperadas: HTTP Error Rate > 5%, Avg Latency > 500ms
# Observable en: Grafana Overview (requests/sec, 429s), Kibana (rate limit logs)
# =============================================================================
scenario_1_request_flood() {
    run_scenario 1 "Inyección de requests (flood)"

    if $DRY_RUN; then
        log "[DRY-RUN] Enviaría requests concurrentes a $API_URL/api/drug durante ${DURATION}s"
        return
    fi

    local endpoints=(
        "/api/drug"
        "/api/pharmacy"
        "/api/user"
    )

    if command -v hey &>/dev/null; then
        log "Usando 'hey' para flood de requests..."
        for ep in "${endpoints[@]}"; do
            log "Flood a ${API_URL}${ep} (50 workers, ${DURATION}s)..."
            hey -z "${DURATION}s" -c 50 -q 100 "${API_URL}${ep}" 2>&1 | tail -20 &
        done
        wait
    else
        warn "'hey' no está instalado. Usando curl como fallback..."
        warn "Para mejores resultados: go install github.com/rakyll/hey@latest"
        local end_time=$((SECONDS + DURATION))
        local count=0
        local rate_limited=0
        local errors=0

        while [ $SECONDS -lt $end_time ]; do
            for ep in "${endpoints[@]}"; do
                code=$(curl -s -o /dev/null -w "%{http_code}" \
                    -H "X-Real-IP: 10.0.0.$((RANDOM % 5 + 1))" \
                    "${API_URL}${ep}" 2>/dev/null || echo "000")
                count=$((count + 1))

                if [ "$code" = "429" ]; then
                    rate_limited=$((rate_limited + 1))
                elif [ "$code" != "200" ] && [ "$code" != "404" ]; then
                    errors=$((errors + 1))
                fi
            done
        done

        echo ""
        log "Resultados del flood:"
        echo "  Total requests: $count"
        echo "  Rate Limited (429): $rate_limited"
        echo "  Errores: $errors"
    fi

    ok "Escenario 1 completado"
    echo ""
    log "Verificar en Grafana:"
    echo "  - Overview > Requests/sec: pico de tráfico"
    echo "  - Overview > Status Codes: 429 Rate Limited"
    echo "  - Overview > Error Rate: incremento"
    echo "  - Overview > Latency: incremento"
    log "Verificar en Kibana:"
    echo "  - Buscar logs con StatusCode:429"
    echo "  - Buscar logs del UserRateLimitMiddleware"
}

# =============================================================================
# ESCENARIO 2: Sobrecarga de CPU
# Objetivo: saturar CPU dentro de pods de backend
# Alertas esperadas: CPU Node > 80%
# Observable en: Grafana Infra (CPU per pod, Node CPU %)
# =============================================================================
scenario_2_cpu_stress() {
    run_scenario 2 "Sobrecarga de CPU"

    if $DRY_RUN; then
        log "[DRY-RUN] Ejecutaría stress en CPU dentro de pods de pharmacy-service"
        return
    fi

    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app=pharmago-pharmacy-service \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod" ]; then
        fail "No se encontró pod de pharmacy-service"
        return 1
    fi

    log "Pod objetivo: $pod"
    log "Instalando stress-ng y ejecutando stress de CPU (${DURATION}s)..."

    kubectl exec -n "$NAMESPACE" "$pod" -- stress-ng --cpu 4 --timeout "${DURATION}s" --metrics-brief \
        2>&1 || warn "El comando de stress terminó (esto es esperado)"

    ok "Escenario 2 completado"
    echo ""
    log "Verificar en Grafana:"
    echo "  - Infra > CPU per Pod: pico en pharmacy-service"
    echo "  - Infra > Node CPU %: incremento general"
    echo "  - Alerta 'CPU node > 80%' debería dispararse"
}

# =============================================================================
# ESCENARIO 3: Sobrecarga de memoria
# Objetivo: provocar OOMKill y demostrar auto-recuperación
# Alertas esperadas: Memory Node > 85%, Pod Restarts > 3 in 5min
# Observable en: Grafana Infra (Memory per pod, Pod Restarts)
#
# En Windows (WSL2) el OOMKill ocurre naturalmente porque los cgroups se
# enforcean correctamente. En macOS Docker Desktop no enforcea memory limits,
# por lo que si stress-ng no provoca el OOMKill, el script mata el pod
# manualmente como fallback.
# =============================================================================
scenario_3_memory_stress() {
    run_scenario 3 "Sobrecarga de memoria"

    if $DRY_RUN; then
        log "[DRY-RUN] Estresaría memoria del pod de users-service hasta OOMKill"
        return
    fi

    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app=pharmago-users-service \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod" ]; then
        fail "No se encontró pod de users-service"
        return 1
    fi

    log "Pod objetivo: $pod (limit: 384Mi)"
    log "Estresando memoria para provocar OOMKill..."

    # Intentar provocar OOMKill real con stress-ng
    # --vm-keep: no libera la memoria entre iteraciones
    # En WSL2/Linux esto debería exceder el memory limit y provocar OOMKill
    kubectl exec -n "$NAMESPACE" "$pod" -- stress-ng --vm 2 --vm-bytes 512M --vm-keep --timeout "${DURATION}s" --metrics-brief \
        2>&1 || true

    sleep 5

    # Verificar si el pod fue matado por OOMKill
    local reason
    reason=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null)

    if [ "$reason" = "OOMKilled" ]; then
        ok "OOMKill real detectado — Kubernetes mató el pod por exceder el memory limit"
    else
        # Fallback para macOS: Docker Desktop no enforcea memory limits via cgroups
        warn "OOMKill no ocurrió (normal en Docker Desktop macOS)"
        log "Fallback: matando pod manualmente para demostrar auto-recuperación..."
        kubectl delete pod "$pod" -n "$NAMESPACE" --grace-period=0 --force 2>&1
    fi

    log "Esperando a que K8s recree el pod automáticamente..."
    sleep 15
    kubectl get pods -n "$NAMESPACE" -l app=pharmago-users-service --no-headers

    # Verificar que el nuevo pod está ready
    kubectl wait --for=condition=ready pod -l app=pharmago-users-service -n "$NAMESPACE" --timeout=60s 2>&1 || \
        warn "Timeout esperando recuperación"

    ok "Escenario 3 completado"
    echo ""
    log "Verificar en Grafana:"
    echo "  - Infra > Memory per Pod: spike en users-service seguido de caída"
    echo "  - Infra > Pod Restarts: incremento"
    echo "  - El pod fue recreado automáticamente por Kubernetes"
    log "Verificar en Kibana:"
    echo "  - Logs de crash y reinicio del pod"
}

# =============================================================================
# ESCENARIO 4: Sobrecarga de storage
# Objetivo: llenar disco del pod de base de datos
# Observable en: Grafana Infra (Disk Available %, Disk I/O)
# =============================================================================
scenario_4_storage_stress() {
    run_scenario 4 "Sobrecarga de storage"

    if $DRY_RUN; then
        log "[DRY-RUN] Llenaría disco en pod de base de datos"
        return
    fi

    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app=pharmago-db \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    if [ -z "$pod" ]; then
        fail "No se encontró pod de base de datos"
        return 1
    fi

    log "Pod objetivo: $pod"
    log "Escribiendo archivo de 500MB en /tmp para saturar I/O..."

    kubectl exec -n "$NAMESPACE" "$pod" -- bash -c "
        echo 'Escribiendo 500MB en /tmp/chaos-fill...'
        dd if=/dev/zero of=/tmp/chaos-fill bs=1M count=500 2>&1
        echo 'Disco ocupado. Tamaño del archivo:'
        ls -lh /tmp/chaos-fill
        echo 'Espacio en disco:'
        df -h /tmp 2>/dev/null || true
        echo 'Esperando ${DURATION}s con disco lleno...'
        sleep ${DURATION}
    " 2>&1

    # Limpiar
    log "Limpiando archivo de stress..."
    kubectl exec -n "$NAMESPACE" "$pod" -- rm -f /tmp/chaos-fill 2>/dev/null || true

    ok "Escenario 4 completado"
    echo ""
    log "Verificar en Grafana:"
    echo "  - Infra > Disk Available %: caída durante el escenario"
    echo "  - Infra > Disk I/O Write: pico durante escritura"
}

# =============================================================================
# ESCENARIO 5: Interrupción de tráfico de red
# Objetivo: simular pérdida de conectividad eliminando el pod del API Gateway
# Alertas esperadas: HTTP Error Rate > 5%, Pod Restarts
# Observable en: Grafana Overview (5xx/000), Grafana Infra (restarts), Kibana
# Nota: usa delete pod en lugar de NetworkPolicy porque minikube con bridge CNI
#       no enforcea NetworkPolicies. En un cluster con Calico se puede usar
#       network-policy-block.yaml en su lugar.
# =============================================================================
scenario_5_network_interruption() {
    run_scenario 5 "Interrupción de tráfico de red"

    if $DRY_RUN; then
        log "[DRY-RUN] Eliminaría el pod del API Gateway para simular pérdida de red"
        return
    fi

    local pod
    pod=$(kubectl get pods -n "$NAMESPACE" -l app=pharmago-api-gateway \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

    log "Pod objetivo: $pod"
    log "Eliminando pod del API Gateway para simular interrupción de red..."
    kubectl delete pod "$pod" -n "$NAMESPACE" --grace-period=0 --force 2>&1

    log "Gateway eliminado. Enviando requests durante ${DURATION}s..."
    log "(las requests fallarán hasta que K8s recree el pod)"

    local end_time=$((SECONDS + DURATION))
    local count=0
    local errors=0
    local recovered=false

    while [ $SECONDS -lt $end_time ]; do
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 \
            "${API_URL}/api/drug" 2>/dev/null || echo "000")
        count=$((count + 1))

        if [ "$code" = "000" ] || [ "$code" = "502" ] || [ "$code" = "503" ]; then
            errors=$((errors + 1))
        elif [ "$code" = "200" ] && ! $recovered; then
            recovered=true
            log "Gateway recuperado después de $count requests"
        fi

        if [ $((count % 10)) -eq 0 ]; then
            echo "  [$count requests] Último: HTTP $code | Errores: $errors"
        fi

        sleep 0.5
    done

    echo ""
    log "Resultados de interrupción de red:"
    echo "  Total requests: $count"
    echo "  Errores (000/502/503): $errors"
    if $recovered; then
        echo "  Recuperación: SÍ (automática)"
    else
        echo "  Recuperación: aún en progreso"
    fi

    echo ""
    log "Estado del gateway:"
    kubectl get pods -n "$NAMESPACE" -l app=pharmago-api-gateway --no-headers

    ok "Escenario 5 completado"
    echo ""
    log "Verificar en Grafana:"
    echo "  - Infra > Pod Restarts: incremento en api-gateway"
    echo "  - Overview > Error Rate: pico durante la interrupción"
    log "Verificar en Kibana:"
    echo "  - Logs de terminación y reinicio del gateway"
}

# =============================================================================
# ESCENARIO 6: Desconexión de componentes internos
# Objetivo: apagar la base de datos y observar el efecto cascada
# Alertas esperadas: Pod Restarts > 3 in 5min, HTTP Error Rate > 5%
# Observable en: Grafana (restarts, errors), Jaeger (spans rotos), Kibana (DB errors)
# =============================================================================
scenario_6_component_disconnect() {
    run_scenario 6 "Desconexión de base de datos"

    if $DRY_RUN; then
        log "[DRY-RUN] Escalaría pharmago-db a 0 réplicas"
        return
    fi

    log "Apagando base de datos (scale replicas=0)..."
    kubectl scale deployment pharmago-db -n "$NAMESPACE" --replicas=0 2>&1

    log "Base de datos desconectada. Esperando ${DURATION}s..."
    log "Enviando requests para generar errores observables..."

    local end_time=$((SECONDS + DURATION))
    local count=0
    local errors=0

    while [ $SECONDS -lt $end_time ]; do
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
            "${API_URL}/api/drug" 2>/dev/null || echo "000")
        count=$((count + 1))

        if [ "$code" = "500" ] || [ "$code" = "503" ] || [ "$code" = "000" ]; then
            errors=$((errors + 1))
        fi

        if [ $((count % 10)) -eq 0 ]; then
            echo "  [$count requests] Último código: $code | Errores 5xx: $errors"
        fi

        sleep 0.5
    done

    echo ""
    log "Resultados sin base de datos:"
    echo "  Total requests: $count"
    echo "  Errores 5xx: $errors"

    log "Restaurando base de datos (scale replicas=1)..."
    kubectl scale deployment pharmago-db -n "$NAMESPACE" --replicas=1 2>&1

    log "Esperando a que la base de datos esté ready..."
    kubectl rollout status deployment/pharmago-db -n "$NAMESPACE" --timeout=120s 2>&1 || \
        warn "Timeout esperando a la base de datos"

    ok "Escenario 6 completado"
    echo ""
    log "Verificar en Grafana:"
    echo "  - Overview > Error Rate: pico de 5xx mientras DB estaba caída"
    echo "  - Infra > Pod Restarts: si health checks fallaron"
    echo "  - Alerta 'HTTP Error Rate > 5%' debería dispararse"
    log "Verificar en Jaeger:"
    echo "  - Trazas con spans de error hacia SQL Server"
    log "Verificar en Kibana:"
    echo "  - Buscar logs con 'SqlException' o 'connection refused'"
    echo "  - Health check failures"
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║          CHAOS ENGINEERING TEST — PharmaGo                 ║${NC}"
    echo -e "${RED}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${RED}║  Namespace: $NAMESPACE                                        ║${NC}"
    echo -e "${RED}║  Duración por escenario: ${DURATION}s                              ║${NC}"
    echo -e "${RED}║  Pausa entre escenarios: ${PAUSE}s                              ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if $DRY_RUN; then
        warn "MODO DRY-RUN: no se ejecutarán acciones destructivas"
        echo ""
    fi

    check_pods_ready

    if should_run 1; then scenario_1_request_flood;    wait_recovery; fi
    if should_run 2; then scenario_2_cpu_stress;        wait_recovery; fi
    if should_run 3; then scenario_3_memory_stress;     wait_recovery; fi
    if should_run 4; then scenario_4_storage_stress;    wait_recovery; fi
    if should_run 5; then scenario_5_network_interruption; wait_recovery; fi
    if should_run 6; then scenario_6_component_disconnect; wait_recovery; fi

    separator
    echo -e "${GREEN}  CHAOS TEST FINALIZADO${NC}"
    echo ""
    echo "  Revisar telemetría en:"
    echo "    Grafana:  http://127.0.0.1:3000 (admin/admin)"
    echo "    Kibana:   http://127.0.0.1:5601"
    echo "    Jaeger:   http://127.0.0.1:16686"
    separator
}

main
