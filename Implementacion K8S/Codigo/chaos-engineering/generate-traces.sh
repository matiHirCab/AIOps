#!/bin/bash
# Genera trafico GET y POST variado hacia el API Gateway para poblar trazas en Kibana.
# Requiere port-forward activo en localhost:5000 (pharmago-api-gateway).
# Uso: ./generate-traces.sh [iteraciones]

BASE="http://localhost:5000"
ITERS="${1:-50}"

echo "==> Login como admin..."
ADMIN_TOKEN=$(curl -s -X POST "$BASE/api/login" \
  -H "Content-Type: application/json" \
  -d '{"userName":"admin","password":"Abcdef12."}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

echo "==> Login como empleado..."
EMP_TOKEN=$(curl -s -X POST "$BASE/api/login" \
  -H "Content-Type: application/json" \
  -d '{"userName":"empleado01","password":"Abcdef12."}' | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

if [ -z "$ADMIN_TOKEN" ]; then
  echo "ERROR: no se pudo obtener token de admin. Verifica el port-forward en :5000."
  exit 1
fi

echo "Admin token: ${ADMIN_TOKEN:0:8}..."
echo "Empleado token: ${EMP_TOKEN:0:8}..."
echo "Enviando $ITERS iteraciones de trafico mixto..."

send_gets() {
  curl -s -o /dev/null "$BASE/api/drug" &
  curl -s -o /dev/null "$BASE/api/pharmacy" &
  curl -s -o /dev/null "$BASE/api/drug/1" &
  curl -s -o /dev/null "$BASE/api/drug/2" &
  curl -s -o /dev/null "$BASE/api/pharmacy/1" -H "Authorization: $ADMIN_TOKEN" &
  curl -s -o /dev/null "$BASE/test-health" &
  curl -s -o /dev/null "$BASE/api/purchases" -H "Authorization: $ADMIN_TOKEN" &
  curl -s -o /dev/null "$BASE/api/unitmeasure" -H "Authorization: $ADMIN_TOKEN" &
  curl -s -o /dev/null "$BASE/api/presentation" -H "Authorization: $ADMIN_TOKEN" &
}

send_posts() {
  curl -s -o /dev/null -X POST "$BASE/api/login" \
    -H "Content-Type: application/json" \
    -d '{"userName":"admin","password":"Abcdef12."}' &

  curl -s -o /dev/null -X POST "$BASE/api/login" \
    -H "Content-Type: application/json" \
    -d '{"userName":"empleado01","password":"Abcdef12."}' &

  curl -s -o /dev/null -X POST "$BASE/api/login" \
    -H "Content-Type: application/json" \
    -d '{"userName":"noexiste","password":"wrongpass"}' &

  curl -s -o /dev/null -X POST "$BASE/api/pharmacy" \
    -H "Content-Type: application/json" \
    -H "Authorization: $ADMIN_TOKEN" \
    -d '{"name":"FarmaciaTest","address":"Calle Falsa 123"}' &

  curl -s -o /dev/null -X POST "$BASE/api/drug" \
    -H "Content-Type: application/json" \
    -H "Authorization: $EMP_TOKEN" \
    -d '{"name":"DrugTest","symptom":"test","prescription":false,"price":10.0,"stock":5,"unitMeasure":{"name":"mg"},"presentation":{"name":"Tablet"},"pharmacyId":1}' &
}

for i in $(seq 1 "$ITERS"); do
  send_gets
  send_posts
  if [ $((i % 10)) -eq 0 ]; then
    wait
    echo "  Iteracion $i/$ITERS completada"
  fi
done

wait
echo "==> Listo. Revisa Kibana APM -- deberias ver operaciones GET y POST ahora."
