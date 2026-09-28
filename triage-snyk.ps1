<#
.SYNOPSIS
    Agrupa el export CSV de Snyk (Issues Detail) por paquete y produce un
    triage corto en Markdown, apto para pasarle a un agente sin quemar contexto.

.DESCRIPTION
    Entrada : CSV exportado desde Snyk > Analytics > Reports > Issues Detail
              con las columnas PACKAGE_NAME_AND_VERSION y
              EXISTS_IN_DIRECT_DEPENDENCY habilitadas en "Modify Columns".
    Salida  : Markdown en stdout (redirigir a un archivo versionado).

.EXAMPLE
    .\triage-snyk.ps1 -CsvPath .\reports\snyk_issues_detail.csv > .\reports\triage.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $CsvPath,

    # Proyectos Snyk a tratar como "no productivos" (no llegan al artefacto desplegado).
    [string[]] $NonProdProjects = @('integTest')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $CsvPath)) {
    throw "No se encontro el CSV: $CsvPath"
}

# --- Helpers -------------------------------------------------------------

# Snyk exporta listas como [""a"",""b""]. Devuelve los elementos limpios.
function Convert-SnykList {
    param([string] $Raw)
    if ([string]::IsNullOrWhiteSpace($Raw)) { return @() }
    return [regex]::Matches($Raw, '[^",\[\]]+') |
        ForEach-Object { $_.Value.Trim() } |
        Where-Object { $_ }
}

# "com.fasterxml.jackson.core:jackson-databind: 2.21.2" -> nombre + version.
# Una celda puede traer varios paquetes separados por coma.
function Convert-PackageCell {
    param([string] $Raw)
    $result = @()
    foreach ($part in ($Raw -split ',')) {
        $p = $part.Trim()
        if (-not $p) { continue }
        $m = [regex]::Match($p, '^(?<name>.*):\s*(?<ver>[^:\s]+)$')
        if ($m.Success) {
            $result += [pscustomobject]@{ Name = $m.Groups['name'].Value.Trim(); Version = $m.Groups['ver'].Value.Trim() }
        } else {
            $result += [pscustomobject]@{ Name = $p; Version = '?' }
        }
    }
    return $result
}

# Comparador laxo: 4.1.133.Final -> 4.1.133 ; 2.21.4 -> 2.21.4
function ConvertTo-ComparableVersion {
    param([string] $Raw)
    # @(...) es obligatorio: sin el, un solo grupo numerico devuelve un [int]
    # y "$nums += 0" haria aritmetica en vez de agregar al arreglo.
    $nums = @([regex]::Matches($Raw, '\d+') | ForEach-Object { [int]$_.Value })
    while ($nums.Count -lt 4) { $nums += 0 }
    return [version]::new($nums[0], $nums[1], $nums[2], $nums[3])
}

# Version minima de la lista de fixes que sea >= la version actual.
# Evita "arreglar" bajando de linea mayor (ej: semver 6.3.0 -> 6.3.1, no 5.7.2).
function Get-MinimalTarget {
    param([string] $Current, [string[]] $Candidates)
    if (-not $Candidates -or $Candidates.Count -eq 0) { return $null }
    try { $cur = ConvertTo-ComparableVersion $Current } catch { return ($Candidates | Select-Object -Last 1) }

    $viable = @()
    foreach ($c in $Candidates) {
        try {
            if ((ConvertTo-ComparableVersion $c) -ge $cur) { $viable += $c }
        } catch { }
    }
    if ($viable.Count -eq 0) { return ($Candidates | Sort-Object { ConvertTo-ComparableVersion $_ } | Select-Object -Last 1) }
    return ($viable | Sort-Object { ConvertTo-ComparableVersion $_ } | Select-Object -First 1)
}

# --- Carga y normalizacion ----------------------------------------------

$rows = Import-Csv -LiteralPath $CsvPath
if ($rows.Count -eq 0) { throw "El CSV no tiene filas." }

$required = @('ISSUE_SEVERITY','PACKAGE_NAME_AND_VERSION','EXISTS_IN_DIRECT_DEPENDENCY','COMPUTED_FIXABILITY','FIXED_IN_VERSION','PROJECT_NAME')
$missing  = $required | Where-Object { $_ -notin $rows[0].PSObject.Properties.Name }
if ($missing) {
    throw "Al CSV le faltan columnas: $($missing -join ', '). Agregalas en Snyk con 'Modify Columns' y volve a exportar."
}

$findings = New-Object System.Collections.Generic.List[object]

foreach ($r in $rows) {
    $cves   = Convert-SnykList $r.CVE
    $fixes  = Convert-SnykList $r.FIXED_IN_VERSION
    $direct = ($r.EXISTS_IN_DIRECT_DEPENDENCY -as [string]).Trim().ToLowerInvariant() -eq 'true'
    $isProd = $r.PROJECT_NAME -notin $NonProdProjects

    foreach ($pkg in (Convert-PackageCell $r.PACKAGE_NAME_AND_VERSION)) {
        $findings.Add([pscustomobject]@{
            Package    = $pkg.Name
            Current    = $pkg.Version
            Severity   = $r.ISSUE_SEVERITY
            Score      = [int]($r.SCORE -as [int])
            Fixability = $r.COMPUTED_FIXABILITY
            Direct     = $direct
            Prod       = $isProd
            Project    = $r.PROJECT_NAME
            Cves       = if ($cves) { $cves } else { @('(sin CVE)') }
            Fixes      = $fixes
            Target     = Get-MinimalTarget -Current $pkg.Version -Candidates $fixes
            Title      = $r.PROBLEM_TITLE
        })
    }
}

$sevRank = @{ 'Critical' = 4; 'High' = 3; 'Medium' = 2; 'Low' = 1 }

# --- Agrupacion por paquete ---------------------------------------------

$groups = $findings | Group-Object Package | ForEach-Object {
    $g       = $_.Group
    $targets = $g | Where-Object { $_.Target } | Select-Object -ExpandProperty Target -Unique
    $top     = ($g | Sort-Object { $sevRank[$_.Severity] } -Descending | Select-Object -First 1)

    [pscustomobject]@{
        Package    = $_.Name
        Current    = ($g | Select-Object -ExpandProperty Current -Unique) -join ', '
        Issues     = $g.Count
        MaxSev     = $top.Severity
        MaxRank    = $sevRank[$top.Severity]
        MaxScore   = ($g | Measure-Object Score -Maximum).Maximum
        Direct     = [bool]($g | Where-Object { $_.Direct })
        Prod       = [bool]($g | Where-Object { $_.Prod })
        Projects   = ($g | Select-Object -ExpandProperty Project -Unique) -join ', '
        Cves       = ($g | ForEach-Object { $_.Cves } | Select-Object -Unique)
        # Version unica que cubre todos los hallazgos del paquete: el maximo de los minimos.
        Target     = if ($targets) { ($targets | Sort-Object { ConvertTo-ComparableVersion $_ } | Select-Object -Last 1) } else { $null }
        NoFix      = [bool]($g | Where-Object { -not $_.Target })
        Partial    = [bool]($g | Where-Object { $_.Fixability -match 'Partially' })
    }
}

$sorted = $groups | Sort-Object @{E='MaxRank';D=$true}, @{E='MaxScore';D=$true}

$loteA = $sorted | Where-Object {  $_.Target -and  $_.Direct -and  $_.Prod }
$loteB = $sorted | Where-Object {  $_.Target -and -not $_.Direct -and  $_.Prod }
$loteC = $sorted | Where-Object {  $_.Target -and -not $_.Prod }
$sinFix = $sorted | Where-Object { -not $_.Target }

# --- Salida Markdown -----------------------------------------------------

function Write-Table {
    param($Items, [string] $Extra = '')
    if (-not $Items) { "_Sin hallazgos en este lote._"; ''; return }
    "| Paquete | Actual | Subir a | Sev | Issues | CVEs |"
    "|---|---|---|---|---|---|"
    foreach ($i in $Items) {
        $cves = if ($i.Cves.Count -gt 3) { "$(($i.Cves | Select-Object -First 3) -join ', ') (+$($i.Cves.Count - 3))" } else { $i.Cves -join ', ' }
        $tgt  = if ($i.Target) { $i.Target } else { '—' }
        "| ``$($i.Package)`` | $($i.Current) | **$tgt** | $($i.MaxSev) | $($i.Issues) | $cves |"
    }
    ''
}

"# Triage de vulnerabilidades — Snyk"
""
"- Fuente: ``$(Split-Path -Leaf $CsvPath)``"
"- Generado: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
"- Filas del CSV: $($rows.Count) · Hallazgos por paquete: $($findings.Count) · Paquetes únicos: $($groups.Count)"
""
"## Resumen"
""
"| Lote | Qué es | Paquetes |"
"|---|---|---|"
"| A | Directas de producción — se cambian en ``build.gradle`` | $($loteA.Count) |"
"| B | Transitivas de producción — normalmente las arrastra el BOM | $($loteB.Count) |"
"| C | Solo pruebas ($($NonProdProjects -join ', ')) — no llegan al artefacto desplegado | $($loteC.Count) |"
"| D | Sin versión de fix aplicable — requieren otra vía | $($sinFix.Count) |"
""
"## Lote A — dependencias directas de producción"
""
"Se declaran en ``build.gradle``. Es el lote de mayor prioridad y el más controlable."
""
Write-Table $loteA
"## Lote B — transitivas de producción"
""
"No están declaradas: las trae otra dependencia. Antes de fijar versión a mano, verificá si el BOM de Spring Boot ya las sube:"
""
'```'
".\gradlew dependencyInsight --dependency <artefacto> --configuration runtimeClasspath"
'```'
""
Write-Table $loteB
"## Lote C — solo en proyectos de prueba"
""
"No forman parte del artefacto desplegado. No deberían bloquear un release; se atienden aparte."
""
Write-Table $loteC
"## Lote D — sin versión de fix aplicable"
""
"**No se resuelven subiendo versión.** Requieren exclusión, reemplazo de librería o aceptación documentada del riesgo, con decisión del Tech Lead."
""
if ($sinFix) {
    "| Paquete | Actual | Sev | Issues | Directa | Proyecto | CVEs |"
    "|---|---|---|---|---|---|---|"
    foreach ($i in $sinFix) {
        $cves = if ($i.Cves.Count -gt 3) { "$(($i.Cves | Select-Object -First 3) -join ', ') (+$($i.Cves.Count - 3))" } else { $i.Cves -join ', ' }
        "| ``$($i.Package)`` | $($i.Current) | $($i.MaxSev) | $($i.Issues) | $(if ($i.Direct) { 'sí' } else { 'no' }) | $($i.Projects) | $cves |"
    }
    ''
} else {
    "_Sin hallazgos en este lote._"
    ''
}
"## Propuesta de bumps (borrador, requiere verificación)"
""
"Sobrescritura de propiedades del BOM en ``build.gradle``, bloque ``ext``:"
""
'```groovy'
"ext {"
foreach ($i in ($loteA + $loteB)) {
    "    // $($i.Package): $($i.MaxSev), $($i.Issues) issue(s)"
    "    // '<propiedad-del-bom>' = '$($i.Target)'"
}
"}"
'```'
""
"> El nombre de la propiedad del BOM (``jackson-bom.version``, ``netty.version``, …) no sale del CSV."
"> Confirmalo en la documentación de Spring Boot de la versión en uso antes de aplicarlo."
