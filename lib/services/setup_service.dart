import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

class SetupService {
  late final String _appDir;
  late final String _rootfsDir;
  late final String _scriptsDir;
  late final String _nativeLibDir;

  static const _rootfsUrl =
      'https://github.com/termux/proot-distro/releases/download/v4.17.3/debian-bookworm-aarch64-pd-v4.17.3.tar.xz';

  Future<void> ensureSetup(void Function(String) onStatus) async {
    final appDir = await getApplicationDocumentsDirectory();
    _appDir = appDir.path;
    _rootfsDir = '$_appDir/rootfs';
    _scriptsDir = '$_appDir/scripts';

    await Directory(_rootfsDir).create(recursive: true);
    await Directory(_scriptsDir).create(recursive: true);
    await Directory('$_appDir/tmp').create(recursive: true);

    _nativeLibDir = _findNativeLibDir();

    await _ensureRootfs(onStatus);
    await _writeStartScript();
  }

  String _findNativeLibDir() {
    try {
      final maps = File('/proc/self/maps').readAsStringSync();
      for (final line in maps.split('\n')) {
        if (line.contains('libflutter.so')) {
          final parts = line.split(' ');
          if (parts.length > 5) {
            final path = parts.last;
            final dir = path.substring(0, path.lastIndexOf('/'));
            if (dir.isNotEmpty) return dir;
          }
        }
      }
    } catch (_) {}

    try {
      final linker = File('/proc/self/exe').resolveSymbolicLinksSync();
      if (linker.contains('/')) {
        return linker.substring(0, linker.lastIndexOf('/'));
      }
    } catch (_) {}

    return '';
  }

  int _detectStripCount(Archive tar) {
    if (tar.isEmpty) return 0;
    final first = tar.first;
    if (!first.isFile) {
      final parts = first.name.split('/');
      if (parts.length > 1 && RegExp(r'^[^/]+$').hasMatch(parts[0])) {
        final prefix = parts[0];
        final allSame = tar.every((e) => e.name.startsWith('$prefix/'));
        if (allSame) return 1;
      }
    }
    return 0;
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

        final data = await response.fold<List<int>>(
          [],
          (prev, chunk) => prev..addAll(chunk),
        );
        final tarball = File('$_appDir/rootfs.tar.xz');
        await tarball.writeAsBytes(data);

        onStatus('Extracting Debian rootfs...');
        await _extractArchive(tarball.path, _rootfsDir);

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

  Future<void> _extractArchive(String archivePath, String outputDir) async {
    final bytes = File(archivePath).readAsBytesSync();
    final decompressed = XZDecoder().decodeBytes(bytes);
    final tar = TarDecoder().decodeBytes(decompressed);
    final strip = _detectStripCount(tar);

    for (final entry in tar) {
      final name = strip > 0 ? entry.name.split('/').skip(strip).join('/') : entry.name;
      if (name.isEmpty) continue;
      final dest = File('$outputDir/$name');
      if (entry.isFile) {
        await dest.parent.create(recursive: true);
        await dest.writeAsBytes(entry.content as List<int>);
      } else {
        await dest.create(recursive: true);
      }
    }
  }

  Future<void> _writeStartScript() async {
    final prootPath = _findProotPath();

    final script = '''#!/system/bin/sh
${_nativeLibDir.isNotEmpty ? "export LD_LIBRARY_PATH=$_nativeLibDir:\$LD_LIBRARY_PATH" : ""}
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
      final candidate1 = '$_nativeLibDir/libproot.so';
      final candidate2 = '$_nativeLibDir/proot';
      if (File(candidate1).existsSync()) return candidate1;
      if (File(candidate2).existsSync()) return candidate2;
    }
    return 'proot';
  }

  String getShellPath() => '$_scriptsDir/start.sh';
}
