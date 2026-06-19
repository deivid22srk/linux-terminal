import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:flterm/flterm.dart';
import '../services/setup_service.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  late final TerminalController _controller;
  Pty? _pty;
  final SetupService _setup = SetupService();
  bool _isSetupComplete = false;
  String _setupStatus = 'Initializing...';
  StreamSubscription? _ptySubscription;

  @override
  void initState() {
    super.initState();
    _controller = TerminalController()
      ..onOutput = (bytes) => _pty?.write(bytes)
      ..onResize = (size) => _pty?.resize(size.rows, size.cols);
    _runSetup();
  }

  Future<void> _runSetup() async {
    setState(() => _setupStatus = 'Setting up Linux environment...');

    try {
      await _setup.ensureSetup((msg) {
        if (mounted) setState(() => _setupStatus = msg);
      });

      if (mounted) {
        setState(() {
          _isSetupComplete = true;
          _setupStatus = 'Starting terminal...';
        });
        _startTerminal();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _setupStatus = 'Setup failed: $e');
      }
    }
  }

  void _startTerminal() {
    final shellPath = _setup.getShellPath();

    _pty = Pty.start(
      '/system/bin/sh',
      arguments: [shellPath],
      columns: 80,
      rows: 24,
    );

    _ptySubscription = _pty!.output.listen(_controller.write);

    _pty!.exitCode.then((code) {
      _controller.write([13, 10]);
      _controller.write(
        '${[27, 91, 51, 49, 109]}[process exited: $code]${[27, 91, 48, 109]}'
            .codeUnits,
      );
      _controller.write([13, 10]);
    });

    _pty!.resize(24, 80);
  }

  @override
  void dispose() {
    _ptySubscription?.cancel();
    _pty?.kill();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSetupComplete) {
      return Scaffold(
        appBar: AppBar(title: const Text('Linux Terminal')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _setupStatus,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              if (_setupStatus.contains('failed')) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _isSetupComplete = false;
                      _setupStatus = 'Retrying...';
                    });
                    _runSetup();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Linux Terminal'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset terminal',
            onPressed: () {
              _pty?.kill();
              _startTerminal();
            },
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Column(
        children: [
          Expanded(
            child: TerminalView(
              controller: _controller,
              theme: TerminalTheme.dark().copyWith(
                cursor: const CursorTheme(color: Colors.white, shape: CursorShape.block),
              ),
            ),
          ),
          _buildExtraKeys(),
        ],
      ),
    );
  }

  Widget _buildExtraKeys() {
    final keys = [
      ('ESC', [27]),
      ('TAB', [9]),
      ('CTRL', <int>[]),
      ('ALT', <int>[]),
      ('-', [45]),
      ('↑', [27, 91, 65]),
      ('↓', [27, 91, 66]),
      ('←', [27, 91, 68]),
      ('→', [27, 91, 67]),
    ];
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys.map((k) {
          return InkWell(
            onTap: () {
              if (k.$2.isNotEmpty) {
                _pty?.write(k.$2);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: const Color(0xFF2D2D2D),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                k.$1,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
