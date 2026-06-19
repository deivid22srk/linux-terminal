import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/flutter.dart';
import 'package:xterm/xterm.dart';
import '../services/setup_service.dart';

class TerminalScreen extends StatefulWidget {
  const TerminalScreen({super.key});

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  final Terminal _terminal = Terminal(maxLines: 10000);
  Pty? _pty;
  final SetupService _setup = SetupService();
  bool _isSetupComplete = false;
  String _setupStatus = 'Initializing...';
  StreamSubscription? _ptySubscription;

  @override
  void initState() {
    super.initState();
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
      columns: _terminal.viewWidth,
      rows: _terminal.viewHeight,
    );

    _ptySubscription = _pty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder())
        .listen(_terminal.write);

    _pty!.exitCode.then((code) {
      _terminal.write('\r\n\x1b[31m[process exited: $code]\x1b[0m\r\n');
    });

    _terminal.onOutput = (data) {
      _pty?.write(const Utf8Encoder().convert(data));
    };

    _terminal.onResize = (w, h, pw, ph) {
      _pty?.resize(h, w);
    };
  }

  @override
  void dispose() {
    _ptySubscription?.cancel();
    _pty?.kill();
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
              _terminal,
              theme: TerminalTheme(
                cursor: const TextStyle(color: Colors.white),
                foreground: const TextStyle(color: Color(0xFFD4D4D4)),
                background: const TextStyle(color: Colors.black),
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
      _KeyDef('ESC', '\x1b'),
      _KeyDef('TAB', '\t'),
      _KeyDef('CTRL', ''),
      _KeyDef('ALT', ''),
      _KeyDef('/', '/'),
      _KeyDef('-', '-'),
      _KeyDef('↑', '\x1b[A'),
      _KeyDef('↓', '\x1b[B'),
      _KeyDef('←', '\x1b[D'),
      _KeyDef('→', '\x1b[C'),
    ];
    return Container(
      color: const Color(0xFF1E1E1E),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: keys.map((k) {
          return InkWell(
            onTap: () {
              if (k.value.isNotEmpty) {
                _pty?.write(utf8.encode(k.value));
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
                k.label,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _KeyDef {
  final String label;
  final String value;
  const _KeyDef(this.label, this.value);
}
