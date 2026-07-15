# Plan de Implementación — Avance de Efectivo (Opción F)

**Fecha:** 2026-07-11
**Autor:** Álvaro — Equipo CCA
**Estado:** 🟡 Propuesta de plan
**Documento base:** ADR-0XX — Opción F: orquestación en `card-charge` consumiendo un endpoint nuevo de `ca-baas-accounts`, con validación previa de productos

---

## TL;DR

- **Esfuerzo de desarrollo de `ca-baas-credit`:** 10 a 13 días hábiles de un desarrollador.
- **Ventana disponible hasta UAT (3 de agosto):** ~17 días hábiles.
- **El riesgo del cronograma ya no es el código de Credit, es la coordinación:** la solución depende de que el equipo de `ca-baas-accounts` entregue el endpoint nuevo, y de que la parametrización esté cargada en `ca-baas-configuration`. Ambos están fuera del control del equipo de Credit.
- Respecto a las opciones anteriores: la Opción F **quita de Credit** el conector a SProBaaS y la replicación de lógica (Opción E), y **agrega** la validación de productos y el consumo de dos endpoints ajenos.
- **Consumo estimado de créditos de GitHub Copilot:** 350 a 500.

### Fechas

| Hito | Fecha |
|------|-------|
| Corte de desarrollo | 31 de julio de 2026 |
| UAT | 3 – 7 de agosto de 2026 |
| **Producción** | **Fin de agosto de 2026** |
| Auditoría del conjunto de Gaps | Febrero de 2027 |

La planificación se hace contra agosto de 2026. Febrero de 2027 no es holgura: es el límite de la auditoría para el conjunto completo de Gaps.

## 1. Bloqueadores y dependencias externas (ruta crítica)

No dependen del equipo de `ca-baas-credit`. **En la Opción F, estos pesan más que el desarrollo.**

| ID | Bloqueador | Responsable | Fecha límite | Bloquea a |
|----|-----------|-------------|--------------|-----------|
| B1 | **Cargar la parametrización** (código de operación, formato ETF, códigos de razón) para el código de transacción y moneda del adelanto, en la tabla de **`ca-baas-configuration`**. Sin esto, el endpoint de Accounts no funciona. | Negocio / equipo de `ca-baas-configuration` | **17-jul** | T11, T13 |
| B2 | **Endpoint nuevo de `ca-baas-accounts`**: contrato acordado y fecha de entrega. Confirmar modelo de respuesta y de error. | Equipo de `ca-baas-accounts` | Contrato **11-jul**; entrega para pruebas integradas **24-jul** | T5, T13 |
| B3 | Confirmar si el core **deduplica `reference_number`** | Core / SProBaaS | **17-jul** | T8 |
| B4 | Habilitar caminos de red y credenciales: `ca-baas-credit → ca-baas-accounts` (endpoint nuevo) y `ca-baas-credit → ca-baas-products` | Redes / Seguridad | **17-jul** | T5, T4, T13 |
| B5 | **Contrato de `ca-baas-products`**: entrada (identificador de cliente) y salida (productos con estado); con qué identificadores se localizan tarjeta y cuenta | Equipo de `ca-baas-products` | **14-jul** | T4 |

> ⚠️ **B1 y B2 son los verdaderos determinantes de la fecha.** El desarrollo de Credit puede completarse contra simuladores, pero **UAT no puede empezar sin el endpoint de Accounts entregado (B2) y sin la parametrización cargada (B1)**. Si cualquiera de los dos se atrasa, la fecha de agosto está en riesgo independientemente del avance de Credit.

## 2. Desglose de tareas (solo `ca-baas-credit`)

Estimaciones en **días hábiles de un desarrollador**.

### Fase 0 — Verificaciones y contratos (0.5 día)

| ID | Tarea | Estimación | Notas |
|----|-------|-----------|-------|
| T0 | **Verificaciones:** (a) qué significa `x-country-code = "CAM"` (H5) y si aplica; (b) revisar los contratos de `ca-baas-products` (B5) y del endpoint nuevo de Accounts (B2) apenas estén disponibles. | 0.5 d | Depende de B2 y B5 para cerrarse; puede iniciarse con lo disponible. |

### Fase 1 — Cimientos (2 a 3 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T1 | **Contrato del API**: agregar cuenta destino (opcional) al `DHIRequest` y al OpenAPI. Validación: presente solo con `dhi_type = CASH_ADVANCE`. | 0.5 d | — | Compatible hacia atrás. |
| T2 | **Registro de estado de la saga**: DDL (SQL Server), entidad JPA con `@Version`, repositorio. Siete estados. Restricción única `(country_code, reference_number)`. | 0.5 d | — | BD propia de Credit. Transacciones cortas. |
| T4 | **Cliente de `ca-baas-products`** y lógica de validación: consultar productos del cliente, localizar tarjeta (por `card_key`) y cuenta, verificar estado activo y pertenencia. Tiempo de espera explícito. | 1 – 1.5 d | B5, B4 | Se construye contra simulador antes de B4. |

### Fase 2 — Orquestación (3.5 a 4.5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T5 | **Cliente del endpoint nuevo de `ca-baas-accounts`**: request con parámetros mínimos (cuentas, monto, moneda, código de transacción), OAuth2, headers, tiempo de espera explícito, mapeo de respuesta. | 1.5 – 2 d | B2, B4 | Se construye contra simulador (WireMock) mientras B2 se entrega. Más simple que en la Opción E: ya no se arma el payload completo de SProBaaS. |
| T6 | **Bifurcación única de modo** en la Operation: cuenta destino presente + `CASH_ADVANCE` → saga; si no → flujo actual intacto. Colaboradores inyectados (`ProductsValidator`, `AccountsTransferGateway`), no lógica dentro de la Operation. | 1 d | T1, T4, T5 | **Un solo `if`.** |
| T7 | **Saga, camino feliz**: validar productos → `INICIADA` → `makeCharge` → `CARGO_OK` → acreditar en Accounts → `COMPLETADA`. | 1 d | T2, T4, T5, T6 | Validación de productos **antes** del cargo. |

### Fase 3 — Manejo de errores y pruebas (4 a 5 días)

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T8 | **Mapeo de resultados y compensación.** Interpretar `makeCharge` (tabla del ADR). **Clasificar el fallo de la acreditación por tipo de excepción y momento, no por código:** rechazo de conexión → compensar; vencimiento de lectura o `HTTP 5xx` → `EN_DUDA_ACREDITACION`; `notifications` del core → compensar. Compensar `revertCharge` **solo desde `CARGO_OK`**, con bloqueo optimista. | 2 – 2.5 d | T7, B3 | **Tarea más delicada.** Ver el hallazgo crítico del ADR sobre `E500CABAAS0002`. Ajustar al contrato real del endpoint nuevo. |
| T9 | **Trazabilidad y logging**: `x-b3-*`, correlación con `reference_number` de la saga, registro de transiciones. | 0.5 d | T7 | Sin métricas ni alertas nuevas. |
| T10 | **Pruebas unitarias**: máquina de estados, validación de productos, mapeo de `makeCharge`, idempotencia, no-doble-compensación. | 1 d | T8 | |
| T11 | **Pruebas de integración** (WireMock para `ca-baas-products` y para el endpoint de Accounts). Escenarios de productos: tarjeta inactiva, cuenta inactiva, producto ajeno, cliente inexistente. Escenarios de acreditación: éxito; `notifications`/`HTTP 200` → compensa; rechazo de conexión → compensa; vencimiento de lectura → `EN_DUDA_ACREDITACION` (no compensa); duplicado → idempotencia; cargo `code = -1` → `EN_DUDA_CARGO`. | 1.5 – 2 d | T8, B1 | Los escenarios de conexión-vs-timeout son la prueba clave. Ya hay WireMock en el entorno. |

### Fase 4 — Integración y entrega

| ID | Tarea | Estimación | Depende de | Notas |
|----|-------|-----------|------------|-------|
| T12 | **Pruebas de no regresión** de `card-charge` sin cuenta destino: los seis `dhi_type` existentes se comportan igual. | 0.5 d | T6 | Garantía del compromiso "compatible hacia atrás". |
| T13 | **Pruebas en ambiente integrado**: contra el endpoint real de Accounts, `ca-baas-products` real, con red y credenciales, y **con la parametrización cargada en `ca-baas-configuration`**. | 1 – 1.5 d | B1, B2, B4, T11 | Aquí aparecen las sorpresas. Reservar holgura. |
| T14 | **Runbook de conciliación**: `EN_DUDA_CARGO` (vs. TSYS/GlobalTC), `EN_DUDA_ACREDITACION` (vs. Accounts), `COMPENSACION_FALLIDA`. | 0.5 – 1 d | Requisito operativo. |
| T15 | **Soporte a UAT** y corrección. | 2 – 3 d | Primera semana de agosto. |
| T16 | **Despliegue a Producción** y monitoreo. | 1 d | Fin de agosto. |

### Totales (desarrollo de `ca-baas-credit`)

| Fase | Estimación |
|------|-----------|
| Fase 0 | 0.5 d |
| Fase 1 — Cimientos | 2 – 3 d |
| Fase 2 — Orquestación | 3.5 – 4.5 d |
| Fase 3 — Errores y pruebas | 4 – 5 d |
| **Subtotal desarrollo (antes de UAT)** | **10 – 13 días hábiles** |
| Fase 4 — Integración y entrega | 5 – 7 d (incluye UAT y producción en agosto) |

## 3. Cronograma propuesto

| Semana | Fechas | Actividad |
|--------|--------|-----------|
| Semana 1 | 9 – 17 jul | Escalar B1–B5. Acordar contratos (B2, B5). T0, T1, T2, T4 contra simulador. |
| Semana 2 | 20 – 24 jul | T5 (contra simulador), T6, T7. Recepción del endpoint de Accounts (B2). |
| Semana 3 | 27 – 31 jul | T8, T9, T10, T11, T12, T13. Runbook (T14). Corte para UAT. |
| Semana 4 | 3 – 7 ago | **UAT** (T15). |
| Semanas 5-6 | 10 – 28 ago | Corrección, certificación, producción (T16). |

**Holgura de desarrollo:** 4 a 7 días hábiles. Cómoda **para el código de Credit**. Pero la holgura real del proyecto la fijan B1 y B2, no el desarrollo.

**Puntos de escalamiento:**
- **Miércoles 22 de julio:** si el contrato del endpoint de Accounts (B2) no está acordado, o la parametrización (B1) no está comprometida con fecha, escalar el riesgo de cronograma.
- **Jueves 24 de julio:** si el endpoint de Accounts no está disponible para pruebas integradas, T13 se comprime contra UAT. Escalar.

## 4. Evolución de la solución (registro)

| Opción | Pata de acreditación | Estado |
|--------|----------------------|--------|
| D | Credit consume `transfers-between-accounts` directamente | Rechazada (re-certificación de canales) |
| E | Credit llama a SProBaaS y replica la lógica | Superada (duplicación, PCI, dependencia con el core) |
| **F** | **Accounts expone endpoint nuevo (fachada); Credit lo consume** | **Adoptada** |

La Opción F resuelve las objeciones de D (no re-certifica canales, porque el endpoint es aditivo) y de E (no duplica lógica ni acopla Credit a SProBaaS). Es la que mejor respeta el bounded context, a costa de coordinación entre más equipos.

## 5. Fuera de alcance en esta entrega

- **Circuit breaker (Resilience4j)** sobre las llamadas a Accounts y a Products. Sí se incluyen tiempos de espera explícitos.
- **Métricas y alertas nuevas** (dashboard de estados, alerta por `EN_DUDA_*`). T9 cubre trazabilidad y logging; la observabilidad completa se evalúa post-UAT.
- **Consulta automática de estado** para resolver transacciones en duda. Conciliación manual con runbook.
- **Reversa de un adelanto ya completado** (débito de la cuenta). Ver Preguntas abiertas del ADR.
- **El endpoint nuevo de `ca-baas-accounts`, la parametrización de `ca-baas-configuration` y cualquier cambio en `ca-baas-products`.** Son responsabilidad de otros equipos; este plan cubre solo `ca-baas-credit`.
- **Corrección de H1, H2 y H6.** Preexistentes; tickets independientes.

## 6. Estrategia de desarrollo asistido (Spec Kit + GitHub Copilot)

### Enrutamiento de modelos

Créditos por millón de tokens:

| Modelo | Entrada | Salida | Cacheado |
|--------|--------:|-------:|---------:|
| Opus 4.6 | 500 | 2,500 | 50 |
| Sonnet 4.6 | 300 | 1,500 | 30 |
| GPT-5.3-Codex | 175 | 1,400 | 17 |

| Fase | Modelo sugerido | Por qué |
|------|-----------------|---------|
| `/speckit.plan` | **Opus** | Poco volumen, alto razonamiento (máquina de estados, clasificación de errores). |
| `/speckit.tasks` | **Sonnet** o **Codex** | Mecánico. |
| `/speckit.implement` | **Codex** | Mayor volumen de salida; el más económico. |
| Depuración de T8 | **Opus**, solo si Codex se atasca | Puntual. |

### Consumo estimado

| Fase | Créditos |
|------|---------:|
| `/speckit.specify` | 20 – 40 |
| `/speckit.plan` (Opus) | 50 – 90 |
| `/speckit.tasks` | 30 – 50 |
| `/speckit.implement` (Codex) | 180 – 280 |
| Iteración y depuración | 60 – 100 |
| **Total estimado** | **350 – 500** |

Baja respecto a la Opción E: el cliente del endpoint nuevo es más simple que el conector a SProBaaS (ya no se arma el payload técnico completo). Sube la parte de validación de productos.

Palancas de ahorro: una sola conversación por feature (cacheo al 10%), disciplina de salida (diffs, no reescrituras), contexto estable cargado al inicio.

### Nota de riesgo

**T6 y T8 no se delegan a modo agéntico sin revisión línea por línea.** T6 modifica una clase en producción; T8 decide si se revierte dinero.

## 7. Supuestos de la estimación

- Un solo desarrollador dedicado principalmente a esta feature en `ca-baas-credit`.
- `ca-baas-credit` tiene datasource propio (verificado).
- Ningún consumer usa hoy `card-charge` (confirmado): bajo riesgo de regresión.
- El endpoint nuevo de Accounts se entrega para pruebas integradas a más tardar el 24 de julio (B2).
- La parametrización está cargada en `ca-baas-configuration` antes de UAT (B1).
- `ca-baas-products` está disponible y su contrato se conoce a tiempo (B5).
- QA dispone de ambiente integrado con los tres microservicios ajenos desde el 27 de julio.

## 8. Qué necesitamos decidir antes de arrancar

1. Nombre y tipo del campo nuevo de cuenta destino en el `DHIRequest`.
2. Con qué identificador se consulta `ca-baas-products` y cómo se localizan la tarjeta y la cuenta en su respuesta (B5).
3. Contrato y modelo de error del endpoint nuevo de Accounts (B2).
4. Qué significa `x-country-code = "CAM"` (H5) y si aplica al modo orquestador.
5. ¿El endpoint nuevo permite consultar el estado de una acreditación (para el caso indeterminado)?
6. ¿Está en alcance la reversa de un adelanto ya completado?
7. Quién escala B1–B5 y con qué fecha compromiso.
8. Si se levantan H1, H2 y H6 como tickets independientes.

## Referencias

- 📄 ADR-0XX — Avance de Efectivo (Opción F): [enlace manual]
- 📁 Análisis técnico de `card-charge` y `transfers-between-accounts`: [rutas en Git]
- 🎫 Tickets de Jira: [agregar manualmente]
