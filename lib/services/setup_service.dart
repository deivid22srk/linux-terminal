import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SetupService {
  late final String _appDir;
  late final String _rootfsDir;
  late final String _binDir;
  late final String _scriptsDir;
  bool _initialized = false;

  static const String _rootfsUrl =
      'https://github.com/termux/proot-distro/releases/download/v4.10.0/debian-bookworm-aarch64.tar.gz';

  static const String _prootDebUrl =
      'https://packages.termux.dev/apt/termux-main/pool/main/p/proot/';

  Future<void> ensureSetup(void Function(String) onStatus) async {
    final appDir = await getApplicationDocumentsDirectory();
    _appDir = appDir.path;
    _rootfsDir = '$_appDir/rootfs';
    _binDir = '$_appDir/bin';
    _scriptsDir = '$_appDir/scripts';
    _initialized = true;

    await Directory(_rootfsDir).create(recursive: true);
    await Directory(_binDir).create(recursive: true);
    await Directory(_scriptsDir).create(recursive: true);
    await Directory('$_appDir/tmp').create(recursive: true);

    await _ensureProot(onStatus);
    await _ensureRootfs(onStatus);
    await _writeStartScript();
  }

  Future<void> _ensureProot(void Function(String) onStatus) async {
    final prootBin = '$_binDir/proot';
    if (File(prootBin).existsSync() &&
        File('$_binDir/libproot.so').existsSync()) {
      return;
    }

    onStatus('Downloading proot binary...');
    try {
      final debUrl = await _findLatestProotDeb();
      if (debUrl != null) {
        await _downloadAndExtractProot(debUrl);
        return;
      }
    } catch (_) {}

    onStatus('Using bundled proot...');
    await _copyFromAssets();
  }

  Future<String?> _findLatestProotDeb() async {
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(
          Uri.parse(
              'https://packages.termux.dev/apt/termux-main/dists/stable/main/binary-aarch64/Packages.gz'),
        );
        final response = await request.close();
        final bytes = await response.fold<List<int>>(
          [],
          (prev, chunk) => prev..addAll(chunk),
        );
        final content = utf8.decode(bytes);
        final lines = content.split('\n');
        bool inProot = false;
        for (final line in lines) {
          if (line.startsWith('Package: ') && line.contains('proot')) {
            inProot = true;
          } else if (line.startsWith('Package: ')) {
            inProot = false;
          } else if (inProot && line.startsWith('Filename: ')) {
            return line.substring(10).trim();
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
    return null;
  }

  Future<void> _downloadAndExtractProot(String debPath) async {
    final client = HttpClient();
    try {
      final url = 'https://packages.termux.dev/apt/termux-main/$debPath';
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final bytes = await response.fold<List<int>>(
        [],
        (prev, chunk) => prev..addAll(chunk),
      );

      final debFile = File('$_appDir/proot.deb');
      await debFile.writeAsBytes(bytes);

      await _extractDeb(debFile.path);
      await debFile.delete();
    } finally {
      client.close();
    }
  }

  Future<void> _extractDeb(String debPath) async {
    await _exec('ar', ['x', debPath, '--output=$_appDir']);
    final dataTar = '$_appDir/data.tar.xz';
    if (File(dataTar).existsSync()) {
      await _exec('tar', ['xf', dataTar, '-C', _appDir]);
      final usrDir = '$_appDir/data/data/com.termux/files/usr';
      for (final entry in ['bin/proot', 'lib/libproot.so', 'lib/libtalloc.so']) {
        final src = '$usrDir/$entry';
        if (File(src).existsSync()) {
          await File(src).copy('$_binDir/${entry.split('/').last}');
        }
      }
      await _exec('chmod', ['+x', '$_binDir/proot']);
      await Directory('$_appDir/data').delete(recursive: true);
    }
  }

  Future<void> _ensureRootfs(void Function(String) onStatus) async {
    final marker = '$_rootfsDir/.installed';
    if (File(marker).existsSync()) return;

    onStatus('Downloading Debian rootfs (large file, may take a while)...');
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_rootfsUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        onStatus('Saving rootfs tarball...');
        final tarball = File('$_appDir/rootfs.tar.gz');
        await tarball.writeAsBytes(
          await response.fold<List<int>>(
            [],
            (prev, chunk) => prev..addAll(chunk),
          ),
        );

        onStatus('Extracting Debian rootfs...');
        await _exec('tar', ['xzf', tarball.path, '-C', _rootfsDir]);
        await tarball.delete();
        await File(marker).writeAsString('done');
      } finally {
        client.close();
      }
    } catch (e) {
      onStatus('Rootfs download failed: $e');
      rethrow;
    }
  }

  Future<void> _writeStartScript() async {
    final script = '''#!/system/bin/sh
export LD_LIBRARY_PATH=$_binDir:\$LD_LIBRARY_PATH
export PATH=$_binDir:/system/bin:/system/xbin

mkdir -p $_rootfsDir/proc $_rootfsDir/sys $_rootfsDir/dev $_rootfsDir/tmp $_appDir/tmp

exec $_binDir/proot \\
  -0 \\
  -r $_rootfsDir \\
  -b /dev \\
  -b /proc \\
  -b /sys \\
  -b $_appDir/tmp:/tmp \\
  -w /root \\
  /usr/bin/env -i \\
  HOME=/root \\
  TERM=xterm-256color \\
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \\
  /bin/bash --login
''';
    await File('$_scriptsDir/start.sh').writeAsString(script);
    await _exec('chmod', ['+x', '$_scriptsDir/start.sh']);
  }

  Future<void> _exec(String cmd, List<String> args) async {
    final result = await Process.run(cmd, args);
    if (result.exitCode != 0) {
      throw Exception('$cmd ${args.first}: ${result.stderr}');
    }
  }

  Future<void> _copyFromAssets() async {
    for (final name in ['proot', 'libproot.so', 'libtalloc.so']) {
      try {
        final data = await rootBundle.load('assets/scripts/$name');
        await File('$_binDir/$name')
            .writeAsBytes(data.buffer.asUint8List());
      } catch (_) {}
    }
    await _exec('chmod', ['+x', '$_binDir/proot']);
  }

  String getShellPath() => '$_scriptsDir/start.sh';
}
