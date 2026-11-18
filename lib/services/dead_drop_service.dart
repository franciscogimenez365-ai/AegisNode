import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'mesh_chat_service.dart';

class PaqueteDeadDrop {
  final String id;
  final String remitente;
  final String destinatarioAlias; // vacío si es para grupo cifrado
  final String texto;
  final String? gps;
  final bool esPrivado;
  final DateTime creadoEn;

  PaqueteDeadDrop({
    required this.id,
    required this.remitente,
    required this.destinatarioAlias,
    required this.texto,
    this.gps,
    this.esPrivado = false,
    required this.creadoEn,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'rem': remitente,
        'dest': destinatarioAlias,
        't': texto,
        if (gps != null) 'g': gps,
        'priv': esPrivado,
        'ts': creadoEn.millisecondsSinceEpoch,
      };

  factory PaqueteDeadDrop.fromJson(Map<String, dynamic> j) => PaqueteDeadDrop(
        id: j['id']?.toString() ?? '',
        remitente: j['rem']?.toString() ?? 'Nodo',
        destinatarioAlias: j['dest']?.toString() ?? '',
        texto: j['t']?.toString() ?? '',
        gps: j['g']?.toString(),
        esPrivado: j['priv'] == true,
        creadoEn: DateTime.fromMillisecondsSinceEpoch(
            (j['ts'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
      );
}

class DeadDropService {
  static final List<MensajeMesh> _importantes = [];
  static final List<PaqueteDeadDrop> _buzon = [];
  static bool _cargado = false;

  static List<MensajeMesh> get importantes => List.unmodifiable(_importantes);
  static List<PaqueteDeadDrop> get buzon => List.unmodifiable(_buzon);

  static Future<File> _archivo(String nombre) async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$nombre');
  }

  static Future<void> inicializar() async {
    if (_cargado) return;
    _cargado = true;
    try {
      final fImp = await _archivo('mensajes_importantes.json');
      if (await fImp.exists()) {
        final list = jsonDecode(await fImp.readAsString()) as List<dynamic>;
        _importantes.clear();
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          _importantes.add(MensajeMesh.fromJson(map));
        }
      }
      final fDrop = await _archivo('dead_drops.json');
      if (await fDrop.exists()) {
        final list = jsonDecode(await fDrop.readAsString()) as List<dynamic>;
        _buzon.clear();
        for (final item in list) {
          _buzon.add(PaqueteDeadDrop.fromJson(item as Map<String, dynamic>));
        }
      }
    } catch (_) {}
  }

  static bool esImportante(String id) => _importantes.any((m) => m.id == id);

  static Future<void> alternarImportante(MensajeMesh msg) async {
    await inicializar();
    final idx = _importantes.indexWhere((m) => m.id == msg.id);
    if (idx >= 0) {
      _importantes.removeAt(idx);
    } else {
      if (_importantes.length >= 50) _importantes.removeLast();
      _importantes.insert(0, msg);
    }
    await _guardarImportantes();
  }

  static Future<void> agregarDeadDrop(PaqueteDeadDrop drop) async {
    await inicializar();
    if (_buzon.any((d) => d.id == drop.id)) return;
    if (_buzon.length >= 40) _buzon.removeLast();
    _buzon.insert(0, drop);
    await _guardarBuzon();
  }

  static Future<void> _guardarImportantes() async {
    try {
      final f = await _archivo('mensajes_importantes.json');
      await f.writeAsString(
          jsonEncode(_importantes.map((m) => m.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> _guardarBuzon() async {
    try {
      final f = await _archivo('dead_drops.json');
      await f.writeAsString(jsonEncode(_buzon.map((d) => d.toJson()).toList()));
    } catch (_) {}
  }
}
