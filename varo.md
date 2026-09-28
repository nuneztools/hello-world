````
`mermaid`

## Where to find deeper context
- Business/domain context (glossary, target architecture, external API contracts): `docs/context/`
- Engineering principles every spec must honor: `.specify/memory/constitution.md`
- Always-on coding rules: `.github/copilot-instructions.md`


# Glosario de dominio — ca-baas-tokenization-gateway

> ⚠️ ARCHIVO DE PRUEBA (canary). La entrada ZARPAZO es ficticia y sirve solo para validar que Copilot recupera este archivo on-demand. **Borrala después del test.** El resto puede quedar como semilla del glosario real.

## Términos

- **ZARPAZO**: nombre interno del _retry budget_ del flujo dual-routing. Default: **3** intentos. _(canary — borrar)_

<!-- Cuando valides el test, borrá la línea ZARPAZO y empezá a poblar el glosario real: PAN, BIN, token, idempotency key, Store & Forward, eligibility, provisioning, x-country-code, GatewayCCAFactory, CaBaaS, DataPower, etc. -->


specify workflow add --dev .\workflows\cabaas-dependency-bump
specify workflow list
specify workflow info cabaas-dependency-bump
specify workflow run cabaas-dependency-bump

run: "powershell -NoProfile -File tools/triage-snyk.ps1 -CsvPath reports/snyk_issues_detail.csv > reports/triage.md"

C:\Development\Projects\PythonPrjTest\.venv\Scripts\specify.exe integration status

Set-Alias specify "C:\Development\Projects\PythonPrjTest\.venv\Scripts\specify.exe"

```

olicito la instalación/habilitación de las siguientes herramientas en mi equipo Windows de desarrollo:

**1. PowerShell 7 estable x64**  
Instalar PowerShell 7 y agregar `pwsh` al PATH. Actualmente el equipo dispone únicamente de Windows PowerShell 5.1.

**2. Node.js 22 LTS o superior x64**  
Incluir npm y agregar `node` y `npm` al PATH.

**3. GitHub Copilot CLI estable**  
Instalar GitHub Copilot CLI (`@github/copilot`) y agregar el comando `copilot` al PATH.

La herramienta será utilizada desde terminal para ejecutar workflows de SpecKit integrados con GitHub Copilot.
