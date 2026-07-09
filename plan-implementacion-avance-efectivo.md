# Plan de Implementación — Avance de Efectivo (Opción E)

**Fecha:** 2026-07-09
**Autor:** Álvaro — Equipo CCA
**Estado:** 🟡 Propuesta de plan
**Documento base:** ADR-0XX — Opción E: orquestación dentro de `card-charge` mediante parámetro opcional de cuenta destino

---

## TL;DR

- **Esfuerzo de desarrollo estimado:** 12 a 16 días hábiles de un desarrollador.
- **Ventana disponible hasta UAT (3 de agosto):** ~17 días hábiles.
- **La holgura es mínima o nula.** Con la estimación alta, el plan consume toda la ventana. El riesgo del cronograma está ahora en el **desarrollo**, no solo en los bloqueadores.
- Respecto a la opción de consumir `ca-baas-accounts`, esta alternativa **suma entre 4 y 6 días de desarrollo** (conector a SProBaaS, resolución de cuenta y moneda, mapeo de errores, pruebas), a cambio de **certificar un solo microservicio**. Ese intercambio fue evaluado y aceptado.
- **Consumo estimado de créditos de GitHub Copilot:** 400 a 610.

### Fechas

El Avance de Efectivo forma parte de un **conjunto de Gaps** de la fusión bancaria. Todos los Gaps críticos y de prioridad alta deben estar en producción antes de la **auditoría de febrero de 2027**. Negocio priorizó este Gap con fecha propia:

| Hito | Fecha |
|------|-------|
| Corte de desarrollo | 31 de julio de 2026 |
| UAT | 3 – 7 de agosto de 2026 |
| **Producción** | **Fin de agosto de 2026** |
| Auditoría del conjunto de Gaps | Febrero de 2027 |

La planificación se hace **contra agosto de 2026**. Febrero de 2027 no es holgura disponible: es el límite de la auditoría para el conjunto completo de Gaps.

## 1. Bloqueadores externos (ruta crítica)

No dependen del equipo de desarrollo. Deben escalarse de inmediato.

| ID | Bloqueador | Responsable | Fecha límite | Bloquea a |
|----|-----------|-------------|--------------|-----------|
| B1 | Amarrar `AV01` a su cuenta contable (hoy en 0) y confirmar `format` (ETF), `operation_code` y aplicabilidad de `reason_code_debit` | Negocio / Core | **17-jul** | T5, T11, T13 |
| B2 | Habilitar el **camino de red `ca-baas-credit → SProBaaS`** y las credenciales OAuth2 correspondientes | Redes / Seguridad | **17-jul** | T4, T13 |
| B3 | Confirmar si SProBaaS **deduplica `reference_number`** | Core / SProBaaS | **17-jul** | T8 |
| B4 | **Acceso de `ca-baas-credit` a SProBaaS**: confirmar que acepta `x-originating-appl-code = CaBaaSCredit` (o el código EPM que corresponda), y verificar si existe lista blanca de aplicaciones origen. | Core / SProBaaS | **17-jul** | T4, T13 |

> ℹ️ **B2 y B4 están contemplados por el equipo**, que los estima de gestión sencilla. Se mantienen rastreados con fecha porque **T13 requiere probar contra SProBaaS real desde el 27 de julio**. Conviene tener la confirmación por escrito y las credenciales en mano antes de iniciar la semana 2 (20 de julio). Si llegan antes, se cierran y listo.

## 2. Desglose de tareas

Estimaciones en **días hábiles de un desarrollador**.

### Fase 0 — Verificaciones previas (0.5 día)

| ID | Tarea | Estimación | Notas |
|----|-------|-----------|-------|
| T0 | **Verificaciones puntuales:** (a) que el componente de KeyMaster de Credits resuelva cuentas de depósito, no solo tarjetas (`NaturalKeyPrefixType`); (b) el significado de `x-country-code = "CAM"` (H5) y si aplica al modo orquestador; (c) si el `x-originating-appl-code` que Credits envía hoy a otros sistemas sirve para SProBaaS. | 0.5 d | (a) es la más importante: si KeyMaster en Credits no maneja el prefijo de cuentas, T3 crece. |

### Fase 1 — Contrato y cimientos (3.5 a 5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T1 | **Contrato del API**: agregar `destination_account` (opcional) al `DHIRequest` y al OpenAPI (`api_v1.yml`). Validación: presente solo con `dhi_type = CASH_ADVANCE`, si no → `HTTP 400`. | 0.5 d | — | Campo nuevo y opcional: compatible hacia atrás. |
| T2 | **Registro de estado de la saga**: DDL (SQL Server), entidad JPA con `@Version`, repositorio. Siete estados. Restricción única `(country_code, reference_number)`. Esquema en el ADR. | 0.5 d | — | Base de datos propia de Credits, que ya tiene JPA y HikariCP. **Transacciones cortas por transición.** |
| T3 | **Resolución de cuenta destino**: reutilizar el componente de KeyMaster de Credits para traducir surrogate key (UUID) → llave natural, y rellenar a 12 dígitos con ceros a la izquierda. Manejar el caso de fallo de KeyMaster de forma explícita (no dejar que el UUID viaje como número de cuenta). | 1 d | T0(a) | Replica el comportamiento de `TransferBetweenAccountsGateway.naturalAccount()`. |
| T4 | **Conector a SProBaaS**: `POST ${sPro.host}/api/v1/deposit/transfer-between-accounts`. OAuth2 client credentials, headers (`x-channel-id`, `x-originating-appl-code`, `x-country-code`), cuerpo como arreglo con un `TransferBetweenAccountsAttributes`. **Tiempo de espera explícito** (connect + read). Mapeo de respuesta: `notifications` vacío → éxito. | 2 – 3 d | B2, B4 | Se construye contra un simulador antes de que B2/B4 se resuelvan. Es la pieza más voluminosa que introduce esta opción. |
| T5 | **Resolución de moneda**: si el request no trae moneda de la cuenta destino, consultar `SProBaaS info-current-account`. Formatear el monto a 2 decimales. Validar el formato del monto **antes** de convertirlo (evitar el `NumberFormatException` que Accounts no valida). | 1 d | T4, B1 | |

### Fase 2 — Orquestación (3.5 a 4.5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T6 | **Bifurcación única de modo** en `PostDHIAuthorizationOperation`: si `destination_account` presente y `dhi_type = CASH_ADVANCE` → método nuevo de saga; si no → flujo actual intacto. La lógica de acreditación se inyecta como colaborador (`SProBaasTransferGateway`), no se escribe dentro de la Operation. | 1 d | T1, T4 | **Un solo `if`.** No dispersar condicionales por `makeCharge`, `revertCharge` ni `convertObjectToStringXml`. |
| T7 | **Saga, camino feliz**: resolver cuenta y moneda → guardar `INICIADA` → `makeCharge` → guardar `CARGO_OK` → acreditar en SProBaaS → `COMPLETADA`. | 1 d | T2, T3, T5, T6 | Resolver y validar la cuenta destino **antes** del cargo, para fallar barato. |
| T8 | **Mapeo de resultados, compensación y transacción en duda.** Interpretar el resultado de `makeCharge` según la tabla del ADR (cuatro casos, incluido el `code = -1` que significa "sí cargó, no compensable"). **Clasificar el fallo de la acreditación por tipo de excepción y momento de la llamada, no por código de error**: rechazo de conexión → compensar; vencimiento de lectura o `HTTP 5xx` → `EN_DUDA_ACREDITACION`; `notifications` del core → compensar. Compensar con `revertCharge` **solo desde `CARGO_OK`**, con bloqueo optimista. | 2 – 2.5 d | T7, B3 | **Tarea más delicada del plan.** Es la lógica que decide si se revierte dinero. Ver el hallazgo crítico del ADR sobre `E500CABAAS0002`. |
| T9 | **Trazabilidad y logging**: propagación de `x-b3-traceid` / `x-b3-spanid`, correlación extremo a extremo con el `reference_number` de la saga (sin confundirlo con el Auth ID de TSYS del response). Registro de cada transición de estado. | 0.5 d | T7 | No incluye métricas ni alertas nuevas. |

### Fase 3 — Pruebas (4 a 5.5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T10 | **Pruebas unitarias**: máquina de estados, los cuatro casos del mapeo de `makeCharge`, idempotencia de entrada, no-doble-compensación, validaciones de contrato. | 1 – 1.5 d | T8 | |
| T11 | **Pruebas de integración** con SProBaaS simulado (WireMock). Escenarios mínimos: (1) éxito; (2) `notifications` con `E_IWS_XXXX` y `HTTP 200` → compensa; (3) **rechazo de conexión** → compensa; (4) **vencimiento de lectura** → `EN_DUDA_ACREDITACION`, **no compensa**; (5) `HTTP 5xx` → `EN_DUDA_ACREDITACION`; (6) solicitud duplicada → idempotencia; (7) cargo con `code = -1` → `EN_DUDA_CARGO`; (8) fallo de KeyMaster. | 2 – 2.5 d | T8, B1 | Los escenarios 3 y 4 son la prueba clave: **el mismo `E500CABAAS0002` en Accounts, dos comportamientos distintos en Credits.** Ya hay WireMock en el entorno del equipo. |
| T12 | **Pruebas de no regresión** de `card-charge` sin `destination_account`: los seis `dhi_type` existentes deben comportarse exactamente igual. | 0.5 d | T6 | Bajo riesgo: hoy ningún consumer usa el endpoint (C11). Aun así, es la garantía del compromiso "compatible hacia atrás". |
| T13 | **Pruebas en ambiente integrado**: contra SProBaaS real, con red y credenciales habilitadas. | 1 – 1.5 d | B1, B2, B4, T11 | Aquí aparecen las sorpresas del core. Reservar holgura. |

### Fase 4 — Entrega

| ID | Tarea | Estimación | Notas |
|----|-------|-----------|-------|
| T14 | **Runbook de conciliación**, con procedimientos distintos para `EN_DUDA_CARGO` (verificar contra TSYS / GlobalTC), `EN_DUDA_ACREDITACION` (verificar contra SProBaaS) y `COMPENSACION_FALLIDA`. | 0.5 – 1 d | Requisito operativo, no opcional. |
| T15 | **Soporte a UAT** y corrección de hallazgos. | 2 – 3 d | Primera semana de agosto. |
| T16 | **Despliegue a Producción** y monitoreo inicial. | 1 d | Fin de agosto. |

### Totales

| Fase | Estimación |
|------|-----------|
| Fase 0 — Verificaciones | 0.5 d |
| Fase 1 — Contrato y cimientos | 3.5 – 5 d |
| Fase 2 — Orquestación | 3.5 – 4.5 d |
| Fase 3 — Pruebas | 4.5 – 6 d |
| **Subtotal desarrollo (antes de UAT)** | **12 – 16 días hábiles** |
| Fase 4 — Entrega | 3.5 – 5 d (agosto) |

## 3. Cronograma propuesto

| Semana | Fechas | Actividad |
|--------|--------|-----------|
| Semana 1 | 9 – 17 jul | Escalamiento de B1–B4. En paralelo: T0, T1, T2, T3, e inicio de T4 contra simulador. |
| Semana 2 | 20 – 24 jul | T4 (cierre), T5, T6, T7. |
| Semana 3 | 27 – 31 jul | T8, T9, T10, T11, T12, T13. Runbook (T14). Corte para UAT. |
| Semana 4 | 3 – 7 ago | **UAT** (T15). |
| Semanas 5-6 | 10 – 28 ago | Corrección de hallazgos, certificación, despliegue a Producción (T16). |

**Holgura:** entre 1 y 5 días hábiles según se materialice la estimación baja o alta. Con la estimación alta **no hay holgura**. Los dos puntos donde el plan puede romperse son **T4** (conector a SProBaaS, si el contrato o la autenticación traen sorpresas) y **T13** (pruebas contra el core).

**Recomendación de mitigación:** si a mitad de la semana 2 (miércoles 22 de julio) el conector T4 no está funcionando contra el simulador, o si B2/B4 siguen sin confirmarse, escalar el riesgo de fecha de inmediato — no en la semana 3.

## 4. Comparación de costo con la Opción D (rechazada)

Se documenta para trazabilidad de la decisión, no para reabrirla.

| Concepto | Opción D (consumir `ca-baas-accounts`) | Opción E (adoptada) |
|----------|----------------------------------------|---------------------|
| Desarrollo | 8.5 – 11 días | **12 – 16 días** |
| Microservicios a certificar | 2 | **1** |
| Equipos involucrados | 2 | **1** |
| Dependencia de red nueva | `ca-baas-credit → ca-baas-accounts` | `ca-baas-credit → SProBaaS` |
| Lógica de acreditación duplicada | No | **Sí** |
| Bloqueadores externos | 3 | **4** (se agrega B4) |

El intercambio es explícito: **+4 a 6 días de desarrollo a cambio de eliminar la coordinación y certificación cruzada entre organizaciones.** Bajo una fusión bancaria con fecha crítica, el equipo evaluó que el riesgo de coordinación pesa más que el de desarrollo.

## 5. Fuera de alcance en esta entrega

- **Circuit breaker (Resilience4j)** sobre la llamada a SProBaaS. Sí se incluye el tiempo de espera explícito. Se documenta como riesgo asumido.
- **Métricas y alertas nuevas** (dashboard de estados de la saga, alerta por transacciones en `EN_DUDA_*`). T9 cubre trazabilidad y logging; la observabilidad completa se evalúa después de UAT.
- **Consulta automática de estado** para resolver transacciones en duda. Se resuelve por conciliación manual, con runbook.
- **Reversa de un adelanto ya completado** (débito de la cuenta de depósito). Ver Preguntas abiertas del ADR. Si el negocio lo requiere, es alcance adicional.
- **Corrección de H1 (condición de carrera confirmada), H2 (cargo no persistido) y H6 (posible `NullPointerException`).** Preexistentes; se recomienda levantarlos como tickets independientes.

## 6. Estrategia de desarrollo asistido (Spec Kit + GitHub Copilot)

### Reparto de herramientas

| Fase | Herramienta | ¿Consume créditos de Copilot? |
|------|-------------|-------------------------------|
| Análisis y refinamiento del requerimiento | Claude.ai con skills propias | ❌ No |
| `/speckit.specify` → `/speckit.implement` | Copilot en IntelliJ | ✅ Sí |

El análisis técnico de ambos servicios y este ADR ya están hechos fuera de Copilot, así que `specify` entra con el contexto resuelto.

### Enrutamiento de modelos

Créditos por millón de tokens:

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
| Depuración de T8 | **Opus**, solo si Codex se atasca | Escalamiento puntual, no por defecto. |

### Consumo estimado

| Fase | Créditos |
|------|---------:|
| `/speckit.specify` | 20 – 40 |
| `/speckit.plan` (Opus) | 60 – 100 |
| `/speckit.tasks` | 30 – 50 |
| `/speckit.implement` (Codex) | 220 – 350 |
| Iteración y depuración | 70 – 120 |
| **Total estimado** | **400 – 610** |

Sube respecto a la Opción D porque hay más superficie que implementar (conector a SProBaaS, resolución de cuenta y moneda, mapeo de errores).

Palancas de ahorro, en orden de impacto:
- **Una sola conversación por feature** para aprovechar el cacheo (cuesta el 10% de la entrada fresca).
- **Disciplina de salida**: pedir diffs y archivos puntuales, no reescrituras completas.
- **Cargar el contexto estable al inicio** (ADR + análisis de ambos endpoints) y no re-explicarlo en cada turno.

### Nota de riesgo

**T6 y T8 no se delegan a modo agéntico sin revisión línea por línea.** T6 modifica una clase en producción; T8 decide si se revierte un cargo de dinero. Copilot propone; la persona decide.

## 7. Supuestos de la estimación

- Un solo desarrollador dedicado principalmente a esta feature.
- **`ca-baas-credit` tiene datasource propio** (SQL Server + HikariCP + JPA), verificado en `application.yml`.
- **El componente de KeyMaster de Credits puede resolver cuentas de depósito**, no solo tarjetas (a verificar en T0).
- **Ningún consumer usa hoy `card-charge`** (confirmado por el equipo), lo que reduce el riesgo de regresión.
- Los códigos de operación (B1) llegan parametrizables por configuración.
- No se requiere cambio de código en `ca-baas-accounts` ni en SProBaaS.
- QA dispone de ambiente integrado con SProBaaS desde el 27 de julio.

## 8. Qué necesitamos decidir antes de arrancar

1. Nombre y tipo del campo nuevo (`destination_account`): ¿acepta UUID, llave natural, o ambos?
2. Qué significa `x-country-code = "CAM"` (H5) y si aplica al modo orquestador.
3. ¿Se valida la existencia de la cuenta destino con una consulta previa a SProBaaS, o se acepta el rechazo del core y se compensa?
4. **¿Está en alcance la reversa de un adelanto ya completado?** Hoy `CASH_ADVANCE_REVERSE` solo revierte el cargo a la tarjeta; no debita la cuenta de depósito.
5. Quién escala B1, B2, B3 y B4, y con qué fecha compromiso.
6. Si se levantan H1, H2 y H6 como tickets independientes.

## Referencias

- 📄 ADR-0XX — Avance de Efectivo (Opción E): [enlace manual]
- 📁 Análisis técnico de `card-charge` y `transfers-between-accounts`: [rutas en Git]
- 🎫 Tickets de Jira: [agregar manualmente]
