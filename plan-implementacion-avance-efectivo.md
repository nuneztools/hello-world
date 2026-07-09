# Plan de Implementación — Avance de Efectivo (`ca-baas-credit`)

**Fecha:** 2026-07-08
**Autor:** Álvaro — Equipo CCA
**Estado:** 🟡 Propuesta de plan
**Documento base:** ADR-0XX — Orquestar el Avance de Efectivo reutilizando `transfers-between-accounts`

---

## TL;DR

- **Esfuerzo de desarrollo estimado:** 8 a 11 días hábiles de un desarrollador.
- **Ventana disponible hasta UAT:** ~17 días hábiles (del 9 al 31 de julio).
- **Cero modificaciones a código existente.** El análisis del código confirmó que `PostDHIAuthorizationOperation` es inyectable y se invoca vía `handle(...)`. No hay refactor.
- **Conclusión:** la fecha acordada con Negocio **es alcanzable**, siempre que los bloqueadores externos se resuelvan a más tardar el **17 de julio**. Ese es el verdadero riesgo del cronograma, no el desarrollo.
- **Consumo estimado de créditos de GitHub Copilot:** 300 a 450 de los disponibles.

## 1. Bloqueadores externos (ruta crítica real)

Estas tareas **no dependen del equipo de desarrollo** y son las que definen si se llega o no. Deben escalarse de inmediato.

| ID | Bloqueador | Responsable | Fecha límite | Bloquea a |
|----|-----------|-------------|--------------|-----------|
| B1 | Amarrar `AV01` a su cuenta contable (hoy en 0) y confirmar `format` (ETF), `operation_code` y aplicabilidad de `reason_code_debit` | Negocio / Core | **17-jul** | T5, T9, T10 |
| B2 | Otorgar scope `baas:ca:accounts:external:read` al client de `ca-baas-credit` y habilitar el camino de red hacia `ca-baas-accounts` | Seguridad (Passport) / Redes | **17-jul** | T3, T10 |
| B3 | Confirmar si SProBaaS deduplica `reference_number` | Core / SProBaaS | **17-jul** | T6 |

> ⚠️ **Si B2 no se resuelve a tiempo**, la Opción D del ADR no es viable y hay que reevaluar.
>
> Mientras B1 esté abierto, el desarrollo puede avanzar usando valores parametrizados por configuración (no hardcodeados).

## 2. Desglose de tareas

Estimaciones en **días hábiles de un desarrollador**.

### Fase 0 — Verificaciones previas (0.5 día)

| ID | Tarea | Estimación | Notas |
|----|-------|-----------|-------|
| T0 | **Dos verificaciones puntuales:** (a) que `getUserContext()` esté poblado en el hilo del orquestador (probable `ThreadLocal` del Chassis); (b) el significado de `x-country-code = "CAM"` y si el orquestador debe replicar ese corto-circuito. | 0.5 d | La verificación del datasource ya se completó: `ca-baas-credit` tiene base de datos propia (SQL Server + HikariCP + JPA). La tabla de saga vive ahí. |

### Fase 1 — Preparación (2 a 2.5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T1 | **Armado del `RestConsumerRequest<DHIRequest>`**: método interno que construye el objeto de entrada de `PostDHIAuthorizationOperation` desde el contexto del orquestador (`headerParams` + `DHIRequest`), replicando el mapeo que hoy hace `PostDhiAuthController`. Inyectar la operación por `@Qualifier`. | 0.5 d | T0(a) | **No es un refactor** ni un patrón nuevo: es un método privado de mapeo. No se modifica ni una línea de `card-charge`. Riesgo bajo. |
| T2 | **Registro de estado de la saga**: DDL (SQL Server), entidad JPA con `@Version`, repositorio. Estados: `INICIADA`, `CARGO_OK`, `COMPLETADA`, `COMPENSADA`, `EN_DUDA_CARGO`, `EN_DUDA_ACREDITACION`, `COMPENSACION_FALLIDA`. Restricción única `(country_code, reference_number)`. Esquema completo en el ADR. | 0.5 d | — | Se crea en la base de datos propia de `ca-baas-credit`, que ya tiene JPA y HikariCP configurados. **Transacciones cortas por transición**, nunca una que abarque la saga (ver ADR: pool de 20 y detección de fugas a 2 s). |
| T3 | **Cliente HTTP hacia `ca-baas-accounts`**: `RestTemplate` con **tiempo de espera explícito** (connect + read), token OAuth2 client credentials, propagación de headers (`x-b3-traceid`, `x-b3-spanid`, `x-channel-id`, `x-originating-appl-code`, `x-country-code`). | 1 – 1.5 d | B2 (solo para probar contra el ambiente real) | Se construye y prueba contra mock antes de que B2 se resuelva. |

### Fase 2 — Orquestador (3.5 a 4.5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T4 | **Endpoint `POST /v1/credit/cash-advance`**: controller, delegate con `@PreAuthorize`, validación de request, contrato OpenAPI. Generación del `reference_number` de la saga (≤ 9 dígitos). | 1 d | T1 | Seguir la convención de los endpoints hermanos. |
| T5 | **Saga, camino feliz**: registrar estado → validar/resolver cuenta destino → `handle(CASH_ADVANCE)` → acreditación en Accounts → `COMPLETADA`. | 1 d | T1, T2, T3, B1 | Validar la cuenta destino **antes** del cargo, para fallar barato. |
| T6 | **Mapeo de resultados, compensación y transacción en duda.** Implementar la tabla de interpretación del ADR: cargo exitoso; errores de validación previa (`E422CABAASCREDIT0008`, `E400BAASCREDIT0000/0001`) y error de TSYS → **no cargó**, abortar seguro; `code = -1` por fallo de persistencia → **sí cargó, no compensable** → `EN_DUDA_CARGO`; `E500CABAAS0000` genérico → `EN_DUDA_CARGO`; timeout de Accounts → `EN_DUDA_ACREDITACION`. Compensar con `handle(CASH_ADVANCE_REVERSE)` **solo desde `CARGO_OK`**, con bloqueo optimista. | 1.5 – 2 d | T5, B3 | **Tarea más delicada del plan.** Incluye el método puntual que interpreta `notifications` de Accounts. |
| T7 | **Trazabilidad y logging**: propagación de `x-b3-traceid` / `x-b3-spanid` y correlación extremo a extremo con el `reference_number` de la saga, sin confundirlo con el `reference_number` de respuesta de `card-charge` (que es el Auth ID de TSYS, campo I038). Registro de cada transición de estado de la saga. | 0.5 d | T5 | Reusar el servicio de logging existente. **No incluye métricas ni alertas nuevas** (ver Fuera de alcance). |

### Fase 3 — Pruebas (2.5 a 3.5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T8 | **Pruebas unitarias**: máquina de estados, mapeo de resultados de `card-charge` (los cuatro casos), idempotencia de entrada, no-doble-compensación. | 1 d | T6 | |
| T9 | **Pruebas de integración**: Accounts simulado (WireMock). Escenarios: éxito, error de negocio con `HTTP 200`, tiempo de espera vencido, solicitud duplicada, cargo con `code = -1`. | 1 – 1.5 d | T6, B1 | El escenario de tiempo de espera vencido valida que **no** se compense a ciegas. |
| T10 | **Pruebas en ambiente integrado**: contra `ca-baas-accounts` real, con scope y red habilitados. | 0.5 – 1 d | B1, B2, T9 | Aquí aparecen las sorpresas del core. Reservar holgura. |

### Fase 4 — Entrega

| ID | Tarea | Estimación | Notas |
|----|-------|-----------|-------|
| T11 | **Runbook de conciliación**, con **dos procedimientos distintos**: `EN_DUDA_CARGO` (verificar contra TSYS / GlobalTC si el cargo entró) y `EN_DUDA_ACREDITACION` (verificar contra SProBaaS / core si la acreditación entró). Más el procedimiento para `COMPENSACION_FALLIDA`. | 0.5 – 1 d | Requisito operativo, no opcional. Es lo que hace utilizable el registro de estado. |
| T12 | **Soporte a UAT** y corrección de hallazgos. | 2 – 3 d | Primera semana de agosto. |
| T13 | **Despliegue a Producción** y monitoreo inicial. | 1 d | Fin de agosto. |

### Totales

| Fase | Estimación |
|------|-----------|
| Fase 0 — Verificaciones | 0.5 d |
| Fase 1 — Preparación | 2 – 2.5 d |
| Fase 2 — Orquestador | 3.5 – 4.5 d |
| Fase 3 — Pruebas | 2.5 – 3.5 d |
| **Subtotal desarrollo (antes de UAT)** | **8.5 – 11 días hábiles** |
| Fase 4 — Entrega | 3.5 – 4.5 d (agosto) |

## 3. Cronograma propuesto

| Semana | Fechas | Actividad |
|--------|--------|-----------|
| Semana 1 | 9 – 17 jul | Escalamiento de B1, B2, B3. En paralelo: T0, T1, T2, T3 (contra mocks). |
| Semana 2 | 20 – 24 jul | T4, T5, T6. |
| Semana 3 | 27 – 31 jul | T7, T8, T9, T10, T11. Corte para UAT. |
| Semana 4 | 3 – 7 ago | **UAT** (T12). |
| Semanas 5-6 | 10 – 28 ago | Corrección de hallazgos, certificación, despliegue a Producción (T13). |

**Holgura disponible:** ~6 días hábiles entre la estimación alta (11 d) y la ventana (17 d). Reservada para T6 (la tarea más delicada) y T10 (pruebas contra el core).

## 4. Fuera de alcance en esta entrega

Documentado en el ADR, se difiere a fase posterior:

- Circuit breaker con Resilience4j (sí se incluye el tiempo de espera explícito).
- Capa anti-corrupción formal (solo el método puntual que interpreta `notifications`).
- Consulta automática de estado para resolver transacciones en duda (se resuelve por conciliación manual, con runbook).
- **Métricas y alertas nuevas** (por ejemplo, un dashboard de estados de la saga o una alerta por transacciones en `EN_DUDA`). T7 cubre trazabilidad y logging; la observabilidad completa se evalúa después de UAT, cuando se conozca el volumen real.
- **Corrección de los hallazgos H1 (condición de carrera confirmada), H2 (cargo no persistido) y H6 (posible `NullPointerException`).** Son preexistentes y no los introduce esta feature; se recomienda levantarlos como tickets independientes.

## 5. Estrategia de desarrollo asistido (Spec Kit + GitHub Copilot)

### Reparto de herramientas

| Fase | Herramienta | ¿Consume créditos de Copilot? |
|------|-------------|-------------------------------|
| Análisis y refinamiento del requerimiento | Claude.ai con skills propias | ❌ No |
| `/speckit.specify` → `/speckit.implement` | Copilot en IntelliJ | ✅ Sí |

El análisis técnico de ambos servicios y este ADR ya están hechos fuera de Copilot, así que `specify` entra con el trabajo pesado resuelto.

### Enrutamiento de modelos

Costos en créditos por millón de tokens:

| Modelo | Entrada | Salida | Cacheado |
|--------|--------:|-------:|---------:|
| Opus 4.6 | 500 | 2,500 | 50 |
| Sonnet 4.6 | 300 | 1,500 | 30 |
| GPT-5.3-Codex | 175 | 1,400 | 17 |

| Fase | Modelo sugerido | Por qué |
|------|-----------------|---------|
| `/speckit.plan` | **Opus** | Poco volumen de salida, alto valor de razonamiento. Es donde se decide la máquina de estados. |
| `/speckit.tasks` | **Sonnet** o **Codex** | Trabajo mecánico. |
| `/speckit.implement` | **Codex** | Fase de mayor volumen de salida (lo más caro). Codex es el más económico. |
| Depuración de T6 | **Opus**, solo si Codex se atasca | Escalamiento puntual, no por defecto. |

### Consumo estimado

| Fase | Créditos estimados |
|------|-------------------:|
| `/speckit.specify` (contexto ya resuelto en Claude.ai) | 20 – 40 |
| `/speckit.plan` (Opus) | 50 – 80 |
| `/speckit.tasks` | 30 – 50 |
| `/speckit.implement` (Codex) | 150 – 250 |
| Iteración y depuración | 50 – 100 |
| **Total estimado** | **300 – 450** |

Las palancas de ahorro que más pesan no son cambiar de modelo (eso ahorra ~2×), sino:

- **Una sola conversación por feature** para aprovechar el cacheo (cuesta el 10% de la entrada fresca).
- **Disciplina de salida**: pedir diffs y archivos puntuales, no reescrituras completas.
- **Cargar el contexto estable al inicio** (el ADR, los análisis de ambos endpoints) y no re-explicarlo en cada turno.

### Nota de riesgo

**T6 no se delega a modo agéntico sin revisión línea por línea.** Es la lógica que decide si se revierte o no un cargo de dinero. Copilot propone; la persona decide.

## 6. Supuestos de la estimación

- Un solo desarrollador dedicado principalmente a esta feature.
- **No se modifica código existente de `card-charge`** (confirmado por análisis de código).
- **`ca-baas-credit` tiene datasource propio** (SQL Server + HikariCP + JPA), verificado en `application.yml`. La tabla de saga se crea ahí.
- QA dispone de ambiente integrado con `ca-baas-accounts` desde el 27 de julio.
- No se requiere cambio de código en `ca-baas-accounts`.
- Los códigos de operación (B1) llegan parametrizables por configuración.
- El `UserContext` está disponible en el hilo del orquestador (a verificar en T0).

## 7. Qué necesitamos decidir antes de arrancar

1. Nombre definitivo del endpoint orquestador.
2. Qué significa `x-country-code = "CAM"` y si el orquestador debe replicar ese corto-circuito.
3. Si validamos la existencia de la cuenta destino con una consulta previa a Accounts, o aceptamos el rechazo del core y compensamos.
4. Quién escala B1, B2 y B3, y con qué fecha compromiso.
5. Si el registro de estado de la saga entra en esta entrega (recomendación: **sí**; sin él no hay forma de conciliar el caso en que TSYS cargó y `TRANSACTIONS_DHI` no guardó, ni de evitar una doble reversa).
6. Si se levantan H1 (condición de carrera confirmada), H2 (cargo no persistido) y H6 (posible NPE) como tickets independientes.

## Referencias

- 📄 ADR-0XX — Orquestar el Avance de Efectivo: [enlace manual]
- 📁 Análisis técnico de `card-charge` y `transfers-between-accounts`: [rutas en Git]
- 🎫 Tickets de Jira: [agregar manualmente]
