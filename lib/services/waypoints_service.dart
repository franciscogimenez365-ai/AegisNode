import 'dart:convert';
import 'dart:io';

class WaypointTactico {
  final String id;
  final String nombre;
  final String tipo;
  final double lat;
  final double lon;

  WaypointTactico({
    required this.id,
    required this.nombre,
    required this.tipo,
    required this.lat,
    required this.lon,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nombre': nombre,
        'tipo': tipo,
        'lat': lat,
        'lon': lon,
      };

  factory WaypointTactico.fromJson(Map<String, dynamic> j) => WaypointTactico(
        id: j['id']?.toString() ?? '',
        nombre: j['nombre']?.toString() ?? 'Punto',
        tipo: j['tipo']?.toString() ?? 'base',
        lat: (j['lat'] as num?)?.toDouble() ?? 0.0,
        lon: (j['lon'] as num?)?.toDouble() ?? 0.0,
      );
}

class WaypointsService {
  static Future<List<WaypointTactico>> cargar(String rutaMapas) async {
    try {
      final file = File('$rutaMapas/waypoints.json');
      if (!await file.exists()) return [];
      final lista = jsonDecode(await file.readAsString()) as List<dynamic>;
      return lista
          .map((e) => WaypointTactico.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> guardarLista(
      String rutaMapas, List<WaypointTactico> waypoints) async {
    try {
      final file = File('$rutaMapas/waypoints.json');
      await file.writeAsString(
          jsonEncode(waypoints.map((w) => w.toJson()).toList()));
    } catch (_) {}
  }
}
