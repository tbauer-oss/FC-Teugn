import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_update_client.dart';
import 'app_update_manifest.dart';

const _manifestUri = 'https://magentacloud.de/public.php/dav/files/'
    'xkgHEESdKbQ6XMP/latest.json';
const _publicShareUri = 'https://magentacloud.de/s/xkgHEESdKbQ6XMP';
const _channel = MethodChannel('de.fcteugn.jugend/app_update');

AppUpdateClient createAppUpdateService() => _AndroidUpdateClient();

class _AndroidUpdateClient implements AppUpdateClient {
  _AndroidUpdateClient()
      : _manifestClient = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 5),
            receiveTimeout: const Duration(seconds: 8),
            sendTimeout: const Duration(seconds: 5),
          ),
        ),
        _downloadClient = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(minutes: 5),
          ),
        );

  final Dio _manifestClient;
  final Dio _downloadClient;

  @override
  bool get supported => Platform.isAndroid;

  @override
  Future<AppUpdateManifest?> checkForUpdate() async {
    if (!supported) return null;

    final publicShareCookies = await _openPublicShareSession();
    final response = await _manifestClient.get<Object?>(
      _manifestUri,
      queryParameters: {'check': DateTime.now().millisecondsSinceEpoch},
      options: Options(
        responseType: ResponseType.json,
        headers: {
          HttpHeaders.acceptHeader: 'application/json',
          HttpHeaders.cacheControlHeader: 'no-cache',
          HttpHeaders.cookieHeader: publicShareCookies,
        },
      ),
    );
    final data = switch (response.data) {
      Map<String, dynamic> value => value,
      String value => jsonDecode(value) as Map<String, dynamic>,
      _ => throw const FormatException('Update-Manifest ist ungültig.'),
    };
    final manifest = AppUpdateManifest.fromJson(data);
    final packageInfo = await PackageInfo.fromPlatform();
    final installedVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;
    return manifest.isNewerThan(installedVersionCode) ? manifest : null;
  }

  @override
  Future<AppUpdateInstallResult> downloadAndInstall(
    AppUpdateManifest manifest, {
    required AppUpdateProgress onProgress,
  }) async {
    if (!supported) return AppUpdateInstallResult.unsupported;

    final cacheRoot = await getTemporaryDirectory();
    final updateDirectory = Directory(
      '${cacheRoot.path}${Platform.pathSeparator}app_updates',
    );
    await updateDirectory.create(recursive: true);
    final apk = File(
      '${updateDirectory.path}${Platform.pathSeparator}'
      'fc-teugn-talents-${manifest.versionCode}.apk',
    );

    if (!await _isValid(apk, manifest)) {
      if (await apk.exists()) await apk.delete();
      final publicShareCookies = await _openPublicShareSession();
      await _downloadClient.download(
        manifest.apkUri.toString(),
        apk.path,
        deleteOnError: true,
        options: Options(
          headers: {
            HttpHeaders.cacheControlHeader: 'no-cache',
            HttpHeaders.cookieHeader: publicShareCookies,
          },
        ),
        onReceiveProgress: (received, total) {
          onProgress(total > 0 ? received / total : null);
        },
      );
      if (!await _isValid(apk, manifest)) {
        if (await apk.exists()) await apk.delete();
        throw const FormatException(
          'Die heruntergeladene APK konnte nicht sicher geprüft werden.',
        );
      }
    } else {
      onProgress(1);
    }

    final status = await _channel.invokeMethod<String>(
      'installApk',
      {'path': apk.path},
    );
    return switch (status) {
      'launched' => AppUpdateInstallResult.launched,
      'permissionRequired' => AppUpdateInstallResult.permissionRequired,
      _ => AppUpdateInstallResult.unsupported,
    };
  }

  Future<String> _openPublicShareSession() async {
    final response = await _manifestClient.get<void>(
      _publicShareUri,
      options: Options(
        responseType: ResponseType.plain,
        headers: const {HttpHeaders.cacheControlHeader: 'no-cache'},
      ),
    );
    final cookies = response.headers.map[HttpHeaders.setCookieHeader]
        ?.map((value) => value.split(';').first.trim())
        .where((value) => value.isNotEmpty)
        .join('; ');
    if (cookies == null || cookies.isEmpty) {
      throw const HttpException(
        'Die öffentliche MagentaCLOUD-Freigabe konnte nicht geöffnet werden.',
      );
    }
    return cookies;
  }

  Future<bool> _isValid(
    File apk,
    AppUpdateManifest manifest,
  ) async {
    if (!await apk.exists()) return false;
    if (await apk.length() != manifest.fileSize) return false;
    final digest = await sha256.bind(apk.openRead()).first;
    return digest.toString().toLowerCase() == manifest.sha256;
  }
}
