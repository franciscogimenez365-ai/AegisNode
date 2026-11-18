import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'mesh_chat_service.dart';

class ServidorLocalService {
  HttpServer? _server;
  String? _ipLocal;
  String _rutaBase = '';

  bool get estaActivo => _server != null;
  String get urlAcceso =>
      _ipLocal != null ? 'http://$_ipLocal:8080' : 'http://192.168.43.1:8080';

  Future<String> iniciarServidor(String rutaBase) async {
    _rutaBase = rutaBase;
    if (_server != null) return urlAcceso;

    _ipLocal = await _obtenerIpLocal();
    final handler = const Pipeline().addHandler(_enrutarPeticion);
    _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 8080);
    return urlAcceso;
  }

  Future<void> detenerServidor() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<String> _obtenerIpLocal() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      // Priorizamos interfaces típicas de Hotspot Android (ap0, wlan1, swlan0)
      for (final iface in interfaces) {
        final nombre = iface.name.toLowerCase();
        if (nombre.contains('ap') ||
            nombre.contains('swlan') ||
            nombre.contains('wlan1')) {
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

  String _generarListaArchivos(String subcarpeta, String tituloVacio) {
    final dir = Directory('$_rutaBase/$subcarpeta');
    if (!dir.existsSync()) return '<li>$tituloVacio</li>';

    final archivos = dir
        .listSync()
        .whereType<File>()
        .where((f) => !f.path.split('/').last.startsWith('.'))
        .toList();

    if (archivos.isEmpty) return '<li>$tituloVacio</li>';

    return archivos.map((f) {
      final nombre = f.path.split('/').last;
      final mb = (f.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
      final encoded = Uri.encodeComponent(nombre);
      return '<li><a href="/archivo/$subcarpeta/$encoded">$nombre</a> <span style="color:#888;font-size:12px;">($mb MB)</span></li>';
    }).join('');
  }

  Future<Response> _enrutarPeticion(Request request) async {
    final path = request.url.path;

    if (path == '' || path == '/') {
      final htmlManuales =
          _generarListaArchivos('manuales', 'Sin manuales PDF aún.');
      final htmlMapas =
          _generarListaArchivos('mapas', 'Sin mapas MBTiles descargados aún.');
      final htmlWikis =
          _generarListaArchivos('wikis', 'Sin enciclopedias ZIM aún.');

      final htmlMensajes = MeshChatService.mensajes
          .where((m) => !m.esPrivado) // Solo mostramos el canal abierto público
          .map((m) =>
              '<div class="msg"><b>[${m.autor}]</b> ${m.texto} ${m.gps != null ? "<br><small>📍 ${m.gps}</small>" : ""}</div>')
          .join('');

      final html = '''
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>AegisNode // Portal Local</title>
<style>
  body { background:#000; color:#e0e0e0; font-family:sans-serif; margin:0; padding:16px; }
  h1 { color:#FF6D00; font-size:20px; border-bottom:1px solid #333; padding-bottom:8px; }
  h2 { color:#00E676; font-size:15px; margin-top:20px; border-left:3px solid #FF6D00; padding-left:8px; }
  .card { background:#121212; border:1px solid #2a2a2a; border-radius:8px; padding:12px; margin-bottom:16px; }
  input, button { width:100%; box-sizing:border-box; padding:12px; margin-top:8px; border-radius:6px; border:1px solid #444; background:#1c1c1c; color:#fff; font-size:15px; }
  button { background:#FF6D00; color:#000; font-weight:bold; border:none; cursor:pointer; }
  .msg { padding:8px; border-bottom:1px solid #222; font-size:14px; }
  li { margin:8px 0; }
  a { color:#00E676; text-decoration:none; word-break:break-all; }
</style>
</head>
<body>
  <h1>AEGISNODE // PORTAL OFFLINE LOCAL</h1>
  <div class="card">
    <h2>Bitácora Comunitaria (Canal Abierto)</h2>
    <form method="POST" action="/enviar">
      <input type="text" name="autor" placeholder="Tu Nombre / Indicativo" required>
      <input type="text" name="texto" placeholder="Escribe mensaje o reporte..." required>
      <button type="submit">TRANSMITIR A LA MALLA</button>
    </form>
    <div style="margin-top:12px; max-height:260px; overflow-y:auto;">$htmlMensajes</div>
  </div>
  <div class="card">
    <h2>Manuales PDF Disponibles</h2>
    <ul>$htmlManuales</ul>
  </div>
  <div class="card">
    <h2>Mapas Offline (.mbtiles)</h2>
    <ul>$htmlMapas</ul>
  </div>
  <div class="card">
    <h2>Enciclopedias Offline (.zim)</h2>
    <ul>$htmlWikis</ul>
  </div>
</body>
</html>
''';
      return Response.ok(html,
          headers: {'Content-Type': 'text/html; charset=utf-8'});
    }

    if (path == 'enviar' && request.method == 'POST') {
      final body = await request.readAsString();
      final params = Uri.splitQueryString(body);
      final autor = params['autor']?.trim() ?? 'Web-Local';
      final texto = params['texto']?.trim() ?? '';
      if (texto.isNotEmpty) {
        await MeshChatService.publicarMensajeLocal(
          autor: '$autor (WiFi)',
          texto: texto,
          ttlInicial: 7,
        );
      }
      return Response.found('/');
    }

    if (path.startsWith('archivo/')) {
      final partes = path.split('/');
      if (partes.length >= 3) {
        final carpeta = partes[1];
        if (carpeta == 'manuales' || carpeta == 'mapas' || carpeta == 'wikis') {
          final nombre = Uri.decodeComponent(partes.sublist(2).join('/'));
          final file = File('$_rutaBase/$carpeta/$nombre');
          if (await file.exists()) {
            final tamano = await file.length();
            return Response.ok(
              file.openRead(),
              headers: {
                'Content-Type': 'application/octet-stream',
                'Content-Length': '$tamano',
                'Content-Disposition': 'attachment; filename="$nombre"',
              },
            );
          }
        }
      }
    }

    return Response.notFound('Recurso no encontrado');
  }
}
