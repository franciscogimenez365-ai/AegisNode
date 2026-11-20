import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'mesh_chat_service.dart';
import 'nodo_config_service.dart';
import 'waypoints_service.dart';

class OfertaCartografica {
  final String autor;
  final String ip;
  final List<String> archivosFaltantes; // ej. ['Buenos_Aires.mbtiles', 'red_vial.json']
  final Map<String, String> etiquetas; // archivo -> 'Buenos_Aires.mbtiles (45.2 MB)'

  OfertaCartografica({
    required this.autor,
    required this.ip,
    required this.archivosFaltantes,
    required this.etiquetas,
  });
}

class SyncCartografiaService {
  static final Map<String, OfertaCartografica> ofertasActivas = {};

  static Future<String> obtenerRutaMapas() async {
    final extDirs = await getExternalStorageDirectories();
    final Directory baseDir;
    if (extDirs != null && extDirs.isNotEmpty) {
      baseDir = extDirs.first;
    } else {
      final appDir = await getApplicationDocumentsDirectory();
      baseDir = Directory('${appDir.path}/AegisNode');
    }
    final mapasDir = Directory('${baseDir.path}/mapas');
    if (!await mapasDir.exists()) await mapasDir.create(recursive: true);
    return mapasDir.path;
  }

  static Future<String> _obtenerIpLocal() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        final nombre = iface.name.toLowerCase();
        if (nombre.contains('ap') ||
            nombre.contains('swlan') ||
            nombre.contains('wlan')) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) return addr.address;
          }
        }
      }
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (_) {}
    return '192.168.43.1';
  }

  /// Construye el paquete compacto con inventario + IP local para descarga directa
  static Future<String?> construirPaqueteInventario(NodoConfig cfg) async {
    if (!cfg.syncMapasYRutas && !cfg.syncWaypointsPersonales) return null;

    final rutaMapas = await obtenerRutaMapas();
    final dir = Directory(rutaMapas);
    if (!await dir.exists()) return null;

    final List<Map<String, String>> archivos = [];

    if (cfg.syncMapasYRutas) {
      for (final f in dir.listSync().whereType<File>()) {
        final nombre = f.uri.pathSegments.last;
        if (nombre.toLowerCase().endsWith('.mbtiles') ||
            nombre == 'red_vial.json') {
          final mb = (f.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
          archivos.add({'nombre': nombre, 'mb': mb});
        }
      }
    }

    List<Map<String, dynamic>> wps = [];
    if (cfg.syncWaypointsPersonales) {
      final listaWp = await WaypointsService.cargar(rutaMapas);
      wps = listaWp.take(15).map((w) => w.toJson()).toList();
    }

    if (archivos.isEmpty && wps.isEmpty) return null;

    final ip = await _obtenerIpLocal();
    final payload = jsonEncode({
      'ip': ip,
      'archivos': archivos,
      if (wps.isNotEmpty) 'wps': wps,
    });
    return 'SYNC_MAP:$payload';
  }

  /// Procesa el inventario del vecino y publica tarjeta clicable si hay archivos nuevos
  static Future<void> procesarInventarioRecibido(
      String autorVecino, String rawText, NodoConfig cfg) async {
    if (!rawText.startsWith('SYNC_MAP:')) return;
    try {
      final data = jsonDecode(rawText.substring('SYNC_MAP:'.length))
          as Map<String, dynamic>;
      final rutaMapas = await obtenerRutaMapas();

      // 1. Fusionar Waypoints recibidos directo por BLE si ambos lo tienen activo
      if (cfg.syncWaypointsPersonales && data['wps'] is List) {
        final actuales = await WaypointsService.cargar(rutaMapas);
        int agregados = 0;
        for (final item in (data['wps'] as List)) {
          final wp = WaypointTactico.fromJson(item as Map<String, dynamic>);
          if (!actuales.any((a) =>
              (a.lat - wp.lat).abs() < 0.0001 &&
              (a.lon - wp.lon).abs() < 0.0001)) {
            actuales.add(wp);
            agregados++;
          }
        }
        if (agregados > 0) {
          await WaypointsService.guardarLista(rutaMapas, actuales);
          MeshChatService.publicarAvisoSistema(
            '🚩 Sincronizados $agregados waypoints tácticos desde $autorVecino.',
          );
        }
      }

      // 2. Detectar mapas o red vial que no tenemos y crear tarjeta con enlaces
      if (cfg.syncMapasYRutas && data['archivos'] is List) {
        final ip = data['ip']?.toString() ?? '192.168.43.1';
        final faltantes = <String>[];
        final etiquetas = <String, String>{};

        for (final item in (data['archivos'] as List)) {
          final mapItem = item as Map<String, dynamic>;
          final nombre = mapItem['nombre']?.toString() ?? '';
          final mb = mapItem['mb']?.toString() ?? '?';
          if (nombre.isNotEmpty && !await File('$rutaMapas/$nombre').exists()) {
            faltantes.add(nombre);
            etiquetas[nombre] = '$nombre ($mb MB)';
          }
        }

        if (faltantes.isNotEmpty) {
          final ofertaId = 'oferta_${autorVecino}_${DateTime.now().millisecondsSinceEpoch}';
          ofertasActivas[ofertaId] = OfertaCartografica(
            autor: autorVecino,
            ip: ip,
            archivosFaltantes: faltantes,
            etiquetas: etiquetas,
          );
          MeshChatService.publicarAvisoSistema(
            'OFERTA_MAPA:$ofertaId',
          );
        }
      }
    } catch (_) {}
  }

  /// Descarga un mapa o red_vial.json directamente desde el Portal Web Wi-Fi del vecino
  static Future<bool> descargarArchivoDesdeVecino({
    required String ip,
    required String nombreArchivo,
    void Function(double pct)? onProgreso,
  }) async {
    try {
      final rutaMapas = await obtenerRutaMapas();
      final destino = '$rutaMapas/$nombreArchivo';
      final encoded = Uri.encodeComponent(nombreArchivo);
      final url = 'http://$ip:8080/archivo/mapas/$encoded';

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(minutes: 5),
      ));

      await dio.download(
        url,
        '$destino.tmp',
        onReceiveProgress: (rec, tot) {
          if (tot > 0 && onProgreso != null) {
            onProgreso((rec / tot).clamp(0.0, 1.0));
          }
        },
      );

      final tmpFile = File('$destino.tmp');
      if (await tmpFile.exists()) {
        await tmpFile.rename(destino);
        return true;
      }
    } catch (_) {}
    return false;
  }
}
