# 📡 Protocolo AION 2 TW - Implementação Baseada em Projetos Existentes

## 🎯 Fontes de Referência

Baseado em análise de três projetos open-source:

- [nousx/aion2-dps-meter](https://github.com/nousx/aion2-dps-meter) (Kotlin - 391 skills)
- [Kuroukihime/AIon2-Dps-Meter](https://github.com/Kuroukihime/AIon2-Dps-Meter) (C#)
- [TK-open-public/Aion2-Dps-Meter](https://github.com/tk-open-public/aion2-dps-meter) (TypeScript/Kotlin)

---

## 📋 Protocolo Implementado

### Estrutura de Pacotes

```
┌──────────┬──────────┬───────────────────────────┐
│  VarInt  │  Opcode  │  Payload (variable)       │
│  Length  │  (2 bytes)│                           │
└──────────┴──────────┴───────────────────────────┘
     │           │              │
     │           │              └─> Parsed por packet_parser.py
     │           └─> Identificação do tipo de pacote
     └─> Tamanho do pacote (Protocol Buffers VarInt)
```

### Opcodes Conhecidos

| Opcode      | Tipo       | Descrição        | Implementado |
| ----------- | ---------- | ---------------- | ------------ |
| `0x04 0x38` | Damage     | Dano direto      | ✅ Sim       |
| `0x05 0x38` | DoT        | Damage over Time | ✅ Sim       |
| `0x04 0x8D` | Nickname   | Nome de entidade | ⏳ Futuro    |
| `0x40 0x36` | Summon     | Summon/invocação | ⏳ Futuro    |
| `0x00 0x8D` | Mob HP     | HP de mobs       | ⏳ Futuro    |
| `0x03 0x36` | Ping       | Timestamp        | ⏳ Futuro    |
| `0xFF 0xFF` | Compressed | Stream LZ4       | ⏳ Futuro    |

---

## 🔍 Estrutura de Pacote de Dano (0x04 0x38)

```python
[VarInt: Length]           # Tamanho do pacote
[0x04 0x38]                # Opcode de dano
[VarInt: Target ID]        # ID da entidade que recebeu dano
[VarInt: Switch Value]     # Controle de flags (bits 0-3)
[VarInt: Flag Field]       # Campo de flags (skip)
[VarInt: Actor ID]         # ID do atacante
[UInt32LE: Skill Code]     # Código da skill (little-endian)
[1 byte: Unknown]          # Byte desconhecido
[VarInt: Damage Type]      # Tipo (3 = crítico, outros = normal)
[N bytes: Special Flags]   # Flags especiais (tamanho depende de Switch)
[VarInt: Unknown]          # Campo desconhecido
[VarInt: Damage Value]     # Valor do dano
```

### Switch Value & Special Flags Block

| Switch (& 0x0F) | Tamanho do Bloco | Descrição            |
| --------------- | ---------------- | -------------------- |
| 4               | 8 bytes          | Sem flags especiais  |
| 5               | 12 bytes         | Com 2 bytes de flags |
| 6               | 10 bytes         | Com 2 bytes de flags |
| 7               | 14 bytes         | Com 2 bytes de flags |

### Special Flags (Byte 1 quando disponível)

```python
FLAG_BACK_ATTACK  = 0x01  # Ataque pelas costas
FLAG_UNKNOWN1     = 0x02  # Desconhecido
FLAG_PARRY        = 0x04  # Aparado
FLAG_PERFECT      = 0x08  # Perfeito
FLAG_DOUBLE       = 0x10  # Dano duplo
FLAG_ENDURE       = 0x20  # Endure
FLAG_UNKNOWN2     = 0x40  # Desconhecido
FLAG_POWER_SHARD  = 0x80  # Power Shard
```

---

## 🔍 Estrutura de Pacote DoT (0x05 0x38)

```python
[VarInt: Length]           # Tamanho do pacote
[0x05 0x38]                # Opcode de DoT
[VarInt: Target ID]        # ID da entidade
[1 byte: Effect Type]      # Tipo de efeito (deve ter bit 0x02)
[VarInt: Actor ID]         # ID do atacante
[VarInt: Unknown]          # Campo desconhecido
[UInt32LE: Skill Code]     # Código da skill (little-endian)
[VarInt: Damage Value]     # Valor do dano
```

---

## 🚀 Como Testar

### 1. Instalar Npcap

```powershell
# Baixar de: https://npcap.com/#download
# ⚠️ Marcar opção "WinPcap API-compatible Mode"
```

### 2. Rodar Servidor (Como Administrador)

```powershell
# Modo REAL (captura de rede - requer admin)
& a:\Projects\aion2_dspmeter\.venv\Scripts\python.exe a:\Projects\aion2_dspmeter\backend\main.py

# Modo MOCK (desenvolvimento)
& a:\Projects\aion2_dspmeter\.venv\Scripts\python.exe a:\Projects\aion2_dspmeter\backend\main.py --mock
```

### 3. Auto-Detecção de Porta

O sistema detecta automaticamente a porta do AION 2 ao encontrar os **magic bytes** `0x06 0x00 0x36`:

```
08:27:05 [INFO] 🔥 Porta de combate detectada: 7777
```

### 4. Logs de Debug

Para ver pacotes sendo parseados:

```python
# Em packet_parser.py, adicione no __init__:
logging.basicConfig(level=logging.DEBUG)
```

Você verá logs como:

```
[DEBUG] Opcode desconhecido: 0x12 0x34
```

---

## 📊 Arquivos Modificados

### ✅ `backend/capture.py`

- **Auto-detecção de porta** via magic bytes
- Filtro BPF dinâmico
- Detecção de direção do pacote (incoming/outgoing)

### ✅ `backend/packet_parser.py`

- **Parser VarInt** (Protocol Buffers)
- **Parser de dano direto** (0x04 0x38)
- **Parser de DoT** (0x05 0x38)
- Special flags parsing
- Skill code parsing (uint32le)

### ✅ `backend/calculator.py`

- Suporte para novos campos: `is_back_attack`, `is_perfect`, `is_double`, `is_parry`, `is_dot`

---

## 🧪 Testes Recomendados

### Teste 1: Verificar Detecção de Porta

```powershell
& a:\Projects\aion2_dspmeter\.venv\Scripts\python.exe a:\Projects\aion2_dspmeter\backend\main.py
```

1. Logar no AION 2
2. Verificar log: `🔥 Porta de combate detectada: XXXX`

### Teste 2: Capturar Dano Real

```powershell
& a:\Projects\aion2_dspmeter\.venv\Scripts\python.exe a:\Projects\aion2_dspmeter\backend\main.py
```

1. Atacar um mob no jogo
2. Verificar se o frontend mostra o dano
3. Verificar logs de pacotes desconhecidos

### Teste 3: Comparar com Mockup

```powershell
# Terminal 1: Backend mock
& a:\Projects\aion2_dspmeter\.venv\Scripts\python.exe a:\Projects\aion2_dspmeter\backend\main.py --mock

# Terminal 2: Frontend
cd a:\Projects\aion2_dspmeter\frontend
flutter run -d windows
```

---

## 🔧 Troubleshooting

### Porta não detectada

**Sintoma:** Logs não mostram detecção de porta

**Solução:**

1. Verificar se AION 2 está rodando
2. Verificar se Npcap está instalado
3. Rodar como Administrador
4. Verificar interface de rede correta

### Pacotes não sendo parseados

**Sintoma:** `Opcode desconhecido` nos logs

**Solução:**

1. Ativar logs DEBUG
2. Copiar hex do pacote
3. Comparar com estrutura esperada
4. Abrir issue com exemplo de pacote

### Valores errados de dano

**Sintoma:** Dano mostrado diferente do jogo

**Possível causa:**

- Skill code pode precisar divisão por 100
- VarInt pode estar sendo lido incorretamente
- Offset de campos pode estar errado

**Debug:**

```python
# Adicionar em _parse_damage_packet
logger.info(f"Skill: {skill_id}, Damage: {damage}, Actor: {actor_id}")
```

---

## 📝 Próximos Passos

### Prioridade Alta

- [ ] Testar captura real com AION 2 TW
- [ ] Validar valores de dano vs in-game
- [ ] Implementar compressão LZ4 (pacotes 0xFF 0xFF)
- [ ] Implementar parser de nomes (0x04 0x8D)

### Prioridade Média

- [ ] Implementar parser de summons (0x40 0x36)
- [ ] Implementar parser de mob HP (0x00 0x8D)
- [ ] Adicionar suporte a skills de cura
- [ ] Mapear skill codes → nomes

### Prioridade Baixa

- [ ] Interface para selecionar interface de rede
- [ ] Gravação de pacotes para análise offline
- [ ] Estatísticas de performance do parser

---

## � CI/CD e Automação

### GitHub Actions Workflows

#### 1. **CI - Build and Test** ([`.github/workflows/ci.yml`](.github/workflows/ci.yml))

**Trigger:** Push/PR para `main` ou `develop`

**Jobs:**

- **test-backend**: Valida imports e dependências Python
- **test-build-backend**: Compila backend com PyInstaller (validação)
- **test-flutter**: `flutter analyze` + `flutter test` + build Windows

**Objetivo:** Garantir qualidade do código antes de merge.

#### 2. **Build and Release** ([`.github/workflows/release.yml`](.github/workflows/release.yml))

**Trigger:** Push de tag `v*.*.*` (ex: `v1.0.0`)

**Pipeline:**

```
1. Setup Python 3.13 + dependencies
   ↓
2. Build backend com PyInstaller (backend.exe)
   ↓
3. Setup Flutter 3.9.2
   ↓
4. Build Flutter Windows (release mode)
   ↓
5. Criar pacote ZIP de distribuição
   ↓
6. Gerar changelog automático (git commits)
   ↓
7. Criar GitHub Release + upload de artefatos
```

**Artefato gerado:**

```
aion2_dpsmeter-v1.0.0-windows-x64.zip
├── aion2_dpsmeter.exe (Flutter app)
├── flutter_windows.dll
├── data/flutter_assets/assets/backend/backend.exe
└── README.txt (instruções de instalação)
```

**Tamanho:** ~40-50 MB comprimido

### Como Criar uma Release

```bash
# 1. Commit das mudanças
git add .
git commit -m "feat: nova funcionalidade X"

# 2. Criar tag de versão
git tag -a v1.0.0 -m "Release 1.0.0 - Initial public release"

# 3. Push da tag (dispara workflow automaticamente)
git push origin v1.0.0

# GitHub Actions irá:
# - Compilar tudo
# - Criar a release
# - Anexar os binários
```

### Versionamento

Usamos **Semantic Versioning** (`MAJOR.MINOR.PATCH`):

- **MAJOR**: Mudanças incompatíveis na API (ex: v2.0.0)
- **MINOR**: Novas funcionalidades compatíveis (ex: v1.1.0)
- **PATCH**: Bug fixes (ex: v1.0.1)

**Exemplos:**

- `v1.0.0` - Release inicial
- `v1.1.0` - Adicionado suporte a opcodes 0x04 0x8D
- `v1.1.1` - Corrigido bug de parsing de VarInt
- `v2.0.0` - Mudança no formato WebSocket (breaking change)

---

## �🙏 Créditos

Baseado no trabalho de:

- **nousx** - [aion2-dps-meter](https://github.com/nousx/aion2-dps-meter) (Kotlin)
- **Kuroukihime** - [AIon2-Dps-Meter](https://github.com/Kuroukihime/AIon2-Dps-Meter) (C#)
- **TK-open-public** - [Aion2-Dps-Meter](https://github.com/tk-open-public/aion2-dps-meter) (TypeScript/Kotlin)

Implementação adaptada para Python + Flutter com melhorias:

- Auto-detecção de porta
- Parser modular
- Interface Flutter moderna
- Suporte Windows nativo
