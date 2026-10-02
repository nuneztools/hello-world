**Demo en vivo:**

1. **Exportar el CSV de Snyk.** En *Modify Columns* tienen que estar `PACKAGE_NAME_AND_VERSION` y `EXISTS_IN_DIRECT_DEPENDENCY`. Filtren `Computed Fixability` a *Fixable* y *Partially Fixable*.
2. **Guardar como `.xlsx`** y correr el prompt de M365 Copilot.
3. **Pegar la salida** en `reports/triage.md` dentro del repo.
4. **Revisar el triage entre todos.** Este es el momento humano del taller: discutan por qué el lote C no bloquea un release y por qué el lote D no se arregla subiendo versión.
5. `/speckit-specify` → **leer el `spec.md`** y mostrar los `[NEEDS CLARIFICATION]`.
6. `/speckit-clarify` → responder las preguntas.
7. `/speckit-plan` → **este es el paso que hay que leer con calma.** Revisar los SUPUESTOS.
8. `/speckit-tasks` → mostrar el `tasks.md`.
9. `/speckit-implement`
10. ```powershell
    .\gradlew clean test
    .\gradlew sonar
    ```
11. `git diff` y PR.


## 1. Prompt para Microsoft 365 Copilot (procesar el CSV)

Antes de pegarlo: **abrí el CSV en Excel y guardalo como `.xlsx`**, con los datos como tabla. Copilot en Excel trabaja mucho mejor con una tabla que con un CSV crudo.

```
Este archivo es un export de Snyk con vulnerabilidades de un microservicio Java/Spring Boot.

Agrupá los hallazgos por el valor de PACKAGE_NAME_AND_VERSION y clasificá cada
paquete en uno de estos cuatro lotes:

- Lote A: EXISTS_IN_DIRECT_DEPENDENCY = true y PROJECT_NAME distinto de integTest
- Lote B: EXISTS_IN_DIRECT_DEPENDENCY = false y PROJECT_NAME distinto de integTest
- Lote C: PROJECT_NAME = integTest
- Lote D: COMPUTED_FIXABILITY = "No Fix Supported"

Para cada paquete dame una fila con estas columnas:
paquete | versión actual | versión destino | severidad máxima | cantidad de issues | CVEs

Reglas:
- La versión destino es la MENOR de FIXED_IN_VERSION que sea mayor o igual a la
  versión actual. Ejemplo: si la actual es 6.3.0 y los fixes son 5.7.2, 6.3.1 y
  7.5.2, la respuesta es 6.3.1.
- Si un paquete tiene varios issues, la versión destino es la mayor de esas
  versiones mínimas, para que una sola cubra todos.
- Ordená cada lote por severidad descendente.

Entregá cuatro tablas en Markdown, una por lote, sin texto adicional.
```

Después copiás esa salida a un archivo `reports/triage.md` dentro del repo. Ese archivo es el insumo de GitHub Copilot.

> Si el CSV trae datos que seguridad considere sensibles, confirmá antes que el tenant de M365 esté aprobado para eso. Es un minuto de pregunta y te ahorra un problema.

---

## 2. Comandos core de SpecKit

En modo skills de Copilot se invocan con guion: `/speckit-specify`. Escribís `/` en el chat y te aparecen en la lista.

| Comando | Qué produce | ¿Obligatorio? |
|---|---|---|
| `/speckit-constitution` | Principios del proyecto | Una vez por repo |
| `/speckit-specify` | `spec.md` — el qué y el porqué | Sí |
| `/speckit-clarify` | Resuelve los `[NEEDS CLARIFICATION]` | Recomendado |
| `/speckit-plan` | `plan.md` — decisiones técnicas | Sí |
| `/speckit-tasks` | `tasks.md` — tareas ordenadas | Sí |
| `/speckit-analyze` | Detecta contradicciones spec/plan/tasks | Opcional |
| `/speckit-implement` | Escribe el código | Sí |

### Los prompts, listos para pegar

**`/speckit-specify`**
```
/speckit-specify Actualizar las dependencias vulnerables del LOTE A listadas en
reports/triage.md. Objetivo: cerrar las vulnerabilidades reportadas por Snyk sin
cambiar la versión de Java ni de Spring Boot, y sin modificar comportamiento de
negocio. El criterio de éxito es que el build compile, las pruebas pasen y Sonar
no reporte issues nuevos.
```

**`/speckit-clarify`**
```
/speckit-clarify
```
Sin argumentos. Él solo busca las ambigüedades del spec y te hace preguntas.

**`/speckit-plan`**
```
/speckit-plan Para cada paquete del lote A, determiná si la versión la fija el
BOM de Spring Boot o una declaración explícita en build.gradle, y cuál es el
cambio exacto: sobrescribir una propiedad en el bloque ext, o cambiar una línea
de dependencies. Verificá contra build.gradle real, no asumas. Marcá cada
decisión como HECHO (verificado) o SUPUESTO (requiere confirmación). Revisá si
caBaasBaseLibrary 10.3.13 restringe alguna de esas versiones.
```

**`/speckit-tasks`**
```
/speckit-tasks Una tarea por paquete. Agregá al final una tarea de build, una de
pruebas y una de Sonar.
```

**`/speckit-implement`**
```
/speckit-implement Aplicá únicamente los cambios del plan aprobado. No toques
código de negocio ni versiones fuera del plan.
```

---

## 3. Modelos y esfuerzo

Los modelos disponibles en Copilot cambian seguido, así que te lo doy por **clase de modelo**, que es lo que no se desactualiza. Verifiquen la lista real en el selector del chat.

| Paso | Clase de modelo | Esfuerzo | Por qué |
|---|---|---|---|
| `specify` | Rápido / base | Bajo | Es redacción estructurada, no razonamiento |
| `clarify` | Rápido / base | Bajo | Solo genera preguntas |
| `plan` | **Razonamiento** | **Alto** | Aquí se decide qué tocar. Es el paso que justifica gastar premium request |
| `tasks` | Rápido / base | Bajo | Descompone lo que ya está decidido |
| `analyze` | Razonamiento | Medio | Solo si el plan quedó grande |
| `implement` | Balanceado | Medio | Edición mecánica guiada por el plan |

**Regla práctica para el presupuesto de ~1900 premium requests:** gastá en `plan`, ahorrá en el resto. Un plan malo te hace repetir los cuatro pasos siguientes; un `tasks` mediocre se corrige en diez segundos.

Estimación por lote: entre 8 y 15 requests para el ciclo completo. O sea que el presupuesto mensual no es la restricción, pero sí lo es si alguien corre `implement` sobre los 116 issues de una sola vez y hay que rehacerlo.

---

## 4. Flujo para el taller

**Antes de empezar, cada quien verifica (3 min):**
```powershell
specify --version          # debe decir 1.0.12
specify integration status # default integration: copilot
```



---

## Tres cosas que decirles explícitamente

**Un lote por corrida.** Si corren los 116 juntos y el build se rompe, no van a saber cuál lo rompió. El lote A primero, que son las directas y las más controlables.

**El `plan.md` se lee, no se aprueba a ciegas.** Es donde el agente puede inventarse el nombre de una propiedad del BOM. Si dice SUPUESTO, hay que verificarlo contra la documentación de Spring Boot 3.5 antes de seguir.

**El lote D no es parte de esto.** Son las que no tienen fix disponible. Se resuelven con exclusión, reemplazo de librería o aceptación documentada del riesgo, y eso es conversación con el Tech Lead, no con un agente.

Si te queda tiempo al final, lo que más les va a servir es mostrarles el `git diff` del `implement` y preguntarles qué revisarían antes de aprobar ese PR.
