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





















Antes del prompt, una cosa que conviene que el equipo tenga clara: **Java 21 no va a cerrar casi ninguna de las vulnerabilidades de Snyk.** Ese reporte es de versiones de librerías, no del JDK. Lo que las cierra en volumen es el BOM de Spring Boot 4.

O sea que Java 21 es un **prerrequisito** de Boot 4, no una solución a la presión que tienen encima. Es una decisión defendible, pero si alguien arriba espera ver bajar el número de vulnerabilidades esta semana, hay que decirlo ahora. El lote A de bumps puntuales sigue siendo lo único que da resultado rápido.

Dicho eso, va el prompt.

---

## Prompt para M365 Copilot

```
Actuá como Staff Engineer especializado en Java, Spring Boot y Gradle.

Necesito que generes los prompts exactos que voy a usar con GitHub Copilot y
SpecKit (Spec-Driven Development) para migrar un microservicio de Java 17 a
Java 21.

## Contexto del proyecto

Microservicio: ca-baas-credit. Es parte de una familia de microservicios
bancarios que procesan operaciones de tarjeta de crédito. Arquitectura por
capas: Controller → Delegate → Operation → Gateway.

Stack actual:
- Java 17, Spring Boot 3.5.14, Gradle
- Lombok, Jackson
- JaCoCo para cobertura
- JUnit Jupiter 5.12.2, Mockito 5.18.0, AssertJ 3.27.7
- SonarQube (plugin sonarqube-gradle-plugin 3.3)
- JFrog Artifactory (plugin 5.2.5)
- OpenAPI Generator 7.9.0
- Stack SOAP: jaxws-tools 4.0.3, jaxws-rt 4.0.3, spring-ws-core 4.1.2,
  jakarta.xml.ws-api 4.0.2, jakarta.xml.bind-api 4.0.2,
  jakarta.activation-api 2.1.3
- Spring Cloud Connectors 2.2.13.RELEASE, Spring Cloud 2.0.7.RELEASE
- Plugins internos del banco, versión caBaasBaseLibrary 10.3.13:
  ca-baas-gradle-plugin, ca-baas-soap-plugin, com.bns.cabaas.java-plugin

## Restricciones

- NO se actualiza Spring Boot en este cambio. Solo Java 17 → 21.
- NO se modifica comportamiento de negocio.
- Es un sistema financiero con operaciones que tienen efectos externos
  (autorizaciones y cargos hacia TSYS). Cualquier cambio requiere evidencia
  de que el comportamiento se preserva.
- Los plugins internos del banco son una caja negra: no sabemos si soportan
  Java 21. Eso debe quedar identificado como riesgo bloqueante, no asumido.

## Criterios de satisfacción

1. `./gradlew clean build` compila con Java 21.
2. Todas las pruebas existentes pasan sin modificar sus aserciones.
3. JaCoCo genera reporte de cobertura sin errores de class file version.
4. El análisis de SonarQube corre y no introduce issues nuevos.
5. La generación de código SOAP y OpenAPI sigue produciendo las mismas clases.
6. No se agregan dependencias nuevas salvo que sea estrictamente necesario
   para compatibilidad con Java 21.

## Comandos de SpecKit disponibles

/speckit-constitution, /speckit-specify, /speckit-clarify, /speckit-plan,
/speckit-tasks, /speckit-analyze, /speckit-implement

El flujo es: specify (el qué) → clarify (resolver ambigüedades) → plan (el cómo)
→ tasks (descomponer) → implement (ejecutar).

## Lo que necesito de vos

Para CADA comando de SpecKit, dame:

1. El prompt exacto, listo para copiar y pegar en el chat de Copilot.
2. Qué artefacto debería producir ese paso.
3. Qué debo revisar yo antes de pasar al siguiente paso.
4. Las preguntas que el agente DEBERÍA hacerme en ese paso. Si no las hace,
   es señal de que está asumiendo cosas.

Además, al final dame una lista separada de verificaciones previas que debo
hacer MANUALMENTE antes de empezar el flujo de SpecKit, con el comando de
Gradle o el archivo que debo revisar en cada una.

Importante: los prompts deben pedirle al agente que verifique contra el código
y los archivos reales, y que marque cada afirmación como HECHO (verificado) o
SUPUESTO (requiere confirmación). No quiero que invente versiones ni
compatibilidades.
```

---

## Lo que puede afectar migrar Java primero

Ordenado por probabilidad de que los frene.

**1. Los plugins internos del banco.** `caBaasBaseLibrary 10.3.13` es el riesgo número uno. Si `com.bns.cabaas.java-plugin` fija el toolchain o el `sourceCompatibility` internamente, no lo vas a poder sobreescribir desde tu `build.gradle`. Y si fue compilado contra Java 17, puede ni cargar. **Esto no es una pregunta para el agente, es una pregunta para quien mantiene esos plugins**, y conviene mandarla hoy mismo porque bloquea todo lo demás.

**2. La versión de Gradle.** Gradle necesita soportar Java 21 tanto para correr como para compilar. Revisá:
```
gradle/wrapper/gradle-wrapper.properties
```
Si están en una versión vieja, actualizar Gradle es un prerrequisito, y eso ya es un cambio aparte con su propio riesgo.

**3. Lombok.** Es el que más rompe en saltos de JDK, porque toca el compilador por dentro. Una versión vieja de Lombok falla duro contra JDK 21, con errores poco legibles. Como la versión la fija el BOM de Spring Boot 3.5, probablemente estén bien, pero verifiquen:
```
.\gradlew dependencyInsight --dependency lombok --configuration compileClasspath
```

**4. JaCoCo.** Cada versión de JaCoCo soporta hasta cierto *class file major version*. Java 21 es la 65. Si JaCoCo es viejo, el build compila pero la cobertura explota con "Unsupported class file major version". Es un fallo tardío y confunde.

**5. El stack SOAP y la generación de código.** `jaxws-tools` hace generación de código y herramientas así suelen tocar APIs internas del JDK. Con la encapsulación fuerte de las versiones modernas, eso puede fallar. Sumado a que `ca-baas-soap-plugin` es interno y opaco, yo pondría una tarea específica de verificar que las clases generadas salen idénticas antes y después.

**6. El plugin de SonarQube 3.3.** Es una versión relativamente vieja del plugin de Gradle. Vale verificar que soporta correr bajo Java 21, y por separado que el servidor de Sonar analiza bytecode 21.

**7. Mockito y ByteBuddy.** Mockito 5.18 está bien, pero ByteBuddy entra transitivamente e instrumenta bytecode. Si alguna versión queda vieja, las pruebas con mocks fallan de formas raras.

**8. CI y la imagen base.** Aunque les compile local, **los agentes de build y la imagen del contenedor tienen que tener JDK 21**. Si el pipeline de ACCP solo tiene 17, el build pasa en su máquina y falla en CI. Eso es coordinación con DevOps y conviene arrancarla en paralelo, no al final.

**9. Spring Cloud Connectors 2.2.13.RELEASE.** Esa librería está discontinuada desde hace años. No es un bloqueo para Java 21 necesariamente, pero es deuda que les va a estorbar cuando lleguen a Boot 4. Déjenlo anotado.

### Lo bueno

Spring Boot 3.5 **sí soporta Java 21**, así que no hay conflicto por ese lado. El salto es viable, y hacerlo antes de Boot 4 es el orden correcto: aislás los problemas de runtime de los problemas de framework.

### Las tres verificaciones de cinco minutos

Antes de armar nada, corran esto:

```powershell
.\gradlew --version
.\gradlew dependencyInsight --dependency lombok --configuration compileClasspath
.\gradlew dependencyInsight --dependency org.jacoco:org.jacoco.core --configuration testRuntimeClasspath
```

Y en paralelo, el correo a quien mantiene `ca-baas-gradle-plugin` preguntando si `caBaasBaseLibrary` soporta Java 21 y si hay una versión planificada que lo haga. Esa respuesta decide si el taller de la próxima semana es sobre migración o sobre esperar.
