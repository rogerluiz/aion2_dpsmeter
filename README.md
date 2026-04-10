# AION 2 DPS Meter

Overlay de DPS em tempo real para AION 2 usando captura de pacotes via Npcap.

## Arquitetura

```
Npcap → Python (Scapy + WebSocket) → Flutter (overlay transparente)
```

## Pré-requisitos

- **Windows 10/11** (Npcap só funciona no Windows)
- **Npcap**: https://npcap.com/#download (instale com "WinPcap API compatibility")
- **Python 3.11+**
- **Flutter 3.x** com suporte a Windows Desktop

---

## Backend (Python)

### Instalação para Desenvolvimento

```bash
# Criar virtual environment
python -m venv .venv

# Ativar venv (Windows PowerShell)
.venv\Scripts\Activate.ps1

# Instalar dependências
cd backend
pip install -r requirements.txt
```

### Executar em modo simulado (para desenvolvimento)

```bash
python main.py --mock
```

### Executar com captura real (requer Administrador)

```bash
# Listar interfaces de rede disponíveis
python main.py --list-ifaces

# Captura na interface padrão
python main.py

# Especificar interface (use o nome exato do --list-ifaces)
python main.py --iface "Ethernet"
```

> ⚠️ A captura real requer que o processo seja executado **como Administrador**.

---

## Frontend (Flutter)

### Instalação

```bash
cd frontend
flutter pub get
```

### Executar

```bash
flutter run -d windows
```

### Build release

```bash
flutter build windows --release
```

---

## 📡 Protocolo AION 2 Implementado

O parser foi implementado baseado em projetos open-source existentes:

- [nousx/aion2-dps-meter](https://github.com/nousx/aion2-dps-meter) (Kotlin)
- [Kuroukihime/AIon2-Dps-Meter](https://github.com/Kuroukihime/AIon2-Dps-Meter) (C#)

### ✨ Características

✅ **Auto-detecção de porta** via magic bytes  
✅ **Parser VarInt** (Protocol Buffers)  
✅ **Opcodes confirmados:** Dano direto (0x04 0x38), DoT (0x05 0x38)  
✅ **Special flags:** Crítico, Back Attack, Perfect, Double, Parry

### 📖 Documentação Detalhada

Veja **[AION2_PROTOCOL.md](AION2_PROTOCOL.md)** para:

- Estrutura completa de pacotes
- Tabela de opcodes
- Guia de testes com jogo real
- Troubleshooting

---

## Configuração do Parser (OPCIONAL)

O parser já está configurado com protocolo real do AION 2 TW.

Para debug ou ajustes finos, ative logs em `packet_parser.py`:

```python
# No método _parse_damage_packet, adicione:
logger.info(f"Skill: {skill_id}, Damage: {damage}, Crit: {is_crit}")
```

---

## Estrutura de arquivos

```
aion2_dpsmeter/
├── backend/
│   ├── main.py          # Entry point + WebSocket server (ws://localhost:8765)
│   ├── capture.py       # Captura com Npcap via Scapy / MockCapture
│   ├── parser.py        # Parse dos pacotes → CombatEvent
│   ├── calculator.py    # DPS/HPS com janela deslizante de 10s
│   └── requirements.txt
└── frontend/
    ├── pubspec.yaml
    └── lib/
        ├── main.dart        # App Flutter + janela overlay
        ├── ws_service.dart  # WebSocket client com auto-reconexão
        ├── models.dart      # PlayerStats, DpsSnapshot, DpsPoint
        ├── dps_chart.dart   # Gráfico de linha em tempo real (fl_chart)
        └── party_table.dart # Tabela de ranking com barra de progresso
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

O projeto inclui um script PowerShell que automatiza todo o processo:

```powershell
# No diretório raiz do projeto
.\build_release.ps1
```

Este script irá:

1. ✅ Verificar o ambiente Python (virtual environment)
2. ✅ Instalar PyInstaller se necessário
3. ✅ Compilar o backend Python em executável standalone
4. ✅ Copiar o backend para `frontend/assets/backend/`
5. ✅ Compilar o Flutter em modo release
6. ✅ Criar pacote de distribuição em `dist/`

### Build Manual

Se preferir executar manualmente:

#### 1. Compilar backend com PyInstaller

```powershell
cd backend
python -m PyInstaller main.py `
  --name=aion2_backend `
  --onefile `
  --console `
  --add-data "packet_parser.py;." `
  --add-data "calculator.py;." `
  --add-data "capture.py;." `
  --hidden-import scapy.all `
  --hidden-import websockets
```

Resultado: `backend/dist/aion2_backend.exe`

#### 2. Copiar backend para assets do Flutter

```powershell
Copy-Item backend\dist\aion2_backend.exe frontend\assets\backend\
```

#### 3. Compilar Flutter

```powershell
cd frontend
flutter build windows --release
```

Resultado: `frontend/build/windows/x64/runner/Release/`

### Distribuição

O pacote final estará em `dist/` e contém:

- `frontend.exe` - Aplicação principal Flutter
- `aion2_backend.exe` - Backend Python (embutido nos assets)
- DLLs e dependências do Flutter
- Pasta `data/` com assets compilados

**Requisitos no sistema de destino:**

- ⚠️ Windows 10/11 (64-bit)
- ⚠️ Npcap instalado: https://npcap.com/#download
- ⚠️ Privilégios de Administrador (para captura de pacotes)

**Para distribuir:**
Copie toda a pasta `dist/` para o computador de destino. O backend Python está empacotado dentro do executável Flutter e será iniciado automaticamente.

### Modo de Desenvolvimento vs Release

- **Desenvolvimento**: Backend e frontend executados separadamente
  - Backend: `python main.py --mock`
  - Frontend: `flutter run -d windows`
- **Release**: Executável único que inicia backend automaticamente
  - Execute: `frontend.exe` (na pasta `dist/`)
  - Backend é extraído e iniciado nos bastidores

---

## Troubleshooting

### "Backend executável não encontrado"

Certifique-se de que o backend foi compilado e copiado:

```powershell
# Verificar se existe
Test-Path frontend\assets\backend\aion2_backend.exe
```

### "Erro ao iniciar backend"

Execute manualmente para ver logs de erro:

```powershell
.\dist\aion2_backend.exe --mock
```

### Build do PyInstaller falha

Reinstale as dependências no venv:

```powershell
.venv\Scripts\Activate.ps1
pip install --force-reinstall -r backend\requirements.txt
```

---
