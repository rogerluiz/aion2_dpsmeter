# build_release.ps1
# Script para construir versão release do AION 2 DPS Meter
# Compila o servidor Node.js (pkg) e empacota com o frontend Flutter

Write-Host "AION 2 DPS Meter - Build Release" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

$ErrorActionPreference = "Stop"
$rootDir     = $PSScriptRoot
$serverDir   = Join-Path $rootDir "server"
$frontendDir = Join-Path $rootDir "frontend"
$assetsDir   = Join-Path $frontendDir "assets\backend"
$distDir     = Join-Path $rootDir "dist"

# ────────────────────────────────────────────────────────────────────
# Passo 1: Verificar pré-requisitos
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[1/5] Verificando pré-requisitos..." -ForegroundColor Yellow

$nodeVersion = node --version 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Node.js não encontrado. Instale em https://nodejs.org/" -ForegroundColor Red
    exit 1
}
Write-Host "  Node.js: $nodeVersion" -ForegroundColor Green

flutter --version 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Flutter não encontrado." -ForegroundColor Red
    exit 1
}
Write-Host "  Flutter: OK" -ForegroundColor Green
Write-Host "✅ Pré-requisitos OK" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# Passo 2: Instalar dependências do servidor Node.js
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[2/5] Instalando dependências do servidor Node.js..." -ForegroundColor Yellow

Push-Location $serverDir
try {
    npm install --legacy-peer-deps
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ Erro no npm install" -ForegroundColor Red; exit 1 }
    Write-Host "✅ Dependências instaladas" -ForegroundColor Green
} finally { Pop-Location }

# ────────────────────────────────────────────────────────────────────
# Passo 3: Compilar servidor Node.js com pkg
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[3/5] Compilando servidor Node.js com pkg..." -ForegroundColor Yellow

Push-Location $serverDir
try {
    $serverDist = Join-Path $serverDir "dist"
    if (Test-Path $serverDist) { Remove-Item -Recurse -Force $serverDist }
    New-Item -ItemType Directory -Path $serverDist -Force | Out-Null

    npx pkg src/index.js --target node18-win-x64 --output "$serverDist\aion2_server.exe" --compress GZip
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ Erro na compilação pkg" -ForegroundColor Red; exit 1 }

    $exePath = Join-Path $serverDist "aion2_server.exe"
    if (-not (Test-Path $exePath)) { Write-Host "❌ aion2_server.exe não gerado" -ForegroundColor Red; exit 1 }

    $sz = [math]::Round((Get-Item $exePath).Length / 1MB, 1)
    Write-Host "✅ Servidor compilado: aion2_server.exe ($sz MB)" -ForegroundColor Green
} finally { Pop-Location }

# ────────────────────────────────────────────────────────────────────
# Passo 4: Copiar servidor para assets do Flutter
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[4/5] Copiando servidor para assets do Flutter..." -ForegroundColor Yellow

if (-not (Test-Path $assetsDir)) { New-Item -ItemType Directory -Path $assetsDir -Force | Out-Null }
Copy-Item (Join-Path $serverDir "dist\aion2_server.exe") (Join-Path $assetsDir "aion2_server.exe") -Force
Write-Host "✅ Servidor copiado para: frontend/assets/backend/" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# Passo 5: Compilar Flutter em release
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[5/5] Compilando Flutter para Windows (release)..." -ForegroundColor Yellow

Push-Location $frontendDir
try {
    flutter pub get
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { Write-Host "❌ Erro na compilação Flutter" -ForegroundColor Red; exit 1 }
    Write-Host "✅ Flutter compilado com sucesso" -ForegroundColor Green
} finally { Pop-Location }

# Criar pacote dist/
$releaseDir = Join-Path $frontendDir "build\windows\x64\runner\Release"
if (Test-Path $distDir) { Remove-Item -Recurse -Force $distDir }
New-Item -ItemType Directory -Path $distDir -Force | Out-Null
Copy-Item -Recurse "$releaseDir\*" $distDir -Force

# ────────────────────────────────────────────────────────────────────
# Resumo final
# ────────────────────────────────────────────────────────────────────
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "✨ Build concluído com sucesso!`n" -ForegroundColor Green

$frontendExe = Join-Path $distDir "frontend.exe"
if (Test-Path $frontendExe) {
    $sz = [math]::Round((Get-Item $frontendExe).Length / 1MB, 1)
    Write-Host "  Executável : frontend.exe ($sz MB)" -ForegroundColor Cyan
    Write-Host "  Localização: $distDir" -ForegroundColor Cyan
}

Write-Host "`nPara distribuir, copie toda a pasta 'dist/' para o computador de destino." -ForegroundColor Yellow
Write-Host "⚠️  Requer Npcap instalado e privilegios de Administrador." -ForegroundColor Yellow
Write-Host "⚠️  Download Npcap: https://npcap.com/#download" -ForegroundColor Yellow
