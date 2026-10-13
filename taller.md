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












##Copilot M365 Triage


Este archivo es un export de Snyk con vulnerabilidades del microservicio
ca-baas-credit (Java 17, Spring Boot 3.5.14, Gradle).

Agrupá los hallazgos por el valor de PACKAGE_NAME_AND_VERSION y clasificá
cada paquete en uno de estos cuatro lotes:

- Lote A: EXISTS_IN_DIRECT_DEPENDENCY = true y PROJECT_NAME distinto de integTest
- Lote B: EXISTS_IN_DIRECT_DEPENDENCY = false y PROJECT_NAME distinto de integTest
- Lote C: PROJECT_NAME = integTest
- Lote D: COMPUTED_FIXABILITY = "No Fix Supported"

Para cada paquete dame una fila con:
paquete | versión actual | versión destino | severidad máxima | issues | CVEs

Reglas de la versión destino:
- Es la MENOR de FIXED_IN_VERSION que sea mayor o igual a la versión actual.
  Ejemplo: actual 6.3.0, fixes 5.7.2 / 6.3.1 / 7.5.2 → la respuesta es 6.3.1.
- Si un paquete tiene varios issues, tomá la MAYOR de esas versiones mínimas,
  para que una sola versión cubra todos.
- Si el paquete cae en el lote D, dejá la versión destino vacía.

Notas sobre el formato del CSV:
- PACKAGE_NAME_AND_VERSION puede traer dos puntos, como
  "com.fasterxml.jackson.core:jackson-databind: 2.21.2". El nombre es todo lo
  anterior al último ": ".
- Una celda puede traer varios paquetes separados por coma.
- CVE y FIXED_IN_VERSION vienen como listas entre corchetes y comillas dobles.
- Algunas filas no tienen CVE. Marcalas como "(sin CVE)".

Ordená cada lote por severidad descendente.
Entregá cuatro tablas en Markdown, una por lote, sin texto adicional.
Al final agregá una línea con el conteo de paquetes por lote.




## SpecKit Triage

/speckit-specify Actualizar las dependencias vulnerables del LOTE A listadas en
reports/triage.md para ca-baas-credit.

Alcance: solo los paquetes del lote A. NO se actualiza Java ni Spring Boot.
NO se modifica comportamiento de negocio. No se agregan dependencias nuevas.

Contexto: microservicio bancario que procesa operaciones de tarjeta de crédito
con integraciones hacia TSYS vía DHI. Arquitectura por capas
Controller → Delegate → Operation → Gateway.

Criterios de satisfacción:
1. ./gradlew clean build compila sin errores.
2. Todas las pruebas existentes pasan sin modificar sus aserciones.
3. SonarQube no reporta issues nuevos.
4. El lote D queda documentado como pendiente, no se intenta resolver acá.




/speckit-clarify




/speckit-plan Para cada paquete del lote A, determiná si la versión la fija el
BOM de Spring Boot o una declaración explícita en build.gradle, y cuál es el
cambio exacto: sobrescribir una propiedad en el bloque ext, o cambiar una línea
de dependencies.

Verificá contra build.gradle real, no asumas. Si necesitás el árbol de
dependencias, indicá qué comando dependencyInsight haría falta en vez de
inventar la respuesta.

Revisá si caBaasBaseLibrary 10.3.13 o los plugins internos
(ca-baas-gradle-plugin, ca-baas-soap-plugin, com.bns.cabaas.java-plugin)
restringen alguna de esas versiones.

Marcá cada decisión como HECHO (verificado en el build) o SUPUESTO
(requiere confirmación).

NO ejecutes ./gradlew build en este paso. La verificación con build real va
como tarea del tasks.md.




/speckit-tasks Una tarea por paquete. Al final agregá una tarea de build, una
de pruebas y una de Sonar.



/speckit-implement Aplicá únicamente los cambios aprobados en plan.md.
Trabajá en tandas de máximo 5 tareas. Al terminar cada tanda, pará y reportá
qué quedó hecho antes de seguir. No toques código de negocio ni versiones
fuera del plan.







## Update Agents.dm


Revisá el AGENTS.md de este repo (ca-baas-credit) y proponé una versión mejorada. Antes de escribir, explorá el código. No inventes nada: si algo no tiene evidencia en el código, marcalo como "hipótesis" o dejalo fuera. Mostrame el diff propuesto antes de aplicar cambios.

## 1. Optimización para cache de tokens
- El AGENTS.md debe ser ESTABLE: nada de fechas, "última actualización", estado de tareas en curso ni contenido volátil. Cada edición invalida el prefijo cacheado de todas las sesiones.
- Ordená el contenido de más estable (reglas, arquitectura) a menos estable.
- Mantenelo conciso (objetivo: menos de ~250 líneas). Lo detallado va en archivos aparte (por ejemplo docs/agents/architecture.md y docs/agents/upgrade-playbook.md). El AGENTS.md los referencia y explica cuándo leerlos.
- No hardcodees versiones de librerías, Java ni Spring. Apuntá a la fuente de verdad (build.gradle, gradle.properties, libs.versions.toml si existe).
- Evaluá si conviene usar .github/instructions/*.instructions.md con `applyTo` para reglas que solo aplican a ciertos archivos (ej. build.gradle) y explicame la recomendación.
- Agregá reglas de comportamiento que ahorren tokens:
  - buscar con grep/símbolos antes de abrir archivos completos;
  - no leer carpetas generadas (build/, generatedSoap, código generado de OpenAPI, .gradle/);
  - no releer archivos sin cambios;
  - ejecutar tareas Gradle específicas en vez de builds completos cuando sea posible;
  - no pegar logs completos, solo el fragmento relevante.

## 2. Actualización de librerías, Java y Spring
Creá un playbook (archivo separado, referenciado desde AGENTS.md) para:
a) actualizar dependencias puntuales, por ejemplo a partir de un reporte de vulnerabilidades de Snyk;
b) migrar Java (17 → 21) y Spring Boot (3 → 4).
Incluí:
- cómo leer las versiones actuales y dónde se declaran;
- compatibilidad a verificar: Gradle wrapper, toolchain de Java, Lombok, plugins de Gradle (incluida la generación SOAP/OpenAPI y GenerateSoapClientTask con configuration cache), Jackson y Jakarta;
- consultar las guías oficiales de migración en lugar de asumir cambios;
- un cambio lógico por commit (separar el upgrade de runtime de los cambios de dependencias y de los fixes de código);
- verificación obligatoria: `./gradlew clean compileJava`, luego tests unitarios, luego integTest. No confiar en builds cacheados;
- no cambiar comportamiento funcional durante un upgrade;
- revisar issues nuevos de SonarQube introducidos por el cambio.

## 3. Estructura del proyecto
Documentá la estructura de carpetas/paquetes de ca-baas-credit con la responsabilidad de cada una, según evidencia del código. Incluí main, test, integTest, recursos y código generado.

## 4. Patrones de diseño
Identificá los patrones que realmente se observan (ej. Delegate, Command/Strategy en Operations, Gateway/Adapter, Factory, Builder vía Lombok). Para cada uno, citá 1-2 clases de ejemplo como evidencia. Distinguí entre patrón confirmado e hipótesis. No clasifiques el sistema como DDD solo por la existencia de paquetes `domain` o `factory`.

## 5. Flujo de una petición REST
Describí el flujo usual (se observa Controller → Delegate → Operation → Gateway) usando un endpoint real como ejemplo:
- dónde se valida;
- dónde se mapean los DTOs;
- dónde se llama a sistemas externos (DHI/TSYS, ca-baas-globaltc, ca-baas-keymaster, otros ca-baas-*);
- cómo se manejan errores y excepciones.
Un diagrama Mermaid corto es bienvenido.

## 6. Reglas adicionales a incluir
- Datos sensibles: nunca loguear ni persistir números de tarjeta, cuentas o Core IDs en formato natural. Documentá el uso de surrogate/desurrogate (keymaster) según lo que veas en el código.
- Operaciones con efecto financiero (DHI/TSYS, reversiones): no agregar retries automáticos sin analizar la idempotencia; señalar el riesgo.
- Convenciones Sonar conocidas: `lombok.addLombokGeneratedAnnotation = true`; constantes String en enums dentro de una clase anidada privada `Messages`.
- Convenciones de tests existentes (unit, integTest, APITests) y cómo ejecutarlas.
- Si un cambio introduce deuda técnica solicitada, documentarla en vez de "corregirla" sin consultar.

Mantené el idioma actual del AGENTS.md.






.\gradlew clean test
.\gradlew sonar
git diff --stat




Aqui inicia la Fase 1 de Snyk Fix

Va la Fase 1. Antes de los prompts, tres ajustes técnicos que tienen que estar en el spec o el agente los va a hacer mal.

**Netty tiene que quedar en una sola versión.** El triage pide tres distintas (4.1.137, 4.1.136, 4.1.135) porque calculó el mínimo por artefacto. Netty no funciona así: todos sus artefactos van alineados. **Todo a 4.1.137.Final.**

**Tomcat igual.** `embed-core` pide 10.1.56 y `embed-websocket` 10.1.55. **Ambos a 10.1.56.**

**Micrometer y Reactor son salto de generación, no parche.** `micrometer-core 1.15.11 → 1.16.7` y `reactor-core 3.6.6 → 3.8.7` cruzan a la línea siguiente, que probablemente es la que acompaña a Boot 4. Los separo en un sub-lote aparte, para que si rompen no se lleven puestos a los demás.

---

## specify

```
/speckit-specify Actualizar las dependencias vulnerables del sub-lote A1 de
ca-baas-credit, sobre Spring Boot 3.5.14 y Java 17.

ALCANCE EXPLÍCITO. Solo estos paquetes:

Grupo A1.1 — alineación de familia (una sola versión por familia):
- io.netty:* (netty-handler, netty-codec, netty-transport-native-unix-common)
  4.1.118.Final → 4.1.137.Final  [Critical, 10 issues]
- org.apache.tomcat.embed:* (tomcat-embed-core, tomcat-embed-websocket)
  10.1.54 → 10.1.56  [Critical, 12 issues]

Grupo A1.2 — bumps independientes:
- org.apache.httpcomponents.client5:httpclient5   5.4.2 → 5.6.4   [Critical, 3]
- org.apache.httpcomponents.core5:httpcore5-h2    5.3.3 → 5.4.3   [High, 3]
- ch.qos.logback:logback-core                     1.5.32 → 1.5.36 [High, 3]
- com.microsoft.sqlserver:mssql-jdbc        10.2.1.jre8 → 10.2.4.jre8 [High, 1]
- org.apache.commons:commons-lang3                3.17.0 → 3.18.0 [High, 1]
- org.springframework.data:spring-data-commons    3.5.11 → 3.5.12 [High, 4]
- org.springframework.data:spring-data-keyvalue   3.5.11 → 3.5.12 [Medium, 1]
- org.springframework.security:spring-security-web 6.5.10 → 6.5.11 [High, 2]
- org.springframework.ws:spring-ws-core           4.1.3 → 4.1.4   [High, 1]
- org.springframework.ws:spring-xml               4.1.3 → 4.1.4   [High, 1]
- org.springframework:spring-core                 6.2.18 → 6.2.19 [Medium, 1]

Grupo A1.3 — salto de generación, mayor riesgo:
- io.micrometer:micrometer-core    1.15.11 → 1.16.7 [High, 4]
- io.projectreactor:reactor-core   3.6.6 → 3.8.7    [High, 2]

FUERA DE ALCANCE (no tocar):
- Cualquier paquete que requiera Spring Framework 7 o Spring Security 7:
  spring-security-core, spring-security-crypto, spring-security-oauth2-jose,
  spring-context-support, spring-expression, spring-data-jpa.
  Esos van en una fase posterior junto con Spring Boot 4.
- El lote D (sin fix disponible).
- El lote C (integTest, Node). No llega al artefacto desplegado.
- Java 17 → 21. Es un cambio independiente.
- No se actualiza Spring Boot. Queda en 3.5.14.
- No se modifica comportamiento de negocio.

CONTEXTO: microservicio bancario de tarjeta de crédito, integraciones hacia
TSYS vía DHI. Arquitectura Controller → Delegate → Operation → Gateway.
Stack SOAP (jaxws, spring-ws). Plugins internos caBaasBaseLibrary 10.3.13.

CRITERIOS DE SATISFACCIÓN:
1. ./gradlew clean build compila sin errores.
2. Todas las pruebas pasan sin modificar sus aserciones.
3. SonarQube no introduce issues nuevos.
4. Los artefactos de cada familia (netty, tomcat, spring-data) quedan en una
   única versión coherente. Verificable con dependencyInsight.
5. Queda documentado qué issues del reporte Snyk cubre este cambio y cuáles no.
```

## clarify

```
/speckit-clarify
```

## plan

```
/speckit-plan Determiná, contra build.gradle y el árbol real de dependencias,
CÓMO se aplica cada bump.

Pregunta central a resolver primero: ¿estos paquetes están declarados
explícitamente en build.gradle, o los trae el BOM de Spring Boot 3.5.14 como
transitivas? El reporte de Snyk los marca como "direct dependency", pero en un
proyecto Spring Boot netty, tomcat y logback normalmente son transitivas de los
starters. No asumas: verificá.

Según el caso, el cambio es distinto:
- Si lo fija el BOM → sobrescribir la propiedad correspondiente en el bloque ext
  (netty.version, tomcat.version, logback.version, etc.). Confirmá el nombre
  exacto de cada propiedad contra la documentación de Spring Boot 3.5, no lo
  inventes.
- Si está declarado en dependencies → cambiar esa línea.

Requisitos de coherencia:
- Las tres librerías de io.netty deben quedar en 4.1.137.Final. Nunca mezcladas.
- Los dos artefactos de tomcat.embed deben quedar en 10.1.56.
- spring-data-commons y spring-data-keyvalue pertenecen al mismo tren; si el BOM
  de Spring Data los fija en conjunto, subí el tren completo en vez de artefacto
  por artefacto.

Riesgos a evaluar explícitamente:
- micrometer-core 1.15 → 1.16 y reactor-core 3.6 → 3.8 cruzan de generación.
  Determiná si son compatibles con Boot 3.5.14 o si en realidad requieren Boot 4.
  Si requieren Boot 4, sacalos del alcance y decilo.
- spring-core 6.2.19 y spring-security-web 6.5.11: verificá que subir estos sin
  subir el resto de Framework/Security no genere mezcla de versiones dentro de
  la misma familia.
- Si algún plugin interno (caBaasBaseLibrary 10.3.13, ca-baas-gradle-plugin,
  ca-baas-soap-plugin) restringe alguna de estas versiones, marcalo como
  bloqueante.

Marcá cada decisión como HECHO (verificado en el build o en documentación
oficial citada) o SUPUESTO.

NO ejecutes ./gradlew build en este paso. La verificación va en tasks.md.
```

## tasks

```
/speckit-tasks Agrupá las tareas en tres tandas, en este orden:

Tanda 1 — A1.1: alineación de familias (netty a 4.1.137.Final, tomcat a 10.1.56).
Tanda 2 — A1.2: los bumps independientes.
Tanda 3 — A1.3: micrometer y reactor, solo si el plan confirmó compatibilidad
          con Boot 3.5.

Cada tanda termina con: build, pruebas, y un dependencyInsight que verifique
que las versiones efectivas son las esperadas.

Agregá una tarea final que escriba reports/bump-result-fase1.md con qué issues
del reporte Snyk quedaron cubiertos y cuáles siguen abiertos.
```

## implement

```
/speckit-implement Aplicá solo la Tanda 1. Al terminar, pará y reportá qué
cambió antes de seguir con la Tanda 2.
```

Y repetís el `implement` por tanda. Entre tanda y tanda, en terminal:

```powershell
.\gradlew clean build
.\gradlew test
.\gradlew dependencyInsight --dependency netty-handler --configuration runtimeClasspath
.\gradlew dependencyInsight --dependency tomcat-embed-core --configuration runtimeClasspath
git diff
```

---

**Qué esperar al final:** si las tres tandas pasan, cerrás alrededor de 50 issues, incluidas 25 de severidad crítica entre netty, tomcat y httpclient5. Eso te quita la presión inmediata y te deja hacer Boot 4 con tiempo.

**Si la Tanda 3 rompe**, sacá micrometer y reactor y mandalos a la fase de Boot 4. No vale la pena pelearse con ellos ahora: son 6 issues de 50.



Segunda parte del Plan:

Sí, en la misma ventana del chat del plan. Pegale esto tal cual:

```
Decisiones:

1. ACEPTO reducir el alcance de 14 a 12 coordenadas. Enmendá spec.md:
   - Actualizá FR-014 y FR-015 para que el alcance sean 12 coordenadas.
   - Agregá que micrometer-core y reactor-core quedan explícitamente
     diferidos a la fase de migración a Spring Boot 4, con la justificación
     verificada: sus versiones destino solo existen en
     spring-boot-dependencies:4.0.0.

2. NO ratifico todavía D-1 a D-6. Necesito verlas primero. Listámelas en una
   tabla con estas columnas:
   familia afectada | versión que queda | versión del resto de la familia |
   qué incompatibilidad concreta podría producir | cómo se detectaría
   (compilación, prueba unitaria, o solo en runtime)

   Separá las que son desviaciones reales de coherencia de familia de las que
   son artefactos independientes sin ciclo de release compartido. No las
   presentes todas como equivalentes.

3. Agregá a plan.md una sección "Hallazgo estructural" con esto:

   El proyecto no aplica el BOM de Spring Boot: no hay
   io.spring.dependency-management, ni dependencyManagement{}, ni platform().
   Consecuencia: no existe un piso de versiones y las dependencias derivan
   libremente. Esto explica el volumen del reporte de Snyk.
   Evidencia: netty 4.1.118.Final vs 4.1.132 del BOM; reactor-core 3.6.6 vs
   3.7.18; mssql-jdbc 10.2.1.jre8 vs 12.10.2.jre11.
   Recomendación: evaluar la adopción del BOM como parte de la migración a
   Spring Boot 4, NO en este cambio. Fuera de alcance de la Fase 1.

4. Riesgo adicional a verificar antes de implementar: si netty viene de
   lettuce-core:6.6.0.RELEASE, forzar netty a 4.1.137.Final vía constraints le
   impone a Lettuce una versión contra la que no fue probada, y Lettuce está en
   el camino de operaciones con efecto financiero.
   Revisá qué rango o versión de netty declara el POM de
   lettuce-core:6.6.0.RELEASE y si 4.1.137.Final cae dentro. Si declara rango
   cerrado o versión exacta, marcalo como riesgo y proponé verificación
   específica de Redis en las pruebas.

Confirmá el mecanismo propuesto: platform() nativo de Gradle + constraints +
edición de las 3 líneas ya declaradas (httpclient5, mssql-jdbc, spring-ws-core).

No toques build.gradle ni ejecutes el build todavía.
```

Cuando te devuelva la tabla de D-1 a D-6, pasámela y las revisamos antes de que sigas a `tasks`.


3ra parte del Plan

El análisis está bien hecho y la evidencia es sólida: los POMs con parent declarado para D-2/D-3, y el `tomcat-embed-el` sin bloque `<dependencies>` para D-1. **Ratificá las cinco y descartá D-1.**

Tres cosas que agregaría antes de pasar a `tasks`:

**1. D-2 es la de peor relación riesgo/detección, y eso se resuelve con un grep.** Si el código no usa la API Fluent de HttpComponents, el riesgo es teórico. Vale la pena confirmarlo en diez segundos en vez de arrastrar la duda.

**2. El hallazgo de Lettuce merece una prueba específica.** V-R5 está bien identificado: 19 parches por encima de la matriz probada, en el stack de reconexión, y un `SET/GET` feliz no lo toca. La verificación no puede ser "Redis responde", tiene que ser "Redis se recupera tras perder la conexión".

**3. Ojo con el crecimiento del cambio.** Ratificar las cinco lleva el PR de 12 coordenadas a más de 30 artefactos, sobre todo por los 12 módulos de Spring Framework de D-6. Es correcto y no negociable —el co-versionado de Framework no admite mezcla—, pero el gate de `acceptanceTest` que definiste tiene que cubrir eso, y la descripción del PR debe decirlo.

Y un detalle para que no te confunda después: ratificar D-5 **no cierra** la crítica de `spring-security-oauth2-jose`. Esa necesita 7.0.7 y queda diferida a Boot 4. D-5 solo mantiene la familia coherente en 6.5.11.

Pegale esto:

```
RATIFICO D-2, D-3, D-4, D-5 y D-6. DESCARTO D-1 (tomcat-embed-el queda fuera:
POM 10.1.56 sin bloque <dependencies>, comparte numeración pero no API).

Antes de /speckit.tasks, tres cosas:

1. D-2 — verificá si el código realmente usa la API Fluent:
   buscá imports de org.apache.hc.client5.http.fluent en src/.
   Si no hay uso, documentalo en plan.md: el riesgo queda como teórico y la
   ratificación es solo preventiva. Si hay uso, identificá en qué clases, para
   dirigir la verificación ahí.

2. V-R5 (Lettuce / reconexión) — no basta con verificar que Redis responde.
   Agregá al tasks.md una tarea de verificación explícita de reconexión:
   provocar pérdida de conexión al Redis y confirmar que el cliente se recupera
   y reanuda operaciones. Un SET/GET en camino feliz no cubre este riesgo.
   Si no hay forma de simular eso en el entorno disponible, decilo y marcalo
   como riesgo residual para el PR en vez de darlo por verificado.

3. Alcance real — actualizá plan.md con el conteo final de artefactos que
   toca el cambio una vez ratificadas D-2 a D-6 (no solo las 12 coordenadas
   objetivo, sino todos los artefactos arrastrados por coherencia de familia,
   incluidos los 12 módulos de Spring Framework de D-6). Ese número va en la
   descripción del PR.

4. Dejá explícito en plan.md que ratificar D-5 NO cierra la vulnerabilidad
   crítica de spring-security-oauth2-jose (requiere 7.0.7, diferida a Boot 4).
   D-5 solo preserva coherencia de familia en 6.5.11. Esa crítica sigue abierta
   al terminar la Fase 1.

Confirmado también RK-7: no tocar netty-tcnative ni netty-incubator.

Cuando termines esto, seguimos con /speckit.tasks. No ejecutes el build todavía.
```
