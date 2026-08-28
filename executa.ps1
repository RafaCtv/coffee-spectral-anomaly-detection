# Orquestrador local: extrai e roda o monitor.
#
#   .\executa.ps1
#   .\executa.ps1 -Modo replay
#   .\executa.ps1 -SoMonitor
#   .\executa.ps1 -ComFiguras
#
# Agendador de Tarefas:
#   Programa   : powershell.exe
#   Argumentos : -ExecutionPolicy Bypass -File "CAMINHO\executa.ps1"
#   Iniciar em : CAMINHO_DO_REPOSITORIO

param(
    [ValidateSet("operacao", "replay")]
    [string]$Modo = "",
    [switch]$SoMonitor,
    [switch]$ComFiguras
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$RSCRIPT = "Rscript"
if (-not (Get-Command $RSCRIPT -ErrorAction SilentlyContinue)) {
    $candidato = Get-ChildItem "C:\Program Files\R", "D:\Aplicativos" -Filter "Rscript.exe" `
                 -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($candidato) { $RSCRIPT = $candidato.FullName }
    else { throw "Rscript nao encontrado. Ajuste `$RSCRIPT neste script." }
}

New-Item -ItemType Directory -Force -Path log | Out-Null
$log = "log\execucao.log"

function Registra($texto) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $texto" | Tee-Object -FilePath $log -Append
}

Registra "=== inicio ==="

if (-not $SoMonitor) {
    Registra "extraindo serie"
    python gee\extrai_serie.py
    if ($LASTEXITCODE -ne 0) {
        Registra "falha na extracao ($LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

Registra "rodando o monitor"
if ($Modo) { & $RSCRIPT R\monitora.R $Modo } else { & $RSCRIPT R\monitora.R }
if ($LASTEXITCODE -ne 0) {
    Registra "falha no monitor ($LASTEXITCODE)"
    exit $LASTEXITCODE
}

if ($ComFiguras) {
    Registra "gerando figuras"
    & $RSCRIPT R\figuras.R
}

if (Test-Path "estado\estado_global.csv") {
    Import-Csv "estado\estado_global.csv" | Format-List | Out-String | Write-Host
}

Registra "=== fim ==="
