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

Future<LocalYamlSource?> loadLocalYamlSource() async => null;

Future<String?> readLocalTextFile({
  required String baseDirectory,
  required String path,
}) async => null;
