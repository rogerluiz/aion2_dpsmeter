import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Serviço para gerenciar o processo do servidor Node.js empacotado
class BackendService {
  Process? _backendProcess;
  bool _isRunning = false;

  static const String _exeName = 'aion2_server.exe';

  /// Verifica se o backend está rodando
  bool get isRunning => _isRunning;

  /// Inicia o servidor Node.js automaticamente
  Future<bool> start({bool useMock = false}) async {
    if (_isRunning) {
      debugPrint('Backend já está rodando');
      return true;
    }

    try {
      final serverExe = await _locateBackendExecutable();

      if (serverExe == null) {
        debugPrint('Servidor executável não encontrado ($_exeName)');
        return false;
      }

      debugPrint('Iniciando servidor: $serverExe');

      final List<String> args = useMock ? <String>['--mock'] : <String>[];

      _backendProcess = await Process.start(
        serverExe,
        args,
        mode: ProcessStartMode.detached,
      );

      _isRunning = true;

      // Aguarda o servidor abrir o WebSocket
      await Future.delayed(const Duration(seconds: 2));

      debugPrint('Servidor iniciado com sucesso (PID: ${_backendProcess!.pid})');
      return true;
    } catch (e) {
      debugPrint('Erro ao iniciar servidor: $e');
      return false;
    }
  }

  /// Para o servidor
  Future<void> stop() async {
    if (_backendProcess != null) {
      _backendProcess!.kill();
      _backendProcess = null;
      _isRunning = false;
    }
  }

  /// Localiza o executável do servidor Node.js
  Future<String?> _locateBackendExecutable() async {
    // Em desenvolvimento: procura em server/dist/
    if (!kReleaseMode) {
      final devPath = path.join(
        Directory.current.path,
        'server',
        'dist',
        _exeName,
      );

      if (await File(devPath).exists()) {
        return devPath;
      }
    }
    
    // Em release: procura junto ao executável do Flutter
    final exeDir = path.dirname(Platform.resolvedExecutable);

    // Opção 1: Na pasta data/flutter_assets/assets/backend
    final assetsPath = path.join(exeDir, 'data', 'flutter_assets', 'assets', 'backend', _exeName);
    if (await File(assetsPath).exists()) {
      return assetsPath;
    }

    // Opção 2: Na pasta backend/ ao lado do executável
    final bundledPath1 = path.join(exeDir, 'backend', _exeName);
    if (await File(bundledPath1).exists()) {
      return bundledPath1;
    }

    // Opção 3: No mesmo diretório do executável
    final bundledPath2 = path.join(exeDir, _exeName);
    if (await File(bundledPath2).exists()) {
      return bundledPath2;
    }

    return null;
  }

  /// Verifica se o servidor está acessível via WebSocket
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

