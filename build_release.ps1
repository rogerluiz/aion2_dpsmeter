# build_release.ps1
# Script para construir versão release do AION 2 DPS Meter
# Combina o backend Python (PyInstaller) com frontend Flutter

Write-Host "🚀 AION 2 DPS Meter - Build Release" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

$ErrorActionPreference = "Stop"
$rootDir = $PSScriptRoot
$backendDir = Join-Path $rootDir "backend"
$frontendDir = Join-Path $rootDir "frontend"
$venvDir = Join-Path $rootDir ".venv"

# ────────────────────────────────────────────────────────────────────
# Passo 1: Verificar ambiente Python
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[1/6] Verificando ambiente Python..." -ForegroundColor Yellow

if (-not (Test-Path $venvDir)) {
    Write-Host "❌ Virtual environment não encontrado em: $venvDir" -ForegroundColor Red
    Write-Host "Execute: python -m venv .venv" -ForegroundColor Red
    exit 1
}

$pythonExe = Join-Path $venvDir "Scripts\python.exe"
if (-not (Test-Path $pythonExe)) {
    Write-Host "❌ Python não encontrado no venv" -ForegroundColor Red
    exit 1
}

Write-Host "✅ Python encontrado: $pythonExe" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# Passo 2: Instalar PyInstaller se necessário
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[2/6] Verificando PyInstaller..." -ForegroundColor Yellow

& $pythonExe -m pip install --quiet pyinstaller==6.10.0
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Erro ao instalar PyInstaller" -ForegroundColor Red
    exit 1
}

Write-Host "✅ PyInstaller pronto" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# Passo 3: Compilar backend com PyInstaller
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[3/6] Compilando backend Python..." -ForegroundColor Yellow

Push-Location $backendDir
try {
    # Limpar builds anteriores
    if (Test-Path "dist") { Remove-Item -Recurse -Force "dist" }
    if (Test-Path "build") { Remove-Item -Recurse -Force "build" }
    
    # Executar PyInstaller
    & $pythonExe -c @"
import PyInstaller.__main__
from pathlib import Path

backend_dir = Path(r'$backendDir')

PyInstaller.__main__.run([
    str(backend_dir / 'main.py'),
    '--name=aion2_backend',
    '--onefile',
    '--console',
    '--clean',
    '--add-data', f'{backend_dir / "packet_parser.py"};.',
    '--add-data', f'{backend_dir / "calculator.py"};.',
    '--add-data', f'{backend_dir / "capture.py"};.',
    '--hidden-import', 'scapy.all',
    '--hidden-import', 'scapy.layers.inet',
    '--hidden-import', 'websockets',
    '--hidden-import', 'asyncio',
])
"@
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Erro na compilação do backend" -ForegroundColor Red
        exit 1
    }
    
    $backendExe = Join-Path "dist" "aion2_backend.exe"
    if (-not (Test-Path $backendExe)) {
        Write-Host "❌ Backend executável não foi gerado" -ForegroundColor Red
        exit 1
    }
    
    $exeSize = (Get-Item $backendExe).Length / 1MB
    Write-Host "✅ Backend compilado: aion2_backend.exe ($([math]::Round($exeSize, 2)) MB)" -ForegroundColor Green
}
finally {
    Pop-Location
}

# ────────────────────────────────────────────────────────────────────
# Passo 4: Copiar backend para assets do Flutter
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[4/6] Copiando backend para assets..." -ForegroundColor Yellow

$assetsBackendDir = Join-Path $frontendDir "assets\backend"
if (-not (Test-Path $assetsBackendDir)) {
    New-Item -ItemType Directory -Path $assetsBackendDir -Force | Out-Null
}

$backendExe = Join-Path $backendDir "dist\aion2_backend.exe"
$targetExe = Join-Path $assetsBackendDir "aion2_backend.exe"

Copy-Item $backendExe $targetExe -Force
Write-Host "✅ Backend copiado para: frontend/assets/backend/" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# Passo 5: Compilar Flutter em release
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[5/6] Compilando Flutter para Windows..." -ForegroundColor Yellow

Push-Location $frontendDir
try {
    # Atualizar dependências
    flutter pub get
    
    # Build release
    flutter build windows --release
    
    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Erro na compilação do Flutter" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Flutter compilado com sucesso" -ForegroundColor Green
}
finally {
    Pop-Location
}

# ────────────────────────────────────────────────────────────────────
# Passo 6: Criar pacote de distribuição
# ────────────────────────────────────────────────────────────────────
Write-Host "`n[6/6] Criando pacote de distribuição..." -ForegroundColor Yellow

$releaseDir = Join-Path $frontendDir "build\windows\x64\runner\Release"
$distDir = Join-Path $rootDir "dist"

if (Test-Path $distDir) {
    Remove-Item -Recurse -Force $distDir
}

New-Item -ItemType Directory -Path $distDir -Force | Out-Null

# Copiar todos os arquivos do release
Copy-Item -Recurse "$releaseDir\*" $distDir -Force

Write-Host "✅ Pacote criado em: dist/" -ForegroundColor Green

# ────────────────────────────────────────────────────────────────────
# Resumo final
# ────────────────────────────────────────────────────────────────────
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
Write-Host "✨ Build concluído com sucesso!`n" -ForegroundColor Green

$frontendExe = Join-Path $distDir "frontend.exe"
if (Test-Path $frontendExe) {
    $exeSize = (Get-Item $frontendExe).Length / 1MB
    Write-Host "📦 Executável: frontend.exe ($([math]::Round($exeSize, 2)) MB)" -ForegroundColor Cyan
    Write-Host "📂 Localização: $distDir" -ForegroundColor Cyan
}

Write-Host "`nPara distribuir, copie toda a pasta 'dist/' para o computador de destino." -ForegroundColor Yellow
Write-Host "⚠️  Requer privilégios de administrador para captura de pacotes!" -ForegroundColor Yellow
Write-Host "⚠️  Npcap deve estar instalado no sistema de destino!" -ForegroundColor Yellow
