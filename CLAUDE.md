# Obligatorio - AIOps

## Objetivo

El objetivo del obligatorio es experimentar con herramientas técnicas para mejorar la respuesta a incidentes, partiendo de un proyecto ya existente con un stack tecnológico usado en varias materias de la carrera.

Las actividades del obligatorio se iniciarán en clase, y los equipos de trabajo deben customizarlas para el contexto de sus obligatorios.

Los equipos de trabajo deberán:

- Implementar requerimientos no funcionales para mejorar diferentes sub-atributos de calidad de:
  - disponibilidad
  - desplegabilidad
  - mantenibilidad
- Implementar un plan de contención de incidentes operacionales.
- Implementar scripts que permitan simular incidentes operacionales.
- Implementar técnicas de aprendizaje automático para detectar anomalías en datasets de datos operacionales.

Finalmente, el equipo deberá realizar una defensa de proyecto que consistirá en un war-room, que resultará de la ejecución de un script de ingeniería de caos provisto por los docentes.

En dicha instancia, los estudiantes deberán llevar adelante el plan de mitigación de incidentes operacionales diseñado durante el curso y presentar hallazgos.

---

# Actividades

- Reducir el MTTR de un conjunto de fallos en tiempo de ejecución al mínimo posible, idealmente al orden de pocos segundos.
- Implementar técnicas de despliegue/reemplazo de componentes seguro.
- Diseñar, capturar y visualizar métricas de aplicación e infraestructura.
- Implementar logs estructurados y trazas con propagación de contexto de acuerdo a OpenTelemetry.
- Implementar un plan de mitigación de incidentes operacionales.
- Entrenar dos técnicas no supervisadas de detección de anomalías.
- Diseñar e implementar experimentos de ingeniería del caos.
- Reflexionar sobre el impacto de las prácticas de ingeniería de software ágil.

---

# Entregas y esfuerzo

El proyecto consiste en una única entrega, que se realizará a través de Gestión.

Además, todos los productos de trabajo deben estar versionados en GitHub.

Se espera una dedicación de **2.5 horas persona/semana**.

---

# Rúbrica de evaluación

| Objetivo | Puntaje | Resultados esperados |
|---|---|---|
| Implementación de plataforma | 5 | El sistema debe correr sobre Kubernetes. Cada microservicio debe ejecutar en un deployment independiente. Se debe implementar un diagrama de despliegue de los componentes principales de la plataforma. |
| Alta disponibilidad | 5 | Los microservicios deben curarse automáticamente en casos de errores en tiempo de ejecución. Es decir, una vez que las réplicas de la aplicación llegan a un estado READY, ellas deben poder volver al mismo estado luego de excepciones. El sistema debe ser resiliente a ataques que inciten fallas reiteradas. Se debe implementar algún patrón que mitigue la eventualidad de tener un alto volumen de solicitudes fallidas. |
| Despliegues seguros | 5 | El sistema debe poder reemplazar sus componentes garantizando 100% de disponibilidad. Se necesita documentar y explicar la técnica elegida. |
| Telemetría | 5 | La aplicación debe contar con logs estructurados en JSON, trazas de acuerdo a OTLP y métricas a nivel de pod/contenedor y nodo físico (se sugiere tener CPU, memoria, storage y red). Se deben registrar, al menos, 5 métricas de cada tipo. Las métricas deben recolectarse con OTLP hacia Prometheus, visualización con Grafana. Los logs deben poder consultarse en alguna herramienta de manejo de logs como Kibana con ElasticSearch. Se deben configurar, por lo menos, 5 alertas en Grafana para detección de anomalías de las métricas ya definidas. |
| Técnicas de detección de anomalías | 5 | Deben implementarse los algoritmos IsolationForest y Support Vector Machine para datasets que serán provistos por los docentes. Se deben entregar las notebooks de cada experimento y reportar los resultados. |
| Plan de contención de incidentes operacionales | 5 | Se debe realizar un plan de mitigación de incidentes operacionales que implemente todas las fases del framework de Atlassian. |
| Scripts de caos | 5 | Se deben implementar scripts de caos que prueben: inyección de requests, sobrecarga de CPU, sobrecarga de memoria, sobrecarga de storage, interrupción de tráfico de red y desconexión de componentes internos de la aplicación. |
| Defensa | 5 | Se debe ejecutar el script de caos implementado, mostrar sus efectos mediante telemetría y la respuesta del sistema. Se deben explicar cómo los mecanismos implementados en el obligatorio garantizan el comportamiento observado. Los docentes podrán agregar scripts de caos custom durante la defensa. |

---

# Guía para la realización del informe académico final

El informe final debe tener una sección para cada elemento de la rúbrica, explicando los desafíos enfrentados y los resultados obtenidos.

La extensión no puede ser mayor a 10 páginas.