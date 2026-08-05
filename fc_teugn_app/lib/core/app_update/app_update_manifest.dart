class AppUpdateManifest {
  const AppUpdateManifest({
    required this.schemaVersion,
    required this.versionName,
    required this.versionCode,
    required this.apkUri,
    required this.sha256,
    required this.fileSize,
    required this.publishedAt,
    required this.mandatory,
    required this.releaseNotes,
  });

  factory AppUpdateManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = _positiveInt(json['schemaVersion'], 'schemaVersion');
    if (schemaVersion != 1) {
      throw const FormatException('Unbekannte Update-Manifest-Version.');
    }

    final versionName = _requiredString(json['versionName'], 'versionName');
    final versionCode = _positiveInt(json['versionCode'], 'versionCode');
    final apkUri = Uri.tryParse(_requiredString(json['apkUrl'], 'apkUrl'));
    if (apkUri == null || apkUri.scheme != 'https' || apkUri.host.isEmpty) {
      throw const FormatException('apkUrl muss eine HTTPS-Adresse sein.');
    }

    final hash = _requiredString(json['sha256'], 'sha256').toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) {
      throw const FormatException('sha256 ist ungültig.');
    }

    final publishedAt = DateTime.tryParse(
      _requiredString(json['publishedAt'], 'publishedAt'),
    );
    if (publishedAt == null) {
      throw const FormatException('publishedAt ist ungültig.');
    }

    final rawNotes = json['releaseNotes'];
    final notes = rawNotes is List
        ? rawNotes
            .whereType<String>()
            .map((note) => note.trim())
            .where((note) => note.isNotEmpty)
            .take(8)
            .toList(growable: false)
        : const <String>[];

    return AppUpdateManifest(
      schemaVersion: schemaVersion,
      versionName: versionName,
      versionCode: versionCode,
      apkUri: apkUri,
      sha256: hash,
      fileSize: _positiveInt(json['fileSize'], 'fileSize'),
      publishedAt: publishedAt.toUtc(),
      mandatory: json['mandatory'] == true,
      releaseNotes: notes,
    );
  }

  final int schemaVersion;
  final String versionName;
  final int versionCode;
  final Uri apkUri;
  final String sha256;
  final int fileSize;
  final DateTime publishedAt;
  final bool mandatory;
  final List<String> releaseNotes;

  bool isNewerThan(int installedVersionCode) =>
      versionCode > installedVersionCode;

  static String _requiredString(Object? value, String field) {
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('$field fehlt.');
    }
    return value.trim();
  }

  static int _positiveInt(Object? value, String field) {
    final parsed = value is int ? value : int.tryParse('$value');
    if (parsed == null || parsed <= 0) {
      throw FormatException('$field ist ungültig.');
    }
    return parsed;
  }
}
