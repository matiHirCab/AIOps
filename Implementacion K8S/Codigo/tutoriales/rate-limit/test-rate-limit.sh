#!/bin/bash

# Script simple para testear Rate Limiting en el API Gateway.
# Uso:
#   ./test-rate-limit.sh
#   API_URL=http://127.0.0.1:5000/api/drug TOTAL=120 ./test-rate-limit.sh

API_URL="${API_URL:-http://127.0.0.1:5000/api/drug}"
TOTAL="${TOTAL:-120}"
DELAY="${DELAY:-0.1}"

run_case() {
    local name="$1"
    local header1="$2"
    local header2="$3"
    local success=0
    local rate_limited=0
    local other=0
    local headers=()

    if [ -n "$header1" ]; then
        headers+=("-H" "$header1")
    fi

    if [ -n "$header2" ]; then
        headers+=("-H" "$header2")
    fi

    echo ""
    echo "Caso: $name"
    echo "Endpoint: $API_URL"
    echo "Peticiones: $TOTAL"
    echo ""

    for i in $(seq 1 "$TOTAL"); do
        code=$(curl -s -o /dev/null -w "%{http_code}" "${headers[@]}" "$API_URL")

        if [ "$code" = "200" ]; then
            success=$((success + 1))
            echo "[$i/$TOTAL] OK"
        elif [ "$code" = "429" ]; then
            rate_limited=$((rate_limited + 1))
            echo "[$i/$TOTAL] 429 Rate Limited"
        else
            other=$((other + 1))
            echo "[$i/$TOTAL] HTTP $code"
        fi

        sleep "$DELAY"
    done

    echo ""
    echo "Resultados $name:"
    echo "  Exitosas: $success"
    echo "  Rate Limited (429): $rate_limited"
    echo "  Otros codigos: $other"
}

echo "Test Rate Limiting - API Gateway"
echo "Modo esperado en produccion: IP+User"

run_case "IP sin Authorization" "X-Real-IP: 10.0.0.1"
run_case "Usuario token-demo-a" "X-Real-IP: 10.0.0.2" "Authorization: Bearer token-demo-a"
run_case "Usuario token-demo-b" "X-Real-IP: 10.0.0.3" "Authorization: Bearer token-demo-b"

echo ""
echo "Verificacion de endpoints excluidos"
curl -s -o /dev/null -w "  /health -> HTTP %{http_code}\n" "${API_URL%/api/drug}/health"
curl -s -o /dev/null -w "  /metrics -> HTTP %{http_code}\n" "${API_URL%/api/drug}/metrics"
