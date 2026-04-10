# Roadmap - Features Avançadas (baseado em A2Tools DPS Meter)

## 🎯 Objetivo

Implementar funcionalidades avançadas do A2Tools DPS Meter:

- ✅ Skill details com ícones
- ✅ Nomes de membros da party
- ✅ Job/Class detection automático
- ✅ Agregação de skills com estatísticas detalhadas

---

## 📋 Fase 1: Skill Lookup System

### Backend (Python)

**1.1 Criar banco de dados de skills**

```
backend/data/skills.json
{
  "10001234": {
    "name": "Power Strike",
    "icon": "skill_power_strike.png",
    "class": "Gladiator",
    "description": "Powerful attack"
  },
  ...
}
```

**1.2 Implementar SkillLookup**

```python
# backend/skill_lookup.py
class SkillLookup:
    def __init__(self, data_file="data/skills.json"):
        self.skills = self._load_skills(data_file)

    def get_skill_info(self, skill_code: int) -> dict:
        # Retorna {name, icon, class}

    def normalize_skill_code(self, raw_code: int) -> int:
        # Remove variações (ex: 10001234 → 10001230)
```

**1.3 Atualizar CombatEvent**

```python
@dataclass
class CombatEvent:
    # ... campos existentes ...
    skill_name: str = ""
    skill_icon: str = ""
    player_class: str = "Unknown"
```

### Frontend (Flutter)

**1.4 Criar widget de skill icon**

```dart
// lib/widgets/skill_icon.dart
class SkillIcon extends StatelessWidget {
  final String iconPath;
  final int count;
  // Mostra ícone da skill com badge de contagem
}
```

**1.5 Skill details panel**

```dart
// lib/widgets/skill_details_panel.dart
// Painel expansível que mostra:
// - Lista de skills usadas
// - Dano total/min/max
// - Crit/back/parry rates
// - Ícones das skills
```

---

## 📋 Fase 2: Nickname Parsing Robusto

### Backend (Python)

**2.1 Implementar parsing de múltiplos opcodes**

Adicionar ao `packet_parser.py`:

```python
# Opcode 0x04 0x4C - Nickname packet (PRIORITY!)
OPCODE_NICKNAME = (0x04, 0x4C)

# Opcode 0x44 0x36 - Player spawn
OPCODE_PLAYER_SPAWN = (0x44, 0x36)

def _parse_nickname_packet(self, payload, offset):
    """
    Parsing de pacote 0x04 0x4C
    Estrutura: <varint_id> ... 0x06 0x00 0x36 <name_len> <name_bytes>
    """

def _parse_player_spawn_packet(self, payload, offset):
    """
    Parsing de pacote 0x44 0x36
    Estrutura: <actor_varint> ... 0x07 <name_len> <name_bytes>
    """
```

**2.2 Nickname storage com cache**

```python
# backend/nickname_cache.py
class NicknameCache:
    def __init__(self):
        self.nicknames: Dict[int, str] = {}
        self.pending: Dict[int, str] = {}
        self.permanent: Dict[int, str] = {}  # Local player

    def set_nickname(self, actor_id: int, name: str):
        # Valida e armazena nickname

    def get_nickname(self, actor_id: int) -> Optional[str]:
        # Retorna nickname se conhecido
```

**2.3 Integrar ao main.py**

```python
nickname_cache = NicknameCache()

# No loop de captura:
event = parser.parse(payload)
if event and event.attacker_id not in nickname_cache:
    nickname_cache.try_extract_from_packet(payload)
```

---

## 📋 Fase 3: Job/Class Detection

### Backend (Python)

**3.1 Criar mapeamento skill → class**

```python
# backend/job_detector.py
class JobDetector:
    # Skills exclusivas de cada classe
    GLADIATOR_SKILLS = [10001000, 10001010, ...]
    RANGER_SKILLS = [11001000, 11001010, ...]
    CLERIC_SKILLS = [12001000, ...]

    @staticmethod
    def detect_from_skill(skill_code: int) -> Optional[str]:
        """Retorna nome da classe baseado na skill"""

    @staticmethod
    def get_class_icon(class_name: str) -> str:
        """Retorna path do ícone da classe"""
```

**3.2 Atualizar PlayerStats**

```python
@dataclass
class PlayerStats:
    # ... campos existentes ...
    class_name: str = "Unknown"
    class_icon: str = ""

    def update_class_from_skill(self, skill_code: int):
        detected = JobDetector.detect_from_skill(skill_code)
        if detected and self.class_name == "Unknown":
            self.class_name = detected
            self.class_icon = JobDetector.get_class_icon(detected)
```

### Frontend (Flutter)

**3.3 UI para mostrar classes**

```dart
// Adicionar ao party_table.dart:
// - Ícone da classe ao lado do nome
// - Cor de fundo baseada na classe
// - Tooltip com nome completo da classe
```

---

## 📋 Fase 4: Agregação de Skills

### Backend (Python)

**4.1 Estrutura de dados agregada**

```python
@dataclass
class SkillStats:
    skill_code: int
    skill_name: str
    skill_icon: str
    total_damage: int = 0
    hit_count: int = 0
    crit_count: int = 0
    back_count: int = 0
    parry_count: int = 0
    perfect_count: int = 0
    double_count: int = 0
    min_damage: int = 999999
    max_damage: int = 0
    is_dot: bool = False

    @property
    def avg_damage(self) -> float:
        return self.total_damage / self.hit_count if self.hit_count > 0 else 0

    @property
    def crit_rate(self) -> float:
        return (self.crit_count / self.hit_count * 100) if self.hit_count > 0 else 0
```

**4.2 Atualizar PlayerStats**

```python
@dataclass
class PlayerStats:
    # ... campos existentes ...
    skills: Dict[int, SkillStats] = field(default_factory=dict)

    def process_event(self, event: CombatEvent):
        # Atualiza estatísticas gerais
        # ...

        # Atualiza estatísticas da skill
        if event.skill_id not in self.skills:
            self.skills[event.skill_id] = SkillStats(
                skill_code=event.skill_id,
                skill_name=event.skill_name,
                skill_icon=event.skill_icon
            )

        skill = self.skills[event.skill_id]
        skill.total_damage += event.value
        skill.hit_count += 1
        skill.min_damage = min(skill.min_damage, event.value)
        skill.max_damage = max(skill.max_damage, event.value)
        if event.is_crit: skill.crit_count += 1
        if event.is_back_attack: skill.back_count += 1
        # ... etc
```

**4.3 Atualizar WebSocket snapshot**

```json
{
  "type": "snapshot",
  "data": {
    "players": [
      {
        "id": 1,
        "name": "Player1",
        "class": "Gladiator",
        "class_icon": "gladiator.png",
        "total_damage": 123456,
        "skills": [
          {
            "code": 10001234,
            "name": "Power Strike",
            "icon": "skill_power_strike.png",
            "total_damage": 50000,
            "hits": 42,
            "crits": 8,
            "crit_rate": 19.0,
            "avg_damage": 1190,
            "min_damage": 800,
            "max_damage": 2400
          }
        ]
      }
    ]
  }
}
```

### Frontend (Flutter)

**4.4 Skill details view**

```dart
// lib/views/skill_details_view.dart
class SkillDetailsView extends StatelessWidget {
  final PlayerStats player;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(player.name),
      children: player.skills.map((skill) => SkillRow(skill)).toList(),
    );
  }
}

class SkillRow extends StatelessWidget {
  final SkillStats skill;
  // Mostra: [Ícone] Nome | Hits | Dano Total | Crit% | Avg | Min-Max
}
```

---

## 📋 Fase 5: Ícones e Assets

### Assets necessários

**5.1 Class icons (16 classes)**

```
frontend/assets/classes/
  gladiator.png
  templar.png
  ranger.png
  assassin.png
  cleric.png
  chanter.png
  sorcerer.png
  spiritmaster.png
  (... etc)
```

**5.2 Skill icons (extrair do cliente AION 2)**

```
frontend/assets/skills/
  skill_10001234.png
  skill_11002456.png
  (... milhares de ícones)
```

**5.3 Script de download de ícones**

```python
# tools/download_icons.py
# Baixa ícones de repositórios AION 2 ou extrai do cliente
# Salva em frontend/assets/skills/
```

---

## 📋 Priorização

### Must Have (MVP 2.0)

1. ✅ Nickname parsing robusto (0x04 0x4C)
2. ✅ Skill lookup básico (top 50 skills mais comuns)
3. ✅ Job detection
4. ✅ Agregação de skills com stats básicas

### Nice to Have

- Ícones de skills (fase inicial: apenas nomes)
- Ícones de classes
- Skill details panel expansível
- Histórico de batalhas

### Future

- Multi-language support
- Theme customization
- Export de logs
- Auto-update

---

## 🚀 Implementação Incremental

### Sprint 1 (Atual)

- [ ] Criar skill_lookup.py
- [ ] Adicionar parsing de OPCODE_NICKNAME (0x04 0x4C)
- [ ] Implementar NicknameCache
- [ ] Criar job_detector.py

### Sprint 2

- [ ] Implementar SkillStats
- [ ] Atualizar WebSocket com skills agregadas
- [ ] Criar SkillDetailsView no Flutter
- [ ] UI para mostrar classes

### Sprint 3

- [ ] Baixar/extrair ícones de skills
- [ ] Adicionar assets ao projeto
- [ ] Implementar SkillIcon widget
- [ ] Polimento de UI

---

## 📚 Referências

- A2Tools DPS Meter: https://github.com/taengu/A2Tools-DPS-Meter
- stream_processor.rs: Parsing de nicknames e skills
- dps_calculator.rs: Agregação e cálculos
- data_storage.rs: Estruturas de dados

---

## ✅ Status Atual

- [x] Protocolo básico implementado
- [x] Damage/DoT packets
- [x] Mock mode funcional
- [x] Flutter UI básico
- [ ] **PRÓXIMO:** Skill lookup + nickname parsing
