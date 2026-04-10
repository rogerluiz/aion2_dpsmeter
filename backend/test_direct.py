"""
Teste direto do fluxo de processamento (atualizado).
"""
import time
from packet_parser import PacketParser
from calculator import DPSCalculator
import struct

# Criar parser e calculator
parser = PacketParser(use_mock_format=True)
calculator = DPSCalculator()

print("📊 Teste Direto do Fluxo de Processamento\n")

# Gerar alguns pacotes mock
skill_ids = [10_001_234, 10_002_456, 12_001_500]
packets_generated = 0

for i in range(10):
    # Gerar pacote mock
    opcode = 0x0301
    attacker = 0x01
    target = 0xA1
    skill = skill_ids[i % len(skill_ids)]
    damage = 1000 + (i * 100)
    is_crit = i % 3 == 0

    payload = struct.pack(">HBBIIB", opcode, attacker,
                          target, skill, damage, int(is_crit))

    # Parsear
    event = parser.parse(payload, "incoming")
    if event:
        print(f"✅ Evento {i+1}: attacker={event.attacker_id}, skill={event.skill_id} ({event.skill_name}), damage={event.value}, crit={event.is_crit}")
        print(
            f"   Classe: {event.attacker_class} ({event.attacker_class_icon})")
        calculator.process_event(event)
        packets_generated += 1
    else:
        print(f"❌ Evento {i+1}: Falha no parse")

print(f"\n📦 Pacotes gerados: {packets_generated}")

# Executar tick
calculator.tick()

# Verificar snapshot
snapshot = calculator.get_snapshot()
print(f"\n📸 Snapshot:")
print(f"   Session Duration: {snapshot.get('session_duration', 0):.1f}s")
print(f"   Total Damage: {snapshot.get('total_damage', 0):,}")
print(f"   Players: {len(snapshot.get('players', []))}")

for player in snapshot.get('players', []):
    print(f"\n   👤 Player {player['id']}:")
    print(f"      Nome: {player.get('name', 'Unknown')}")
    print(f"      Classe: {player.get('class_name', 'N/A')}")
    print(f"      Classe Icon: {player.get('class_icon', 'N/A')}")
    print(f"      DPS: {player.get('current_dps', 0):.0f}")
    print(f"      Total: {player.get('total_damage', 0):,}")
    print(f"      Skills: {len(player.get('skills', []))}")

    for j, skill in enumerate(player.get('skills', [])[:3], 1):
        print(f"         {j}. Skill Code: {skill['skill_code']}")
        print(f"            Nome: {skill['skill_name']}")
        print(f"            Ícone: {skill['skill_icon']}")
        print(f"            Dano: {skill['total_damage']:,}")
        print(f"            Hits: {skill['hit_count']}")
        print(f"            Crits: {skill['crit_count']}")

print("\n✅ Teste concluído!")
