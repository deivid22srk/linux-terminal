import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class SetupService {
  late final String _appDir;
  late final String _rootfsDir;
  late final String _scriptsDir;
  late final String _nativeLibDir;

  static const _rootfsUrl =
      'https://github.com/termux/proot-distro/releases/download/v4.10.0/debian-bookworm-aarch64.tar.gz';
  static const _channel = MethodChannel('com.linuxterminal.app/native');

  Future<void> ensureSetup(void Function(String) onStatus) async {
    final appDir = await getApplicationDocumentsDirectory();
    _appDir = appDir.path;
    _rootfsDir = '$_appDir/rootfs';
    _scriptsDir = '$_appDir/scripts';

    await Directory(_rootfsDir).create(recursive: true);
    await Directory(_scriptsDir).create(recursive: true);
    await Directory('$_appDir/tmp').create(recursive: true);

    _nativeLibDir = await _getNativeLibDir();

    await _ensureRootfs(onStatus);
    await _writeStartScript();
  }

  Future<String> _getNativeLibDir() async {
    try {
      return await _channel.invokeMethod('getNativeLibDir');
    } catch (_) {
      return '';
    }
  }

  Future<void> _ensureRootfs(void Function(String) onStatus) async {
    final marker = '$_rootfsDir/.installed';
    if (File(marker).existsSync()) return;

    onStatus('Downloading Debian rootfs (this may take a while)...');
    try {
      final client = HttpClient();
      try {
        final request = await client.getUrl(Uri.parse(_rootfsUrl));
        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('HTTP ${response.statusCode}',
              uri: Uri.parse(_rootfsUrl));
        }

        final tarball = File('$_appDir/rootfs.tar.gz');
        await tarball.writeAsBytes(
          await response.fold<List<int>>(
            [],
            (prev, chunk) => prev..addAll(chunk),
          ),
        );

        onStatus('Extracting Debian rootfs...');
        final result = await Process.run(
          'tar',
          ['xzf', tarball.path, '-C', _rootfsDir],
        );
        if (result.exitCode != 0) {
          throw Exception('Extraction failed: ${result.stderr}');
        }
        await tarball.delete();
        await File(marker).writeAsString('done');
      } finally {
        client.close();
      }
    } catch (e) {
      onStatus('Download failed: $e');
      rethrow;
    }
  }

  Future<void> _writeStartScript() async {
    final prootPath = _findProotPath();
    final libPath = _nativeLibDir.isNotEmpty ? _nativeLibDir : '';

    final script = '''#!/system/bin/sh
${libPath.isNotEmpty ? "export LD_LIBRARY_PATH=$libPath:\$LD_LIBRARY_PATH" : ""}
export PATH=/system/bin:/system/xbin

mkdir -p $_rootfsDir/proc $_rootfsDir/sys $_rootfsDir/dev $_rootfsDir/tmp $_appDir/tmp

exec $prootPath \\
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
    await Process.run('chmod', ['+x', '$_scriptsDir/start.sh']);
  }

  String _findProotPath() {
    if (_nativeLibDir.isNotEmpty) {
      final bundled = '$_nativeLibDir/libproot.so';
      if (File(bundled).existsSync()) return bundled;
      final bundledBin = '$_nativeLibDir/proot';
      if (File(bundledBin).existsSync()) return bundledBin;
    }
    return 'proot';
  }

  String getShellPath() => '$_scriptsDir/start.sh';
}
