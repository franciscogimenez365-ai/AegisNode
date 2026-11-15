import 'dart:async';

class MensajeMesh {
  final String id;
  final String autor;
  final String texto;
  final String? gps;
  final int ttl;
  final DateTime hora;
  final int saltosRecorridos;

  MensajeMesh({
    required this.id,
    required this.autor,
    required this.texto,
    this.gps,
    required this.ttl,
    required this.hora,
    this.saltosRecorridos = 0,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'autor': autor,
        'texto': texto,
        'gps': gps,
        'ttl': ttl,
        'hora': hora.toIso8601String(),
        'saltos': saltosRecorridos,
      };

  factory MensajeMesh.fromJson(Map<String, dynamic> json) => MensajeMesh(
        id: json['id'].toString(),
        autor: json['autor']?.toString() ?? 'Anónimo',
        texto: json['texto']?.toString() ?? '',
        gps: json['gps']?.toString(),
        ttl: json['ttl'] as int? ?? 1,
        hora: DateTime.tryParse(json['hora']?.toString() ?? '') ?? DateTime.now(),
        saltosRecorridos: json['saltos'] as int? ?? 0,
      );
}

class MeshChatService {
  static final List<MensajeMesh> mensajes = [];
  static final List<String> _idsVistos = [];
  static final StreamController<List<MensajeMesh>> _streamCtrl =
      StreamController<List<MensajeMesh>>.broadcast();

  static Stream<List<MensajeMesh>> get streamMensajes => _streamCtrl.stream;

  // Callback hacia el transmisor Bluetooth BLE para difundir/repetir paquetes
  static Future<void> Function(MensajeMesh paqueteReenvio)? onReenviarPaquete;

  static bool yaFueVisto(String id) => _idsVistos.contains(id);

  static void _registrarId(String id) {
    _idsVistos.add(id);
    if (_idsVistos.length > 500) {
      _idsVistos.removeAt(0);
    }
  }

  static Future<void> publicarMensajeLocal({
    required String autor,
    required String texto,
    required int ttlInicial,
    String? gps,
  }) async {
    if (texto.trim().isEmpty) return;

    final msg = MensajeMesh(
      id: '${DateTime.now().microsecondsSinceEpoch}_$autor',
      autor: autor,
      texto: texto.trim(),
      gps: gps,
      ttl: ttlInicial,
      hora: DateTime.now(),
      saltosRecorridos: 0,
    );

    _registrarId(msg.id);
    mensajes.insert(0, msg);
    if (mensajes.length > 200) mensajes.removeLast();
    _streamCtrl.add(List.unmodifiable(mensajes));

    if (msg.ttl > 0 && onReenviarPaquete != null) {
      await onReenviarPaquete!(msg);
    }
  }
  static void publicarAvisoSistema(String texto) {
    mensajes.insert(
      0,
      MensajeMesh(
        id: 'sys_${DateTime.now().microsecondsSinceEpoch}',
        autor: 'SISTEMA BLE',
        texto: texto,
        ttl: 0,
        hora: DateTime.now(),
      ),
    );
    _streamCtrl.add(List.unmodifiable(mensajes));
  }


  static Future<void> recibirPaqueteExterno(Map<String, dynamic> rawJson) async {
    final incoming = MensajeMesh.fromJson(rawJson);
    if (yaFueVisto(incoming.id)) return;

    _registrarId(incoming.id);
    mensajes.insert(0, incoming);
    if (mensajes.length > 200) mensajes.removeLast();
    _streamCtrl.add(List.unmodifiable(mensajes));

    // Si quedan saltos (TTL > 1), lo repite automáticamente a nodos vecinos
    if (incoming.ttl > 1 && onReenviarPaquete != null) {
      final reenvio = MensajeMesh(
        id: incoming.id,
        autor: incoming.autor,
        texto: incoming.texto,
        gps: incoming.gps,
        ttl: incoming.ttl - 1,
        hora: incoming.hora,
        saltosRecorridos: incoming.saltosRecorridos + 1,
      );
      await onReenviarPaquete!(reenvio);
    }
  }
}
