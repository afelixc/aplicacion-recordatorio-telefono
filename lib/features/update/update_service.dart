import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// Una versión publicada en GitHub Releases.
class AppRelease {
  const AppRelease({
    required this.buildNumber,
    required this.name,
    required this.apkUrl,
  });

  final int buildNumber;
  final String name;
  final String apkUrl;
}

/// Busca versiones nuevas de la app en GitHub Releases.
///
/// Cada cambio que se sube a `main` publica un release `v1.0.N`, donde N es el
/// número de compilación. Si N es mayor que el de la app instalada, hay versión nueva.
class UpdateService {
  static const repo = 'afelixc/aplicacion-recordatorio-telefono';
  static const apkName = 'Recordame.apk';

  /// Devuelve la versión nueva, o null si no hay (o si no hay internet).
  Future<AppRelease?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final installed = int.tryParse(info.buildNumber) ?? 0;

      final response = await http
          .get(
            Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final tag = json['tag_name'] as String? ?? '';
      final latest = int.tryParse(tag.split('.').last) ?? 0;
      if (latest <= installed) return null;

      final assets = (json['assets'] as List).cast<Map<String, dynamic>>();
      final apk = assets.where((a) => a['name'] == apkName).firstOrNull;
      if (apk == null) return null;

      return AppRelease(
        buildNumber: latest,
        name: tag,
        apkUrl: apk['browser_download_url'] as String,
      );
    } catch (_) {
      return null;
    }
  }
}
