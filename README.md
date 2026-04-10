# AION 2 DPS Meter

Overlay de DPS em tempo real para AION 2 usando captura de pacotes via Npcap.

## Arquitetura

```
Npcap → Node.js (cap + WebSocket) → Flutter (overlay transparente)
```

## Pré-requisitos

- **Windows 10/11** (Npcap só funciona no Windows)
- **Npcap**: https://npcap.com/#download (instale com "WinPcap API compatibility")
- **Node.js 18+**: https://nodejs.org/
- **Flutter 3.x** com suporte a Windows Desktop

---

## Servidor Node.js

### Instalação para Desenvolvimento

```powershell
cd server
npm install
```

### Executar em modo simulado (para desenvolvimento)

```powershell
npm run dev
# ou
node src/index.js --mock
```

### Executar com captura real (requer Administrador)

```powershell
# Listar interfaces de rede disponíveis
node src/index.js --list-interfaces

# Captura na interface padrão (auto-detect)
node src/index.js

# Especificar interface
node src/index.js --iface="\Device\NPF_{GUID}"
```

> ⚠️ A captura real requer que o processo seja executado **como Administrador**.

---

## Frontend (Flutter)

### Instalação

```powershell
cd frontend
flutter pub get
```

### Executar

```powershell
flutter run -d windows
```

### Build release

```powershell
flutter build windows --release
```

---

## 📡 Protocolo AION 2 Implementado

O parser foi implementado baseado em projetos open-source existentes:

- [nousx/aion2-dps-meter](https://github.com/nousx/aion2-dps-meter) (Kotlin - 391 skills)
- [Kuroukihime/AIon2-Dps-Meter](https://github.com/Kuroukihime/AIon2-Dps-Meter) (C#)
- [TK-open-public/Aion2-Dps-Meter](https://github.com/tk-open-public/aion2-dps-meter) (TypeScript/Kotlin)

### ✨ Características

✅ **Auto-detecção de porta** via magic bytes  
✅ **Parser VarInt** (Protocol Buffers)  
✅ **Opcodes confirmados:** Dano direto (0x04 0x38), DoT (0x05 0x38), Nickname (0x04 0x8D)  
✅ **Special flags:** Crítico, Back Attack, Perfect, Double, Parry  
✅ **Skill enrichment:** Nomes de skills, detecção automática de classe, cache de nicknames  
✅ **90 skills validadas** do AION 2 TW

### 🎯 Skill Code Ranges (AION 2)

Os skill codes no AION 2 seguem o padrão XXYYZZZZ (8 dígitos), onde XX é o ID da classe:

| Range   | Classe       | Nome KR | Exemplos                                                       |
| ------- | ------------ | ------- | -------------------------------------------------------------- |
| **11M** | Gladiator    | 검성    | 11_020_000 (Keen Strike), 11_250_000 (Zikel's Blessing)        |
| **12M** | Templar      | 수호성  | 12_010_000 (Vicious Strike), 12_780_000 (Fury)                 |
| **13M** | Assassin     | 살성    | 13_010_000 (Quick Slice), 13_350_000 (Heart Gore)              |
| **14M** | Ranger       | 궁성    | 14_020_000 (Snipe), 14_310_000 (Rapid Scattershot)             |
| **15M** | Sorcerer     | 마도성  | 15_210_000 (Flame Arrow), 15_320_000 (Delayed Explosion)       |
| **16M** | Elementalist | 정령성  | 16_010_000 (Cold Shock), 16_370_000 (Fire Blessing)            |
| **17M** | Cleric       | 치유성  | 17_010_000 (Earth's Retribution), 17_420_000 (Yustiel's Power) |
| **18M** | Chanter      | 호법성  | 18_010_000 (Wave Strike), 18_780_000 (Earth's Promise)         |

**Nota:** Estes ranges foram validados contra 3 projetos open-source do AION 2 e substituem os códigos do AION 1 (que começavam em 10M).

### 📖 Documentação Detalhada

Veja **[AION2_PROTOCOL.md](AION2_PROTOCOL.md)** para:

- Estrutura completa de pacotes
- Tabela de opcodes
- Guia de testes com jogo real
- Troubleshooting

---

## Configuração do Parser (OPCIONAL)

O parser já está configurado com protocolo real do AION 2 TW.

Para debug de pacotes brutos, defina a variável de ambiente antes de iniciar:

```powershell
$env:DEBUG = "1"
node src/index.js
```

---

## Estrutura de arquivos

```
aion2_dpsmeter/
├── server/
│   ├── src/
│   │   ├── index.js         # Entry point + orquestração
│   │   ├── capture.js       # Captura com Npcap via cap / MockCapture
│   │   ├── packet_parser.js # Parse dos pacotes → CombatEvent
│   │   ├── calculator.js    # DPS/HPS com janela deslizante de 10s
│   │   ├── ws_server.js     # WebSocket server (ws://localhost:8765)
│   │   └── scan_connections.js # Auto-detect porta do jogo
│   └── package.json
└── frontend/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart            # App Flutter + janela overlay
        ├── backend_service.dart # Lança aion2_server.exe automaticamente
        ├── ws_service.dart      # WebSocket client com auto-reconexão
        ├── models.dart          # PlayerStats, DpsSnapshot, DpsPoint
        ├── dps_chart.dart       # Gráfico de linha em tempo real (fl_chart)
        └── party_table.dart     # Tabela de ranking com barra de progresso
```

## Protocolo WebSocket

O backend envia JSON a cada segundo:

```json
{
  "type": "snapshot",
  "data": {
    "session_duration": 42.0,
    "total_damage": 123456,
    "players": [
      {
        "id": 1,
        "name": "Gladiator",
        "total_damage": 80000,
        "current_dps": 2341.5,
        "total_hits": 45,
        "total_crits": 8,
        "crit_rate": 17.8,
        "max_hit": 4200
      }
    ],
    "dps_history": {
      "1": [{"t": 1.0, "dps": 1200.0, "hps": 0.0}, ...]
    }
  }
}
```

O Flutter pode enviar:

```json
{"action": "reset"}   // Reseta a sessão
{"action": "ping"}    // Verifica conexão
```

---

## 🚀 Build e Distribuição

### Build Automático (Recomendado)

```powershell
# No diretório raiz do projeto
.\build_release.ps1
```

Este script irá:

1. ✅ Verificar Node.js e Flutter
2. ✅ Instalar dependências do servidor (`npm install`)
3. ✅ Compilar o servidor com `pkg` → `aion2_server.exe` (~36 MB)
4. ✅ Copiar `aion2_server.exe` para `frontend/assets/backend/`
5. ✅ Compilar o Flutter em modo release

### Build Manual

```powershell
# 1. Compilar servidor Node.js com pkg
cd server
npm run build
# Resultado: server/dist/aion2_server.exe

# 2. Copiar para assets do Flutter
Copy-Item server\dist\aion2_server.exe frontend\assets\backend\

# 3. Compilar Flutter
cd frontend
flutter build windows --release
# Resultado: frontend/build/windows/x64/runner/Release/
```

### Distribuição

O pacote final estará em `dist/` e contém:

- `frontend.exe` — Aplicação principal Flutter
- `aion2_server.exe` — Servidor Node.js (embutido nos assets)
- DLLs e dependências do Flutter
- Pasta `data/` com assets compilados

**Requisitos no sistema de destino:**

- ⚠️ Windows 10/11 (64-bit)
- ⚠️ Npcap instalado: https://npcap.com/#download
- ⚠️ Privilégios de Administrador (para captura de pacotes)

### Modo de Desenvolvimento vs Release

- **Desenvolvimento**: Servidor e frontend executados separadamente
  - Servidor: `cd server && node src/index.js --mock`
  - Frontend: `cd frontend && flutter run -d windows`
- **Release**: `frontend.exe` inicia o servidor Node.js embutido automaticamente

---

## 🚀 CI/CD e Releases Automáticas

### GitHub Actions

#### **Build and Release** ([`.github/workflows/release.yml`](.github/workflows/release.yml))

Executa em push de tags `v*.*.*` ou manualmente via `workflow_dispatch`.

**O que faz:**

1. ✅ Instala Npcap silenciosamente (necessário para compilar o módulo `cap`)
2. ✅ `npm install` + `npm run build` → `aion2_server.exe` via `pkg`
3. ✅ Compila Flutter para Windows release
4. ✅ Cria ZIP de distribuição
5. ✅ Cria GitHub Release com binários anexados (apenas em push de tag)
6. ✅ Upload de artefatos com retenção de 30 dias

### Como Criar uma Release

```powershell
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0
# O GitHub Actions compila e publica automaticamente
```

Para testar sem criar release, use **Run workflow** na interface do GitHub Actions com uma versão de teste.

### Artefatos da Release

```
aion2_dpsmeter-v1.0.0-windows-x64.zip
├── frontend.exe                # Executável principal Flutter
├── flutter_windows.dll         # DLLs do Flutter
├── data/
│   └── flutter_assets/
│       └── assets/
│           └── backend/
│               └── aion2_server.exe  # Servidor Node.js embutido (~36 MB)
└── README.txt
```

**Tamanho aproximado:** 50-60 MB (comprimido)

### Status dos Builds

[![Release](https://github.com/rogerluiz/aion2_dpsmeter/actions/workflows/release.yml/badge.svg)](https://github.com/rogerluiz/aion2_dpsmeter/actions/workflows/release.yml)

---

## Troubleshooting

### "Servidor não encontrado" / Backend não inicia

```powershell
# Verificar se o executável existe
Test-Path frontend\assets\backend\aion2_server.exe

# Compilar se necessário
cd server ; npm run build
Copy-Item dist\aion2_server.exe ..\frontend\assets\backend\
```

### "Erro ao iniciar servidor"

Execute manualmente para ver logs de erro:

```powershell
node server\src\index.js --mock
```

### Captura não detecta pacotes

- Certifique-se que o Npcap está instalado
- Execute como **Administrador**
- Verifique se o AION 2 TW está rodando
- Liste as interfaces e especifique a correta:
  ```powershell
  node server\src\index.js --list-interfaces
  node server\src\index.js --iface="\Device\NPF_{GUID}"
  ```

---
