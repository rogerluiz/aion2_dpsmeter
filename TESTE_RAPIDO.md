# TESTE_RAPIDO.md

## Guia de Teste Rápido — AION 2 DPS Meter

### ✅ Checklist de Verificação

#### 1. Ambiente Configurado

```powershell
# Verificar Python
.\.venv\Scripts\python.exe --version
# Deve retornar: Python 3.13.x

# Verificar Flutter
flutter doctor
# Deve mostrar: Windows Desktop ✓
```

#### 2. Testar Backend Standalone (Modo Mock)

```powershell
# Executar backend Python diretamente
& "a:\Projects\aion2_dspmeter\backend\dist\aion2_backend.exe" --mock
```

**Saída esperada:**

```
08:51:04 [INFO] capture: MockCapture iniciado — gerando dados simulados.
08:51:04 [INFO] aion2_dpsmeter: Captura iniciada.
08:51:04 [INFO] aion2_dpsmeter: Servidor WebSocket em ws://localhost:8765
08:51:04 [INFO] aion2_dpsmeter: Aguardando conexão do Flutter...
```

**Pressione Ctrl+C para parar**

#### 3. Testar Frontend Standalone

Em outro terminal:

```powershell
cd frontend
flutter run -d windows
```

**Comportamento esperado:**

- Janela overlay transparente abre
- Gráfico de DPS atualiza em tempo real
- Tabela mostra jogadores simulados (Gladiator, Ranger, Cleric)
- Valores de DPS mudam a cada segundo

**Pressione 'q' no terminal ou feche a janela para parar**

#### 4. Testar Build Release Completo

```powershell
# No diretório raiz do projeto
.\build_release.ps1
```

**Saída esperada:**

```
🚀 AION 2 DPS Meter - Build Release
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[1/6] Verificando ambiente Python...
✅ Python encontrado

[2/6] Verificando PyInstaller...
✅ PyInstaller pronto

[3/6] Compilando backend Python...
✅ Backend compilado: aion2_backend.exe (13.6 MB)

[4/6] Copiando backend para assets...
✅ Backend copiado para: frontend/assets/backend/

[5/6] Compilando Flutter para Windows...
✅ Flutter compilado com sucesso

[6/6] Criando pacote de distribuição...
✅ Pacote criado em: dist/

✨ Build concluído com sucesso!

📦 Executável: frontend.exe
📂 Localização: dist/
```

#### 5. Testar Executável Final

```powershell
# Navegar para a pasta de distribuição
cd dist

# Executar aplicação final
.\frontend.exe
```

**Comportamento esperado:**

- Aplicação inicia automaticamente (pode levar 2-3 segundos)
- Backend Python é iniciado nos bastidores
- Overlay DPS aparece com dados simulados
- Tudo funciona sem precisar executar backend manualmente

---

### 🐛 Troubleshooting

#### "Port 8765 already in use"

Outro processo está usando a porta. Mate todos os processos:

```powershell
# Encontrar processo na porta 8765
Get-NetTCPConnection -LocalPort 8765 | Select-Object OwningProcess

# Matar processo (substitua <PID>)
Stop-Process -Id <PID> -Force
```

Ou simplesmente reinicie o computador.

#### "Backend executável não encontrado"

Execute o build novamente:

```powershell
.\build_release.ps1
```

Verifique se existe:

```powershell
Test-Path frontend\assets\backend\aion2_backend.exe
```

#### "Npcap error" ou "No interfaces found"

Instale o Npcap:

- Download: https://npcap.com/#download
- Marque opção: "Install Npcap in WinPcap API-compatible Mode"
- Reinicie após instalação

#### Flutter não compila

```powershell
cd frontend

# Limpar cache
flutter clean

# Reinstalar dependências
flutter pub get

# Tentar novamente
flutter build windows --release
```

---

### 📊 Status Final

✅ Backend Python compilado (PyInstaller)  
✅ Frontend Flutter configurado  
✅ Integração automática via BackendService  
✅ Build script completo  
✅ Protocolo AION 2 implementado  
✅ Auto-detecção de porta  
✅ VarInt parser  
✅ Damage packets (0x04 0x38, 0x05 0x38)  
✅ Special flags (crítico, back attack, etc)

### 🎮 Próximos Passos

Para testar com o jogo AION 2 real:

1. **Execute como Administrador** (necessário para captura de pacotes)
2. Modifique [main.dart](frontend/lib/main.dart#L27):
   ```dart
   await backendService.start(useMock: false); // Mude para false
   ```
3. Inicie o jogo AION 2 TW
4. Entre em combate
5. O DPS Meter capturará pacotes reais

Veja [AION2_PROTOCOL.md](AION2_PROTOCOL.md) para troubleshooting de captura real.
