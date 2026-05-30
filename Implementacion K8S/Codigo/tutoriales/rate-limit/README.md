# Test Rate Limiting

Script simple para probar el rate limiting Fixed Window del API Gateway.

## Uso

```bash
cd tutoriales/rate-limit
chmod +x test-rate-limit.sh
./test-rate-limit.sh
```

O directamente:

```bash
bash tutoriales/rate-limit/test-rate-limit.sh
```

Variables opcionales:

```bash
API_URL=http://127.0.0.1:5000/api/drug TOTAL=120 DELAY=0.1 ./test-rate-limit.sh
```

## Que valida

- Envia mas de 100 peticiones sin `Authorization` para validar el limite por IP.
- Repite la prueba con `Authorization: Bearer token-demo-a`.
- Repite la prueba con `Authorization: Bearer token-demo-b` para mostrar contadores independientes por usuario.
- Usa una `X-Real-IP` distinta por caso para que el limite por IP no mezcle los escenarios cuando el modo es `IP+User`.
- Consulta `/health` y `/metrics` para confirmar que los endpoints operativos estan excluidos.

## Resultado esperado

Con `RateLimiting:Mode` en `IP+User` y limites de `100/min`:

- Las primeras 100 peticiones de cada caso deberian llegar al backend.
- Las peticiones excedentes deberian responder `429 Too Many Requests`.
- Los dos tokens de usuario deben tener contadores separados.
- `/health` y `/metrics` no deben quedar bloqueados por el middleware de usuario.

## Requisitos

- API Gateway corriendo en `http://127.0.0.1:5000`.
- `RateLimiting:Mode` configurado como `IP+User`, `IP` o `User`.
