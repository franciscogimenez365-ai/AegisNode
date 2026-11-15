import 'package:flutter/services.dart';

class KiwixBridge {
  static const MethodChannel _channel =
      MethodChannel('com.emergencia.aegis_node/kiwix');

  static String? urlBaseZim;

  static Future<String?> abrirZim(String rutaArchivo) async {
    try {
      final String? url =
          await _channel.invokeMethod('abrirZim', {'ruta': rutaArchivo});
      urlBaseZim = url;
      return url;
    } catch (e) {
      urlBaseZim = null;
      return null;
    }
  }

  static Future<List<Map<String, String>>> buscarSugerencias(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final List<dynamic>? res =
          await _channel.invokeMethod('buscar', {'query': query});
      if (res == null) return [];
      return res
          .map((item) => Map<String, String>.from(item as Map))
          .toList();
    } catch (e) {
      return [];
    }
  }
}
