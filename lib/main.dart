import 'package:flutter/material.dart';
import 'screens/terminal_screen.dart';

void main() {
  runApp(const LinuxTerminalApp());
}

class LinuxTerminalApp extends StatelessWidget {
  const LinuxTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Linux Terminal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
      ),
      home: const TerminalScreen(),
    );
  }
}
