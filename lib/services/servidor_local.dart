import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'mesh_chat_service.dart';

class ServidorLocalService {
  HttpServer? _server;
  String? _ipLocal;
  String _rutaBase = '';
  static const HtmlEscape _htmlEscape = HtmlEscape();
  final Map<String, List<DateTime>> _historialPeticionesIp = {};

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
    _historialPeticionesIp.clear();
  }

  bool _permitirTasaIp(Request request) {
    final connInfo =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    final ip = connInfo?.remoteAddress.address ?? 'unknown';
    final ahora = DateTime.now();
    final ventana = ahora.subtract(const Duration(seconds: 15));

    final lista = _historialPeticionesIp.putIfAbsent(ip, () => []);
    lista.removeWhere((t) => t.isBefore(ventana));
    if (lista.length >= 10) return false;
    lista.add(ahora);
    return true;
  }

  Future<String> _obtenerIpLocal() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
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
    if (!dir.existsSync()) return '<li>${_htmlEscape.convert(tituloVacio)}</li>';

    final archivos = dir
        .listSync()
        .whereType<File>()
        .where((f) => !f.uri.pathSegments.last.startsWith('.'))
        .toList();

    if (archivos.isEmpty) return '<li>${_htmlEscape.convert(tituloVacio)}</li>';

    return archivos.map((f) {
      final nombre = f.uri.pathSegments.last;
      final nombreSeguro = _htmlEscape.convert(nombre);
      final mb = (f.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
      final encoded = Uri.encodeComponent(nombre);
      return '<li><a href="/archivo/$subcarpeta/$encoded">$nombreSeguro</a> <span style="color:#888;font-size:12px;">($mb MB)</span></li>';
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
          .where((m) => !m.esPrivado)
          .map((m) {
        final autorSeguro = _htmlEscape.convert(m.autor);
        final textoSeguro = _htmlEscape.convert(m.texto);
        final gpsSeguro =
            m.gps != null ? _htmlEscape.convert(m.gps!) : null;
        return '<div class="msg"><b>[$autorSeguro]</b> $textoSeguro ${gpsSeguro != null ? "<br><small>📍 $gpsSeguro</small>" : ""}</div>';
      }).join('');

      final html = '''
<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="Content-Security-Policy" content="default-src 'self'; style-src 'unsafe-inline'; script-src 'none';">
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
      <input type="text" name="autor" maxlength="24" placeholder="Tu Nombre / Indicativo" required>
      <input type="text" name="texto" maxlength="400" placeholder="Escribe mensaje o reporte..." required>
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
      return Response.ok(html, headers: {
        'Content-Type': 'text/html; charset=utf-8',
        'X-Content-Type-Options': 'nosniff',
        'X-Frame-Options': 'DENY',
      });
    }

    if (path == 'enviar' && request.method == 'POST') {
      if (!_permitirTasaIp(request)) {
        return Response(429, body: 'Demasiadas peticiones. Espera unos segundos.');
      }

      final contentLength = request.contentLength ?? 0;
      if (contentLength > 4096) {
        return Response(413, body: 'Mensaje demasiado extenso');
      }

      final body = await request.readAsString();
      if (body.length > 4096) {
        return Response(413, body: 'Mensaje demasiado extenso');
      }

      final params = Uri.splitQueryString(body);
      var autor = (params['autor'] ?? 'Web-Local').trim();
      var texto = (params['texto'] ?? '').trim();
      if (autor.length > 24) autor = autor.substring(0, 24);
      if (texto.length > 400) texto = texto.substring(0, 400);

      if (texto.isNotEmpty) {
        await MeshChatService.publicarMensajeLocal(
          autor: '${autor.isEmpty ? "Web-Local" : autor} (WiFi)',
          texto: texto,
          ttlInicial: 7,
        );
      }
      return Response.found('/');
    }

    if (path.startsWith('archivo/')) {
      final partes = path.split('/');
      if (partes.length == 3) {
        final carpeta = partes[1];
        const permitidas = {'manuales', 'mapas', 'wikis'};
        if (!permitidas.contains(carpeta)) {
          return Response.forbidden('Carpeta no autorizada');
        }

        final nombreDecodificado = Uri.decodeComponent(partes[2]);
        if (nombreDecodificado.isEmpty ||
            nombreDecodificado.startsWith('.') ||
            nombreDecodificado.contains('..') ||
            nombreDecodificado.contains('/') ||
            nombreDecodificado.contains('\\') ||
            nombreDecodificado.contains('\x00')) {
          return Response.forbidden('Nombre de archivo inválido');
        }

        final dirBase = Directory('$_rutaBase/$carpeta');
        if (!await dirBase.exists()) {
          return Response.notFound('Directorio inexistente');
        }

        final file = File('${dirBase.path}/$nombreDecodificado');
        if (await file.exists()) {
          final rutaCanonicaDir = await dirBase.resolveSymbolicLinks();
          final rutaCanonicaArchivo = await file.resolveSymbolicLinks();

          if (!rutaCanonicaArchivo
              .startsWith('$rutaCanonicaDir${Platform.pathSeparator}')) {
            return Response.forbidden('Acceso denegado fuera de directorio');
          }

          final tamano = await file.length();
          final nombreHeaderSeguro =
              nombreDecodificado.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');

          return Response.ok(
            file.openRead(),
            headers: {
              'Content-Type': 'application/octet-stream',
              'Content-Length': '$tamano',
              'X-Content-Type-Options': 'nosniff',
              'Content-Disposition':
                  'attachment; filename="$nombreHeaderSeguro"',
            },
          );
        }
      }
    }

    return Response.notFound('Recurso no encontrado');
  }
}
