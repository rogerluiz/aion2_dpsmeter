"""
Cliente WebSocket de teste para verificar dados enriquecidos.
"""
import asyncio
import websockets
import json


async def test_client():
    uri = "ws://localhost:8765"
    print(f"Conectando em {uri}...")

    async with websockets.connect(uri) as websocket:
        print("✅ Conectado ao WebSocket\n")

        # Receber primeiros 5 pacotes
        for i in range(5):
            message = await websocket.recv()
            data = json.loads(message)

            print(f"\n═══ Pacote {i+1} ═══")

            if 'data' in data and 'session_duration' in data['data']:
                snapshot_data = data['data']
                print(
                    f"Session Duration: {snapshot_data.get('session_duration', 0):.1f}s")
                print(
                    f"Total Damage: {snapshot_data.get('total_damage', 0):,}")
                print(f"Players: {len(snapshot_data.get('players', []))}")

                for player in snapshot_data.get('players', []):
                    print(f"\n👤 Player {player.get('id', '?')}:")
                    print(f"  Nome: {player.get('name', 'Unknown')}")
                    print(
                        f"  Classe: {player.get('class_name', 'N/A')} ({player.get('class_icon', 'N/A')})")
                    print(f"  DPS: {player.get('current_dps', 0):.0f}")
                    print(f"  Total: {player.get('total_damage', 0):,}")

                    # Mostrar top 3 skills
                    skills = player.get('skills', [])
                    if skills:
                        print(f"  🔥 Top Skills:")
                        for j, skill in enumerate(skills[:3], 1):
                            skill_name = skill.get('skill_name', 'Unknown')
                            skill_icon = skill.get('skill_icon', 'N/A')
                            damage = skill.get('total_damage', 0)
                            hits = skill.get('hit_count', 0)
                            crits = skill.get('crit_count', 0)
                            crit_rate = (crits / hits * 100) if hits > 0 else 0

                            print(f"    {j}. {skill_name} ({skill_icon})")
                            print(
                                f"       Dano: {damage:,} | Hits: {hits} | Crit: {crit_rate:.1f}%")
            else:
                print("⚠️  Pacote sem dados esperados")

        print("\n\n✅ Teste completo!")


if __name__ == "__main__":
    try:
        asyncio.run(test_client())
    except KeyboardInterrupt:
        print("\n\nTeste interrompido pelo usuário")
    except Exception as e:
        print(f"\n❌ Erro: {e}")
