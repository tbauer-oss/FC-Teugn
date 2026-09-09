/// Compare with the build embedded in the running app, never the server's
/// version as a substitute for the version that is actually loaded.
String? availableWebUpdate(Map<String, dynamic>? manifest,
    {required int installedBuild}) {
  final build = int.tryParse('${manifest?['build_number']}');
  if (build == null) {
    throw const FormatException('Ungültige Versionsinformation');
  }
  if (build <= installedBuild) return null;
  final version = manifest?['version'];
  if (version is! String || version.trim().isEmpty) {
    throw const FormatException('Ungültige Versionsinformation');
  }
  return version;
}
