# Matriz de versiones destino — migración a Spring Boot 4

**Propósito.** Referencia de versiones y de ítems de migración para llevar
`ca-baas-credit` de Spring Boot 3.5.14 a Spring Boot 4.

**Cómo leer las marcas de evidencia:**

- `[VERIFICADO]` — combinación que ya corre en producción dentro de la
  organización, en un microservicio CABAAS equivalente con cero vulnerabilidades.
- `[OFICIAL]` — documentado en la guía de migración de Spring Boot 4.0.
- `[POR CONFIRMAR]` — requiere verificación contra el código o el build de
  `ca-baas-credit`. No asumir.

---

## 1. Plataforma destino

| Componente | Actual | Destino | Evidencia |
|---|---|---|---|
| Spring Boot | 3.5.14 | **4.1.0** | `[VERIFICADO]` |
| Spring Framework | 6.2.18 | **7.0.8** | `[VERIFICADO]` |
| Spring Security | 6.5.10 | **7.0.5** | `[VERIFICADO]` |
| Spring WS | 4.1.2 / 4.1.3 | **5.0.2** | `[VERIFICADO]` — también en el classpath del `buildscript` |
| Java | 17 | 17 o 21 | `[OFICIAL]` Boot 4 requiere Java 17 **como mínimo**; 21 es recomendado, no obligatorio |
| caBaasBaseLibrary | 10.3.13 | `[POR CONFIRMAR]` | 10.4.3 es la versión con evidencia contra Boot 4.1.0. Confirmar en Artifactory si hay una posterior y si está verificada contra esta combinación |
| OpenAPI Generator | 7.9.0 | **7.14.0** | `[VERIFICADO]` |
| springdoc-openapi | `[POR CONFIRMAR]` | **3.0.3** (`springdoc-openapi-starter-webmvc-ui`) | `[VERIFICADO]` — springdoc 3.x es la línea de Boot 4 |
| Gradle | `[POR CONFIRMAR]` | `[POR CONFIRMAR]` | revisar `gradle/wrapper/gradle-wrapper.properties` |

### Decisión pendiente: ¿Java 21 en este cambio?

Boot 4 **no exige** Java 21. Las dos rutas son válidas:

- **Separadas (recomendado):** Boot 4 sobre Java 17, y Java 21 como cambio
  posterior independiente. Aísla variables en un cambio que ya es grande, y deja
  Java 21 como un PR chico y reversible.
- **Juntas:** un solo ciclo de build, pruebas y UAT. Preferible solo si el costo
  de un segundo ciclo de UAT supera el riesgo de mezclar dos variables.

Java 21 **no cierra ninguna vulnerabilidad del reporte de Snyk**. Todo el beneficio
de seguridad está en Boot 4.

---

## 2. Cambios obligatorios de Spring Boot 4 `[OFICIAL]`

Estos salen de la guía de migración oficial y aplican con independencia de la
versión de Java.

### 2.1 Jackson 3 es el default — **mayor riesgo del cambio**

Boot 4 adopta Jackson 3 como librería JSON por defecto, con **nuevos group IDs y
nuevos paquetes**. No es un bump de versión: es un cambio de coordenadas y de
imports.

**Por qué importa aquí:** cierra el cluster más grande del Lote D del reporte de
Snyk (`jackson-databind 2.21.2`, 16 críticas; `jackson-core 2.21.2`, 3 altas),
que hoy figura como "No Fix Supported" porque no hay fix en la línea 2.x.

**Por qué es el mayor riesgo:** Jackson está en el camino de serialización hacia
TSYS vía DHI. Un cambio de comportamiento en el mapeo de un payload financiero
**no lo detecta el compilador** y puede no aparecer en pruebas unitarias con mocks.

**Mitigación disponible:** existe un módulo `spring-boot-jackson2` como paso
intermedio deprecado, si conviene desacoplar la migración de Jackson del resto.

**Verificación exigida:** comparación de payloads serializados antes y después,
para cada contrato hacia TSYS/DHI y para cada endpoint expuesto. No basta con que
las pruebas pasen.

### 2.2 Reorganización de starters y módulos

- `spring-boot-starter-web` → **`spring-boot-starter-webmvc`**
- Flyway y Liquibase requieren su propio starter `[POR CONFIRMAR si aplica]`
- Los starters de test deben corresponder a la tecnología bajo prueba
- Despliegues WAR sobre Tomcat usan `spring-boot-starter-tomcat-runtime`
  `[POR CONFIRMAR si aplica]`

### 2.3 Cambios en pruebas

- **`@MockBean` y `@SpyBean` fueron eliminados** → usar `@MockitoBean` y
  `@MockitoSpyBean`
- MockMvc, `TestRestTemplate` y `WebClient` requieren anotaciones explícitas

**Acción:** inventariar cuántas clases de test usan `@MockBean` / `@SpyBean`. Es
un reemplazo mecánico, pero el volumen define el esfuerzo.

### 2.4 Eliminaciones

Todo lo deprecado en la línea 3.x **fue removido**. Antes de migrar, compilar con
`options.deprecation = true` sobre Boot 3.5 y resolver las advertencias.

Funcionalidades removidas en Boot 4 `[POR CONFIRMAR si alguna aplica]`:
Undertow, auto-configuración reactiva de Pulsar, scripts de arranque embebidos en
el ejecutable, integración con Spock, Spring Session sobre Hazelcast y MongoDB,
y el cargador clásico de uber-jar.

### 2.5 Baseline de plataforma

- **Jakarta EE 11**, Servlet 6.1
- Kotlin 2.2+ `[no aplica]`
- GraalVM native-image 25+ `[no aplica salvo que se use native]`

### 2.6 Renombres de propiedades

Varias propiedades cambiaron de nombre (Spring Session Redis, MongoDB, Jackson).
Existe el módulo `spring-boot-properties-migrator` como ayuda temporal; **debe
removerse después de migrar**.

### 2.7 Cambios de comportamiento por defecto

- Probes de liveness y readiness habilitados por defecto
- Logback usa UTF-8 por defecto
- DevTools live reload deshabilitado por defecto
- `PropertyMapper` ya no invoca adaptadores para valores nulos por defecto
- Spring Batch corre en memoria por defecto `[no aplica salvo que se use Batch]`

### 2.8 Spring Security 7

Spring Authorization Server pasó a formar parte de Spring Security. Boot ya no
gestiona su versión por separado: usar `spring-security.version` en lugar de
`spring-authorization-server.version`.

Consultar además las notas de migración de Spring Security 7.0 para los cambios
de la API de configuración.

---

## 3. Migraciones de código identificadas

### 3.1 Spring Cloud Connectors → java-cfenv

| Actual en `ca-baas-credit` | Destino |
|---|---|
| `springCloudConnectorsVersion = '2.2.13.RELEASE'` | eliminar |
| `springCloudVersion = '2.0.7.RELEASE'` | eliminar |
| — | `io.pivotal.cfenv:java-cfenv-boot:3.5.1` `[VERIFICADO]` |

Spring Cloud Connectors está discontinuado. `java-cfenv` es su sucesor para leer
`VCAP_SERVICES` en Cloud Foundry.

**Requiere cambios de código** donde se consuman servicios enlazados (datasources,
Redis, credenciales). No es solo cambio de versión.

**Acción:** inventariar las clases que usan la API de Spring Cloud Connectors
antes de estimar.

### 3.2 Stack SOAP

El stack SOAP (`jaxws-tools`, `jaxws-rt`, `spring-ws-core`, `ca-baas-soap-plugin`,
`jakarta.xml.*`) es un área de riesgo conocida bajo el Tomcat de Jakarta EE 11.

Una configuración verificada en la organización agregó explícitamente:

```groovy
implementation 'com.sun.xml.messaging.saaj:saaj-impl:3.0.4'
implementation 'com.sun.xml.messaging.saaj:metro-saaj:3.0.4'
```

con el comentario `//SOAP Tomcat problem`.

**Acción:** verificar si `ca-baas-credit` presenta el mismo síntoma al levantar el
contexto bajo Boot 4. Si lo presenta, estas dos coordenadas lo resuelven.

### 3.3 Driver de base de datos

| Actual | Destino |
|---|---|
| `mssql-jdbc 10.2.1.jre8` | **`13.4.0.jre11`** `[VERIFICADO]` |

Cambia el classifier (`jre8` → `jre11`). El target de la Fase 1 (`10.2.4.jre8`) es
un paso intermedio, no el destino final.

### 3.4 Framework de pruebas

| Actual | Destino | Evidencia |
|---|---|---|
| `junitJupiterVersion = '5.12.2'` | **`6.1.0`** | `[VERIFICADO]` |
| `mockitoJunitJupiter = '5.18.0'` | **`5.23.0`** | `[VERIFICADO]` |
| `assertjCore = '3.27.7'` | mantener o revisar | la configuración de referencia usa 3.26.3, que es **inferior** — no bajar por copiar |

Mantener `junit-vintage-engine` como red de seguridad para pruebas que no migren
de inmediato.

---

## 4. Patrón de gestión de versiones

**No se usa el BOM de Spring Boot.** El patrón de la organización es pinear
versiones explícitamente mediante variables en `ext`, más bloques `constraints` y
`resolutionStrategy` para forzar transitivas vulnerables.

Ese patrón **funciona**: hay un microservicio CABAAS con cero vulnerabilidades
usándolo. El problema en `ca-baas-credit` no es la ausencia de BOM, sino que los
pines no se mantuvieron al día.

**Decisión:** mantener el patrón existente. No introducir
`io.spring.dependency-management` ni `platform()` en esta migración.

### 4.1 Overrides de seguridad — forma a replicar

Netty, con los ocho artefactos alineados a la misma versión:

```groovy
constraints {
    implementation("io.netty:netty-buffer:4.2.16.Final")       { because("Override vulnerable/outdated transitive version") }
    implementation("io.netty:netty-codec:4.2.16.Final")        { because("Override vulnerable/outdated transitive version") }
    implementation("io.netty:netty-codec-dns:4.2.16.Final")    { because("Override vulnerable/outdated transitive version") }
    implementation("io.netty:netty-common:4.2.16.Final")       { because("Override vulnerable/outdated transitive version") }
    implementation("io.netty:netty-handler:4.2.16.Final")      { because("Override vulnerable/outdated transitive version") }
    implementation("io.netty:netty-resolver:4.2.16.Final")     { because("Override vulnerable/outdated transitive version") }
    implementation("io.netty:netty-resolver-dns:4.2.16.Final") { because("Override vulnerable/outdated transitive version") }
    implementation("io.netty:netty-transport:4.2.16.Final")    { because("Override vulnerable/outdated transitive version") }
}
```

`[VERIFICADO]` — netty **4.2.x** (salto de línea mayor sobre 4.1) convive con
`spring-boot-starter-data-redis` y Lettuce en una configuración en producción.
Esto reduce el riesgo V-R5 identificado en la Fase 1, que quedó marcado como
desconocido.

Tomcat, por grupo en vez de artefacto por artefacto:

```groovy
configurations.configureEach {
    resolutionStrategy.eachDependency { DependencyResolveDetails details ->
        if (details.requested.group == 'org.apache.tomcat.embed') {
            details.useVersion('11.0.24')
            details.because('Override vulnerable/outdated transitive version')
        }
    }
}
```

`[VERIFICADO]` — **Tomcat 11**, no 10.1.x. Boot 4 va sobre Jakarta EE 11. El
`eachDependency` por grupo cubre todos los artefactos sin enumerarlos, lo que
evita las desviaciones de coherencia de familia que aparecieron en la Fase 1.

---

## 5. Relación con la Fase 1 (sub-lote A1 sobre Boot 3.5)

La Fase 1 **sigue siendo válida y conviene terminarla**: cierra ~50 issues sin
esperar a Boot 4.

Dos de sus targets son escalones, no destinos finales:

| Paquete | Target Fase 1 | Destino final |
|---|---|---|
| netty (familia) | 4.1.137.Final | **4.2.16.Final** |
| mssql-jdbc | 10.2.4.jre8 | **13.4.0.jre11** |

**Corrección al "hallazgo estructural" registrado en el `plan.md` de la Fase 1:**
la ausencia del BOM no es un defecto de `ca-baas-credit` ni la causa del volumen
de vulnerabilidades. Es el patrón de la organización, y hay evidencia de que
permite llegar a cero vulnerabilidades. La causa real es la falta de mantenimiento
de los pines. La recomendación correcta no es adoptar el BOM, sino mantener al día
las variables de `ext` y los bloques de override.

---

## 6. Preguntas a resolver antes de escribir el spec

1. ¿Qué versión de `caBaasBaseLibrary` se usa? La verificada contra Boot 4.1.0, o
   la más reciente de Artifactory con verificación propia.
2. ¿Java 17 o Java 21 en este cambio? (ver sección 1)
3. ¿Qué versión de Gradle requiere Boot 4.1.0, y cuál tiene hoy el proyecto?
4. ¿Cuántas clases de test usan `@MockBean` / `@SpyBean`?
5. ¿Qué clases consumen la API de Spring Cloud Connectors?
6. ¿Qué contratos de serialización hacia TSYS/DHI deben compararse byte a byte
   antes y después de Jackson 3?
7. ¿Qué advertencias de deprecación emite el build actual sobre Boot 3.5 con
   `options.deprecation = true`?

---

## Fuentes

- Guía oficial de migración a Spring Boot 4.0 —
  https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide
- Requisito de versión mínima de Java para Spring Boot 4 —
  https://docs.bswen.com/blog/2026-03-04-spring-boot-4-java-version/
