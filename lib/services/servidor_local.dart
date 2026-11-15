import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'mesh_chat_service.dart';
import 'nodo_config_service.dart';

class ServidorLocalService {
  HttpServer? _server;
  String? _ipLocal;

  bool get estaActivo => _server != null;
  String get urlAcceso =>
      _ipLocal != null ? 'http://$_ipLocal:8080' : 'http://127.0.0.1:8080';

  Future<String> _obtenerIpLocal() async {
    try {
      final interfaces =
          await NetworkInterface.list(type: InternetAddressType.IPv4);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
                  addr.address.startsWith('10.') ||
                  addr.address.startsWith('172.'))) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<void> iniciarServidor(String rutaBase) async {
    if (_server != null) return;
    _ipLocal = await _obtenerIpLocal();

    Future<Response> handler(Request request) async {
      final config = await NodoConfigService.cargar();
      final path = Uri.decodeComponent(request.url.path);

      // Endpoint para publicar mensajes desde navegador Wi-Fi hacia la Malla
      if (request.method == 'POST' && path == 'api/chat') {
        if (!config.chatActivo) {
          return Response.forbidden('Chat desactivado por el nodo');
        }
        final body = await request.readAsString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        await MeshChatService.publicarMensajeLocal(
          autor: '${data['autor'] ?? 'Web'} (WiFi)',
          texto: data['texto']?.toString() ?? '',
          ttlInicial: config.ttlMaximo,
        );
        return Response.ok('OK');
      }

      // Descarga de archivos PDF/Mapas/Wikis si está habilitada en privacidad
      if (path.startsWith('archivos/')) {
        if (!config.compartirArchivos) {
          return Response.forbidden('Compartir archivos desactivado');
        }
        final relativo = path.substring('archivos/'.length);
        final file = File('$rutaBase/$relativo');
        if (await file.exists()) {
          return Response.ok(
            file.openRead(),
            headers: {
              'Content-Type': 'application/octet-stream',
              'Content-Disposition':
                  'attachment; filename="${file.uri.pathSegments.last}"',
            },
          );
        }
        return Response.notFound('Archivo no encontrado');
      }

      // Página principal del Portal Web AegisNode
      final listaPdfs = <String>[];
      if (config.compartirArchivos) {
        final dirManuales = Directory('$rutaBase/manuales');
        if (dirManuales.existsSync()) {
          for (final f in dirManuales.listSync().whereType<File>()) {
            final nombre = f.uri.pathSegments.last;
            listaPdfs.add(
                '<li><a href="/archivos/manuales/$nombre" style="color:#FF6D00;">$nombre</a></li>');
          }
        }
      }

      final htmlMensajes = config.chatActivo
          ? MeshChatService.mensajes
              .take(25)
              .map((m) =>
                  '<div style="border-bottom:1px solid #333;padding:6px 0;"><b style="color:#00E676;">${m.autor}</b>: ${m.texto}</div>')
              .join('')
          : '<p style="color:#888;">Chat desactivado por el operador del nodo.</p>';

      final html = '''
      <!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
      <title>AegisNode - Portal de Emergencia</title></head>
      <body style="background:#000;color:#e0e0e0;font-family:sans-serif;padding:16px;">
        <h2 style="color:#FF6D00;">AegisNode // ${config.alias}</h2>
        <p style="color:#00E676;">Rol: ${config.esMaestro ? 'NODO MAESTRO' : 'REPETIDOR'} | Saltos Malla (TTL): ${config.ttlMaximo}</p>
        ${config.chatActivo ? '''
        <h3>Bitácora / Chat de Emergencia</h3>
        <div style="background:#121212;padding:10px;border-radius:8px;margin-bottom:10px;">$htmlMensajes</div>
        <input id="autor" placeholder="Tu nombre" style="padding:8px;width:30%;background:#1a1a1a;color:#fff;border:1px solid #444;">
        <input id="msg" placeholder="Mensaje de reporte..." style="padding:8px;width:45%;background:#1a1a1a;color:#fff;border:1px solid #444;">
        <button onclick="enviar()" style="padding:8px 12px;background:#FF6D00;color:#000;font-weight:bold;border:none;">Enviar</button>
        <script>
          async function enviar(){
            const a=document.getElementById('autor').value||'Vecino';
            const t=document.getElementById('msg').value;
            if(!t)return;
            await fetch('/api/chat',{method:'POST',body:JSON.stringify({autor:a,texto:t})});
            location.reload();
          }
        </script>''' : ''}
        ${config.compartirArchivos ? '<h3>Manuales Disponibles Offline</h3><ul>${listaPdfs.isEmpty ? '<li>Sin archivos en carpeta manuales</li>' : listaPdfs.join('')}</ul>' : ''}
      </body></html>''';

      return Response.ok(html, headers: {'Content-Type': 'text/html; charset=utf-8'});
    }

    _server = await io.serve(handler, InternetAddress.anyIPv4, 8080);
  }

  Future<void> detenerServidor() async {
    await _server?.close(force: true);
    _server = null;
  }
}
