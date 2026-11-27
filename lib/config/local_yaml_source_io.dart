import 'dart:io';

class LocalYamlSource {
  const LocalYamlSource({
    required this.path,
    required this.baseDirectory,
    required this.content,
  });

  final String path;
  final String baseDirectory;
  final String content;
}

Future<LocalYamlSource?> loadLocalYamlSource() async {
  final configured = Platform.environment['APP_CONFIG_PATH']?.trim() ?? '';
  final candidates = <File>[
    if (configured.isNotEmpty) File(configured),
    File('config/app.local.yaml'),
  ];
  var directory = Directory.current;
  for (var depth = 0; depth < 6; depth++) {
    candidates.add(File('${directory.path}/config/app.local.yaml'));
    final parent = directory.parent;
    if (parent.path == directory.path) {
      break;
    }
    directory = parent;
  }
  for (final file in candidates) {
    if (await file.exists()) {
      return LocalYamlSource(
        path: file.absolute.path,
        baseDirectory: file.absolute.parent.path,
        content: await file.readAsString(),
      );
    }
  }
  return null;
}

Future<String?> readLocalTextFile({
  required String baseDirectory,
  required String path,
}) async {
  final file = File(File(path).isAbsolute ? path : '$baseDirectory/$path');
  return file.existsSync() ? file.readAsString() : null;
}
