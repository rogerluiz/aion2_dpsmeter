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
      final List<String> args = useMock ? <String>['--mock'] : <String>[];

      // Dev mode: tenta rodar via 'node src/index.js' diretamente (sem compilar exe)
      if (!kReleaseMode) {
        final started = await _tryStartWithNode(args);
        if (started) return true;
      }

      // Produção (ou fallback): usa o exe compilado
      final serverExe = await _locateBackendExecutable();
      if (serverExe == null) {
        debugPrint('Servidor executável não encontrado ($_exeName)');
        return false;
      }

      debugPrint('Iniciando servidor: $serverExe');
      _backendProcess = await Process.start(
        serverExe,
        args,
        mode: ProcessStartMode.normal,
        runInShell: false,
      );
      _isRunning = true;
      await Future.delayed(const Duration(seconds: 2));
      debugPrint('Servidor iniciado (PID: ${_backendProcess!.pid})');
      return true;
    } catch (e) {
      debugPrint('Erro ao iniciar servidor: $e');
      return false;
    }
  }

  /// Tenta iniciar o servidor com `node src/index.js` para dev rápido.
  Future<bool> _tryStartWithNode(List<String> extraArgs) async {
    // Se já há algo ouvindo na porta 8765, reutiliza — evita stacking de processos
    // ao fazer hot restart ou flutter run múltiplas vezes.
    try {
      final sock = await Socket.connect('127.0.0.1', 8765,
          timeout: const Duration(milliseconds: 300));
      await sock.close();
      debugPrint('[Dev] Servidor já ativo na porta 8765, reutilizando.');
      _isRunning = true;
      return true;
    } catch (_) {
      // Porta livre — prossegue com o start
    }

    // Sobe até encontrar server/src/index.js relativo ao cwd do processo
    final candidates = [
      path.join(Directory.current.path, '..', 'server', 'src', 'index.js'),
      path.join(Directory.current.path, 'server', 'src', 'index.js'),
    ];

    String? indexJs;
    for (final c in candidates) {
      if (await File(c).exists()) {
        indexJs = path.normalize(c);
        break;
      }
    }
    if (indexJs == null) return false;

    // Verifica se node está disponível
    try {
      final which = await Process.run('where', ['node']);
      if (which.exitCode != 0) return false;
    } catch (_) {
      return false;
    }

    debugPrint('[Dev] Iniciando servidor via node: $indexJs');
    _backendProcess = await Process.start(
      'node',
      [indexJs, ...extraArgs],
      mode: ProcessStartMode.normal,
      runInShell: false,
      workingDirectory: path.dirname(path.dirname(indexJs)), // server/
    );
    _isRunning = true;
    // node precisa de um pouco mais de tempo para JIT + bind ws
    await Future.delayed(const Duration(seconds: 3));
    debugPrint('[Dev] Servidor node iniciado (PID: ${_backendProcess!.pid})');
    return true;
  }

  /// Para o servidor
  Future<void> stop() async {
    if (_backendProcess != null) {
      _backendProcess!.kill();
      _backendProcess = null;
      _isRunning = false;
    }
  }

  /// Localiza o executável do servidor Node.js (produção)
  Future<String?> _locateBackendExecutable() async {
    if (!kReleaseMode) {
      final devPath = path.join(
        Directory.current.path,
        'server', 'dist', _exeName,
      );
      if (await File(devPath).exists()) return devPath;
    }

    final exeDir = path.dirname(Platform.resolvedExecutable);

    final assetsPath = path.join(exeDir, 'data', 'flutter_assets', 'assets', 'backend', _exeName);
    if (await File(assetsPath).exists()) return assetsPath;

    final bundledPath1 = path.join(exeDir, 'backend', _exeName);
    if (await File(bundledPath1).exists()) return bundledPath1;

    final bundledPath2 = path.join(exeDir, _exeName);
    if (await File(bundledPath2).exists()) return bundledPath2;

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

