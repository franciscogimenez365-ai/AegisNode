import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

enum PerfilEnergiaMesh {
  ultraAhorro, // Escucha 3s cada 45s (máxima autonomía)
  equilibrado, // Escucha 4s cada 12s (balanceado)
  rescateActivo, // Escucha continua (respuesta inmediata)
}

class NodoConfig {
  String alias;
  String claveGrupo;
  bool esMaestro;
  int ttlMaximo;
  PerfilEnergiaMesh perfilEnergia;
  bool chatActivo;
  bool compartirGps;
  bool compartirArchivos;
  bool permitirSubidaArchivos;
  bool notificarMensajes; // Apagado por defecto para evitar saturación en grupos grandes

  NodoConfig({
    this.alias = '',
    this.claveGrupo = '',
    this.esMaestro = true,
    this.ttlMaximo = 7,
    this.perfilEnergia = PerfilEnergiaMesh.equilibrado,
    this.chatActivo = true,
    this.compartirGps = false,
    this.compartirArchivos = true,
    this.permitirSubidaArchivos = false,
    this.notificarMensajes = false,
  });


  int get segundosDescansoRadio {
    switch (perfilEnergia) {
      case PerfilEnergiaMesh.ultraAhorro:
        return 45;
      case PerfilEnergiaMesh.equilibrado:
        return 12;
      case PerfilEnergiaMesh.rescateActivo:
        return 1;
    }
  }

  Map<String, dynamic> toJson() => {
        'alias': alias,
        'claveGrupo': claveGrupo,
        'esMaestro': esMaestro,
        'ttlMaximo': ttlMaximo,
        'perfilEnergia': perfilEnergia.index,
        'chatActivo': chatActivo,
        'compartirGps': compartirGps,
        'compartirArchivos': compartirArchivos,
        'permitirSubidaArchivos': permitirSubidaArchivos,
        'notificarMensajes': notificarMensajes,
      };

  factory NodoConfig.fromJson(Map<String, dynamic> json) {
    final idx = (json['perfilEnergia'] as int? ?? 1)
        .clamp(0, PerfilEnergiaMesh.values.length - 1);
    return NodoConfig(
      alias: json['alias']?.toString() ?? '',
      claveGrupo: json['claveGrupo']?.toString() ?? '',
      esMaestro: json['esMaestro'] as bool? ?? true,
      ttlMaximo: (json['ttlMaximo'] as int? ?? 7).clamp(1, 20),
      perfilEnergia: PerfilEnergiaMesh.values[idx],
      chatActivo: json['chatActivo'] as bool? ?? true,
      compartirGps: json['compartirGps'] as bool? ?? false,
      compartirArchivos: json['compartirArchivos'] as bool? ?? true,
      permitirSubidaArchivos: json['permitirSubidaArchivos'] as bool? ?? false,
      notificarMensajes: json['notificarMensajes'] as bool? ?? false,
    );
  }
}

class NodoConfigService {
  static Future<File> _archivoConfig() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/nodo_config.json');
  }

  static Future<NodoConfig> cargar() async {
    try {
      final f = await _archivoConfig();
      if (await f.exists()) {
        final mapa = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        return NodoConfig.fromJson(mapa);
      }
    } catch (_) {}
    return NodoConfig();
  }

  static Future<void> guardar(NodoConfig config) async {
    final f = await _archivoConfig();
    await f.writeAsString(jsonEncode(config.toJson()), flush: true);
  }
}
