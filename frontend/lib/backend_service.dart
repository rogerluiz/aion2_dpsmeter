import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Serviço para gerenciar o processo do backend Python empacotado
class BackendService {
  Process? _backendProcess;
  bool _isRunning = false;
  
  /// Verifica se o backend está rodando
  bool get isRunning => _isRunning;
  
  /// Inicia o backend automaticamente
  Future<bool> start({bool useMock = false}) async {
    if (_isRunning) {
      debugPrint('⚠️ Backend já está rodando');
      return true;
    }
    
    try {
      // Localiza o executável do backend
      final backendExe = await _locateBackendExecutable();
      
      if (backendExe == null) {
        debugPrint('❌ Backend executável não encontrado');
        return false;
      }
      
      debugPrint('🚀 Iniciando backend: $backendExe');
      
      // Argumentos do backend
      final List<String> args = useMock ? ['--mock'] : [];
      
      // Inicia processo do backend
      _backendProcess = await Process.start(
        backendExe,
        args,
        mode: ProcessStartMode.detached,
      );
      
      _isRunning = true;
      
      // Aguarda um pouco para o backend iniciar
      await Future.delayed(const Duration(seconds: 2));
      
      debugPrint('✅ Backend iniciado com sucesso');
      return true;
      
    } catch (e) {
      debugPrint('❌ Erro ao iniciar backend: $e');
      return false;
    }
  }
  
  /// Para o backend
  Future<void> stop() async {
    if (_backendProcess != null) {
      debugPrint('🛑 Parando backend...');
      _backendProcess!.kill();
      _backendProcess = null;
      _isRunning = false;
      debugPrint('✅ Backend parado');
    }
  }
  
  /// Localiza o executável do backend
  Future<String?> _locateBackendExecutable() async {
    // Em desenvolvimento: procura na pasta backend/dist
    if (!kReleaseMode) {
      final devPath = path.join(
        Directory.current.parent.path,
        'backend',
        'dist',
        'aion2_backend.exe',
      );
      
      if (await File(devPath).exists()) {
        return devPath;
      }
    }
    
    // Em release: procura junto ao executável do Flutter
    final exeDir = path.dirname(Platform.resolvedExecutable);
    
    // Opção 1: Na pasta data/flutter_assets/assets/backend (onde Flutter coloca os assets)
    final assetsPath = path.join(exeDir, 'data', 'flutter_assets', 'assets', 'backend', 'aion2_backend.exe');
    if (await File(assetsPath).exists()) {
      return assetsPath;
    }
    
    // Opção 2: Dentro de pasta 'backend' ao lado do executável
    final bundledPath1 = path.join(exeDir, 'backend', 'aion2_backend.exe');
    if (await File(bundledPath1).exists()) {
      return bundledPath1;
    }
    
    // Opção 3: No mesmo diretório do executável
    final bundledPath2 = path.join(exeDir, 'aion2_backend.exe');
    if (await File(bundledPath2).exists()) {
      return bundledPath2;
    }
    
    return null;
  }
  
  /// Verifica se o backend está acessível via WebSocket
  Future<bool> checkConnection() async {
    try {
      final socket = await WebSocket.connect('ws://localhost:8765');
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }
}
