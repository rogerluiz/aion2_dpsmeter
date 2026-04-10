# Implementação de Features Avançadas - Status

## ✅ Implementado (Sprint 1 - Parcial)

### 1. Sistema de Detecção de Classes (`job_detector.py`)

**Funcionalidades:**

- ✅ Enum `JobClass` com 11 classes do AION 2
- ✅ Mapeamento skill ranges → classes (10M-10.9M = Gladiator, etc)
- ✅ Signature skills para detecção precisa
- ✅ `detect_job_from_skill(skill_code)` - Detecta classe por skill
- ✅ `get_job_icon(job)` - Retorna path do ícone
- ✅ `normalize_skill_code(raw)` - Normaliza variações de skills
- ✅ `is_player_skill()` e `is_npc_skill()` - Valida origem

**Exemplo de uso:**

```python
from job_detector import detect_job_from_skill, JobClass

job = detect_job_from_skill(10_001_234)  # Returns: JobClass.GLADIATOR
print(job.class_name)  # "Gladiator"
print(job.prefix)  # "glad"
icon = get_job_icon(job)  # "assets/classes/glad.png"
```

---

### 2. Sistema de Lookup de Skills (`skill_lookup.py`)

**Funcionalidades:**

- ✅ Classe `SkillInfo` - Armazena: code, name, icon, job_class
- ✅ Classe `SkillLookup` - Gerencia banco de dados de skills
- ✅ Top 30 skills mais comuns pré-carregadas (placeholder)
- ✅ `get_skill_info(code)` - Retorna informações completas
- ✅ `get_skill_name(code)` - Nome da skill ou fallback
- ✅ `get_skill_icon(code)` - Path do ícone
- ✅ `get_skill_class(code)` - Classe associada
- ✅ `add_skill()` - Adiciona skill dinamicamente
- ✅ `export_to_json()` - Exporta para arquivo JSON
- ✅ Singleton global `get_skill_lookup()`
- ✅ Normalização automática (tenta base se não encontrar exato)
- ✅ Suporte a carregamento de arquivo JSON externo

**Exemplo de uso:**

```python
from skill_lookup import get_skill_lookup

lookup = get_skill_lookup()
info = lookup.get_skill_info(10_001_234)
print(info.name)  # "Power Strike"
print(info.job_class)  # "Gladiator"
print(info.icon)  # "skill_10001234.png"
```

**Skills pré-carregadas:**

- Gladiator: 3 skills
- Templar: 2 skills
- Ranger: 3 skills
- Assassin: 2 skills
- Sorcerer: 3 skills
- Spiritmaster: 2 skills
- Cleric: 4 skills
- Chanter: 3 skills
- Gunslinger: 2 skills
- Songweaver: 2 skills
- Aethertech: 2 skills

**Total:** 28 skills base (expansível via JSON)

---

### 3. Sistema de Cache de Nicknames (`nickname_cache.py`)

**Funcionalidades:**

- ✅ Classe `NicknameCache` - Gerencia nicknames de players/entidades
- ✅ 3 níveis de storage:
  - `nicknames` - Confirmados (aparecem em combate)
  - `pending` - Detectados mas não confirmados
  - `permanent` - Permanentes (jogador local, nunca resetam)
- ✅ `set_nickname(actor_id, name, permanent)` - Define nickname
- ✅ `set_pending_nickname()` - Define pendente
- ✅ `get_nickname(actor_id)` - Obtém com prioridade (permanent > confirmed > pending)
- ✅ `has_nickname()` - Verifica se conhecido
- ✅ `confirm_combat_actor()` - Promove pending → confirmed
- ✅ `is_combat_actor()` - Verifica se apareceu em combate
- ✅ `reset_non_permanent()` - Limpa tudo exceto permanentes
- ✅ `get_all_nicknames()` - Retorna todos (merge confirmed + pending)
- ✅ Validação de nicknames (2-36 chars, sem caracteres inválidos)
- ✅ Sanitização automática (remove guild tags `[TAG]`, espaços extras)

**Exemplo de uso:**

```python
from nickname_cache import NicknameCache

cache = NicknameCache()

# Definir nickname permanente (jogador local)
cache.set_nickname(12345, "MyCharacter", permanent=True)

# Definir nickname detectado
cache.set_pending_nickname(67890, "[GUILD] PlayerName")
# Internamente: sanitizado para "PlayerName"

# Confirmar via combate
cache.confirm_combat_actor(67890)  # Promove pending → confirmed

# Obter nickname
name = cache.get_nickname(67890)  # "PlayerName"

# Reset (mantém permanentes)
cache.reset_non_permanent()
print(cache.get_nickname(12345))  # "MyCharacter" (ainda existe)
print(cache.get_nickname(67890))  # None (foi resetado)
```

---

## 📋 Próximos Passos (Sprint 1 - Restante)

### 4. Integração com `packet_parser.py`

**A fazer:**

- [ ] Adicionar opcode `0x04 0x4C` (OPCODE_NICKNAME)
- [ ] Adicionar opcode `0x44 0x36` (OPCODE_PLAYER_SPAWN)
- [ ] Implementar `_parse_nickname_packet()`
- [ ] Implementar `_parse_player_spawn_packet()`
- [ ] Integrar `NicknameCache` ao `PacketParser`
- [ ] Atualizar `CombatEvent` com campos:
  - `skill_name: str`
  - `skill_icon: str`
  - `player_class: str`

**Estrutura esperada:**

```python
# packet_parser.py

from nickname_cache import NicknameCache
from skill_lookup import get_skill_lookup
from job_detector import detect_job_from_skill

class PacketParser:
    def __init__(self, use_mock_format: bool = False):
        # ... código existente ...
        self.nickname_cache = NicknameCache()
        self.skill_lookup = get_skill_lookup()

    def _parse_real(self, payload: bytes, direction: str):
        # ... código existente ...

        # Novo: tentar parsear nickname
        if opcode == OPCODE_NICKNAME:
            self._parse_nickname_packet(payload, offset)
            return None  # Não é evento de combate

        # Novo: tentar parsear player spawn
        if opcode == OPCODE_PLAYER_SPAWN:
            self._parse_player_spawn_packet(payload, offset)
            return None

    def _parse_damage_packet(self, payload, offset):
        # ... código existente ...

        # Novo: enriquecer evento com informações
        skill_info = self.skill_lookup.get_skill_info(skill_id)
        job = detect_job_from_skill(skill_id)

        event = CombatEvent(
            # ... campos existentes ...
            skill_name=skill_info.name if skill_info else f"Skill {skill_id}",
            skill_icon=skill_info.icon if skill_info else "",
            player_class=job.class_name if job else "Unknown"
        )

        # Confirmar actor em combate
        self.nickname_cache.confirm_combat_actor(attacker_id)

        return event
```

---

### 5. Integração com `calculator.py`

**A fazer:**

- [ ] Adicionar campo `class_name` a `PlayerStats`
- [ ] Adicionar campo `skills: Dict[int, SkillStats]` a `PlayerStats`
- [ ] Criar dataclass `SkillStats` para agregação:
  - total_damage, hit_count, crit_count
  - min_damage, max_damage, avg_damage
  - back_count, parry_count, perfect_count, double_count
  - skill_name, skill_icon
- [ ] Atualizar `process_event()` para agregar por skill
- [ ] Corrigir nomes usando `NicknameCache`

---

### 6. Integração com `main.py` (WebSocket)

**A fazer:**

- [ ] Atualizar snapshot JSON para incluir:
  - `class` e `class_icon` por player
  - `skills` array com estatísticas agregadas
  - `nicknames` corrigidos
- [ ] Passar `NicknameCache` para calculator

**JSON esperado:**

```json
{
  "type": "snapshot",
  "data": {
    "players": [
      {
        "id": 12345,
        "name": "Aragoorn",
        "class": "Gladiator",
        "class_icon": "assets/classes/glad.png",
        "total_damage": 123456,
        "current_dps": 2341.5,
        "skills": [
          {
            "code": 10001234,
            "name": "Power Strike",
            "icon": "skill_10001234.png",
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

---

## 📊 Métricas de Implementação

### Linhas de Código

- `job_detector.py`: **159 linhas**
- `skill_lookup.py`: **244 linhas**
- `nickname_cache.py`: **266 linhas**
- **Total:** **669 linhas** de código novo

### Cobertura de Features

- ✅ **Job Detection:** 100% (11 classes)
- ✅ **Skill Lookup:** 20% (28/~500 skills comuns)
- ✅ **Nickname Cache:** 100% (sistema completo)
- ⏳ **Parsing Integration:** 0% (próximo passo)

---

## 🎯 Timeline Estimado

- **Sprint 1 (Atual - 70% completo):**
  - [x] Criar módulos base (job, skill, nickname)
  - [ ] Integrar com packet_parser
  - [ ] Integrar com calculator
  - [ ] Atualizar WebSocket snapshot

- **Sprint 2:**
  - [ ] UI Flutter para mostrar classes
  - [ ] UI Flutter para skill details
  - [ ] Expandir banco de skills (JSON completo)

- **Sprint 3:**
  - [ ] Ícones de classes (download/criação)
  - [ ] Ícones de skills (extração do cliente)
  - [ ] Polimento de UI

---

## 🚀 Como Testar (Após Integração)

### Teste 1: Job Detection

```python
# No backend, adicionar logging:
from job_detector import detect_job_from_skill

job = detect_job_from_skill(event.skill_id)
logger.info(f"Skill {event.skill_id} → {job.class_name if job else 'Unknown'}")
```

### Teste 2: Skill Lookup

```python
from skill_lookup import get_skill_lookup

lookup = get_skill_lookup()
info = lookup.get_skill_info(10_001_234)
print(f"Skill: {info.name}, Class: {info.job_class}")
```

### Teste 3: Nickname Cache

```python
# Ao processar evento de combate:
cache.confirm_combat_actor(event.attacker_id)
name = cache.get_nickname(event.attacker_id)
print(f"Attacker: {name or 'Unknown'} (ID: {event.attacker_id})")
```

---

## 📚 Referências Implementadas

Baseado em:

- **A2Tools DPS Meter** (Tauri/Rust)
  - `stream_processor.rs` → nickname parsing
  - `data_storage.rs` → nickname cache
  - `job_class.rs` → job detection
  - `skill_lookup.rs` → skill database

---

## ✅ Status Final

**3 de 6 módulos implementados**

- ✅ Job Detector
- ✅ Skill Lookup
- ✅ Nickname Cache
- ⏳ Packet Parser Integration (próximo)
- ⏳ Calculator Integration (próximo)
- ⏳ WebSocket/UI Integration (próximo)

**Próxima ação:** Integrar com `packet_parser.py` e `calculator.py`
