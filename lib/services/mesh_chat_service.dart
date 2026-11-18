import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart';
import 'nodo_config_service.dart';
import 'sync_cartografia_service.dart';

class MensajeMesh {
  final String id;
  final String autor;
  final String texto;
  final int ttl;
  final int saltosRecorridos;
  final DateTime timestamp;
  final String? gps;
  final bool esPrivado;

  MensajeMesh({
    required this.id,
    required this.autor,
    required this.texto,
    required this.ttl,
    this.saltosRecorridos = 0,
    required this.timestamp,
    this.gps,
    this.esPrivado = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'a': autor,
        't': texto,
        'ttl': ttl,
        's': saltosRecorridos,
        'ts': timestamp.millisecondsSinceEpoch,
        if (gps != null) 'g': gps,
      };

  factory MensajeMesh.fromJson(Map<String, dynamic> json) => MensajeMesh(
        id: json['id']?.toString() ?? '',
        autor: json['a']?.toString() ?? 'Anónimo',
        texto: json['t']?.toString() ?? '',
        ttl: (json['ttl'] as num?)?.toInt() ?? 1,
        saltosRecorridos: (json['s'] as num?)?.toInt() ?? 0,
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            (json['ts'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
        gps: json['g']?.toString(),
      );
}

class MeshChatService {
  static const MethodChannel _cryptoChannel =
      MethodChannel('com.emergencia.aegis_node/kiwix');

  static final List<MensajeMesh> _mensajes = [];
  static final Set<String> _idsVistos = {};
  static final StreamController<List<MensajeMesh>> _controller =
      StreamController<List<MensajeMesh>>.broadcast();

  static Future<void> Function(MensajeMesh paquete)? onReenviarPaquete;

  static List<MensajeMesh> get mensajes => List.unmodifiable(_mensajes);
  static Stream<List<MensajeMesh>> get streamMensajes => _controller.stream;

  static bool yaFueVisto(String id) => _idsVistos.contains(id);

  static void publicarAvisoSistema(String texto) {
    final aviso = MensajeMesh(
      id: 'sys_${DateTime.now().microsecondsSinceEpoch}',
      autor: 'SISTEMA // BLE',
      texto: texto,
      ttl: 0,
      timestamp: DateTime.now(),
    );
    _mensajes.insert(0, aviso);
    _controller.add(List.unmodifiable(_mensajes));
  }

  static Future<void> publicarMensajeLocal({
    required String autor,
    required String texto,
    required int ttlInicial,
    String? gps,
    bool esPrivado = false,
    String claveGrupo = '',
  }) async {
    final idUnico =
        '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';
    _idsVistos.add(idUnico);

    // Mensaje visible localmente en nuestra pantalla (texto plano)
    final msgLocal = MensajeMesh(
      id: idUnico,
      autor: autor,
      texto: texto,
      ttl: ttlInicial,
      saltosRecorridos: 0,
      timestamp: DateTime.now(),
      gps: gps,
      esPrivado: esPrivado && claveGrupo.trim().isNotEmpty,
    );

    _mensajes.insert(0, msgLocal);
    _controller.add(List.unmodifiable(_mensajes));

    // Paquete que viajará por la radio BLE (cifrado si es privado)
    MensajeMesh paqueteTransmision = msgLocal;
    if (esPrivado && claveGrupo.trim().isNotEmpty) {
      try {
        final sobreSecreto = jsonEncode({
          't': texto,
          'g': ?gps,
        });
        final cifrado = await _cryptoChannel.invokeMethod<String>('cifrarAes', {
          'texto': sobreSecreto,
          'clave': claveGrupo.trim(),
        });
        if (cifrado != null && cifrado.startsWith('ENC:v1:')) {
          paqueteTransmision = MensajeMesh(
            id: idUnico,
            autor: autor,
            texto: cifrado,
            ttl: ttlInicial,
            saltosRecorridos: 0,
            timestamp: msgLocal.timestamp,
            gps: null, // Ocultamos el GPS en cabecera abierta
            esPrivado: true,
          );
        }
      } catch (_) {}
    }

    if (onReenviarPaquete != null && ttlInicial > 0) {
      await onReenviarPaquete!(paqueteTransmision);
    }
  }

  static Future<void> recibirPaqueteExterno(Map<String, dynamic> json) async {
    final incoming = MensajeMesh.fromJson(json);
    if (incoming.id.isEmpty || _idsVistos.contains(incoming.id)) {
      return;
    }
    _idsVistos.add(incoming.id);

    // 1. Retransmisión ciega (Blind Relay) para mantener la malla unida
    if (incoming.ttl > 1 && onReenviarPaquete != null) {
      final reenvio = MensajeMesh(
        id: incoming.id,
        autor: incoming.autor,
        texto: incoming.texto,
        ttl: incoming.ttl - 1,
        saltosRecorridos: incoming.saltosRecorridos + 1,
        timestamp: incoming.timestamp,
        gps: incoming.gps,
      );
      await onReenviarPaquete!(reenvio);
    }

    // 2. Si viene cifrado con AES-256, intentamos descifrarlo con nuestra clave
    if (incoming.texto.startsWith('ENC:v1:')) {
      final cfg = await NodoConfigService.cargar();
      if (cfg.claveGrupo.trim().isEmpty) {
        return; // No tenemos clave configurada: descartamos silenciosamente
      }
      try {
        final plano = await _cryptoChannel.invokeMethod<String>('descifrarAes', {
          'payload': incoming.texto,
          'clave': cfg.claveGrupo.trim(),
        });
        if (plano == null || plano.isEmpty) {
          return; // Clave distinta (pertenece a otro grupo): descartamos
        }
        final datos = jsonDecode(plano) as Map<String, dynamic>;
        final msgDescifrado = MensajeMesh(
          id: incoming.id,
          autor: incoming.autor,
          texto: datos['t']?.toString() ?? '',
          ttl: incoming.ttl,
          saltosRecorridos: incoming.saltosRecorridos,
          timestamp: incoming.timestamp,
          gps: datos['g']?.toString(),
          esPrivado: true,
        );
        _mensajes.insert(0, msgDescifrado);
        _controller.add(List.unmodifiable(_mensajes));
      } catch (_) {}
      return;
    }
     // 2.5 Inventario cartográfico silencioso (Mapas, Red Vial, Waypoints)
     if (incoming.texto.startsWith('SYNC_MAP:')) {
      final cfg = await NodoConfigService.cargar();
      await SyncCartografiaService.procesarInventarioRecibido(
        incoming.autor,
        incoming.texto,
        cfg,
      );
      return;
    }
    

    // 3. Mensaje abierto comunitario
    _mensajes.insert(0, incoming);
    _controller.add(List.unmodifiable(_mensajes));
  }
}
