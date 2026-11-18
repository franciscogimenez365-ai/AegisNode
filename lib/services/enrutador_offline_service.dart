import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:latlong2/latlong.dart';

class ResultadoRuta {
  final List<LatLng> puntos;
  final bool esPorCalles;
  final String origenDato;

  ResultadoRuta({
    required this.puntos,
    required this.esPorCalles,
    required this.origenDato,
  });
}

class EnrutadorOfflineService {
  /// Descarga la red vial completa de 45 km a la redonda dividida en 4 cuadrantes
  static Future<bool> descargarRedVialLocal({
    required String rutaMapas,
    required double lat,
    required double lon,
    double radioKm = 45.0,
    void Function(String estado, double? progreso)? onProgreso,
  }) async {
    // Conversión de km a grados aproximados para armar la caja de 45 km a la redonda
    final dLat = radioKm / 111.32;
    final dLon = radioKm / (111.32 * cos(lat * pi / 180.0).abs().clamp(0.2, 1.0));

    final minLat = lat - dLat;
    final maxLat = lat + dLat;
    final minLon = lon - dLon;
    final maxLon = lon + dLon;

    // Dividimos el área total de 90x90 km en 4 cuadrantes para evitar límites de RAM en Overpass
    final cuadrantes = <List<double>>[
      [minLat, minLon, lat, lon], // Suroeste
      [minLat, lon, lat, maxLon], // Sureste
      [lat, minLon, maxLat, lon], // Noroeste
      [lat, lon, maxLat, maxLon], // Noreste
    ];

    final hosts = [
      'overpass-api.de',
      'overpass.kumi.systems',
      'lz4.overpass-api.de',
    ];

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 25),
      headers: {
        'User-Agent': 'AegisNode-OfflineStation/1.0.1',
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    ));

    final Map<String, List<double>> nodosTotales = {};
    final List<List<String>> viasTotales = [];

    for (int idx = 0; idx < cuadrantes.length; idx++) {
      final box = cuadrantes[idx];
      final bboxStr = '${box[0]},${box[1]},${box[2]},${box[3]}';
      final query = '''
[out:json][timeout:110];
(
  way["highway"~"motorway|trunk|primary|secondary|tertiary|unclassified|residential|track|path"]($bboxStr);
);
(._;>;);
out skel qt;
''';

      bool sectorOk = false;
      for (final host in hosts) {
        try {
          final baseProg = idx / cuadrantes.length;
          onProgreso?.call(
            'Sector ${idx + 1}/4 (${radioKm.round()} km): consultando $host...',
            baseProg,
          );

          final url = 'https://$host/api/interpreter';
          final res = await dio.post<String>(
            url,
            data: {'data': query},
            onReceiveProgress: (recibidos, total) {
              final mb = (recibidos / (1024 * 1024)).toStringAsFixed(2);
              final subProg = total > 0
                  ? (baseProg + (recibidos / total) * (1.0 / cuadrantes.length))
                      .clamp(0.0, 0.99)
                  : null;
              onProgreso?.call(
                'Sector ${idx + 1}/4: descargando calles ($mb MB)...',
                subProg,
              );
            },
          );

          if (res.statusCode != 200 || res.data == null) {
            continue;
          }

          onProgreso?.call(
            'Sector ${idx + 1}/4: indexando intersecciones...',
            (idx + 0.9) / cuadrantes.length,
          );

          final decoded = jsonDecode(res.data!) as Map<String, dynamic>;
          final elements = decoded['elements'] as List<dynamic>? ?? [];

          for (final el in elements) {
            final tipo = el['type'];
            if (tipo == 'node') {
              final id = el['id'].toString();
              final nLat = (el['lat'] as num).toDouble();
              final nLon = (el['lon'] as num).toDouble();
              nodosTotales[id] = [nLat, nLon];
            } else if (tipo == 'way') {
              final nds = (el['nodes'] as List<dynamic>?)
                      ?.map((n) => n.toString())
                      .toList() ??
                  [];
              if (nds.length >= 2) viasTotales.add(nds);
            }
          }

          sectorOk = true;
          break;
        } catch (_) {
          onProgreso?.call(
            'Sector ${idx + 1}/4: reintentando en servidor respaldo...',
            idx / cuadrantes.length,
          );
        }
      }

      if (!sectorOk) {
        onProgreso?.call(
          '⚠️ Falló el sector ${idx + 1}/4 en los servidores OSM. Intenta de nuevo.',
          null,
        );
        return false;
      }

      // Pequeña pausa de cortesía entre cuadrantes para evitar rate-limit HTTP 429
      if (idx < cuadrantes.length - 1) {
        await Future.delayed(const Duration(seconds: 2));
      }
    }

    if (nodosTotales.isEmpty || viasTotales.isEmpty) {
      onProgreso?.call('Sin calles registradas en esa zona.', null);
      return false;
    }

    onProgreso?.call('Guardando malla vial unificada de 45 km...', 0.98);
    final archivo = File('$rutaMapas/red_vial.json');
    await archivo.writeAsString(jsonEncode({
      'lat': lat,
      'lon': lon,
      'radioKm': radioKm,
      'nodos': nodosTotales,
      'vias': viasTotales,
    }));

    onProgreso?.call(
      '✅ Red vial 45 km lista (${nodosTotales.length} intersecciones)',
      1.0,
    );
    return true;
  }

  static Future<bool> existeRedVial(String rutaMapas) async {
    return File('$rutaMapas/red_vial.json').exists();
  }
  static double _distMetros(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180.0;
    final dLon = (lon2 - lon1) * pi / 180.0;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180.0) *
            cos(lat2 * pi / 180.0) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Calcula ruta calle por calle 100% OFFLINE (A*) o cae en línea directa si no hay calles
  static Future<ResultadoRuta> calcularRutaHibrida({
    required String rutaMapas,
    required LatLng origen,
    required LatLng destino,
  }) async {
    final archivo = File('$rutaMapas/red_vial.json');
    if (await archivo.exists()) {
      try {
        final raw =
            jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
        final nodosRaw = raw['nodos'] as Map<String, dynamic>;
        final viasRaw = raw['vias'] as List<dynamic>;

        final Map<String, LatLng> nodos = {};
        nodosRaw.forEach((k, v) {
          final arr = v as List<dynamic>;
          nodos[k] = LatLng(
              (arr.first as num).toDouble(), (arr.elementAt(1) as num).toDouble());
        });

        final Map<String, List<String>> adj = {};
        for (final v in viasRaw) {
          final lista = (v as List<dynamic>).map((e) => e.toString()).toList();
          for (int i = 0; i < lista.length - 1; i++) {
            final a = lista.elementAt(i);
            final b = lista.elementAt(i + 1);
            if (nodos.containsKey(a) && nodos.containsKey(b)) {
              adj.putIfAbsent(a, () => []).add(b);
              adj.putIfAbsent(b, () => []).add(a);
            }
          }
        }

        String? startId;
        String? goalId;
        double minStart = 2000.0;
        double minGoal = 2000.0;

        adj.forEach((id, _) {
          final pt = nodos[id]!;
          final dS = _distMetros(
              origen.latitude, origen.longitude, pt.latitude, pt.longitude);
          if (dS < minStart) {
            minStart = dS;
            startId = id;
          }
          final dG = _distMetros(
              destino.latitude, destino.longitude, pt.latitude, pt.longitude);
          if (dG < minGoal) {
            minGoal = dG;
            goalId = id;
          }
        });

        if (startId != null && goalId != null) {
          final camino = _ejecutarAStar(startId!, goalId!, nodos, adj);
          if (camino.isNotEmpty) {
            return ResultadoRuta(
              puntos: [origen, ...camino, destino],
              esPorCalles: true,
              origenDato: 'Red Vial Offline 45 km (A*)',
            );
          }
        }
      } catch (_) {}
    }

    return ResultadoRuta(
      puntos: [origen, destino],
      esPorCalles: false,
      origenDato: 'Directo por rumbo (fuera de red vial)',
    );
  }

  static List<LatLng> _ejecutarAStar(
    String start,
    String goal,
    Map<String, LatLng> nodos,
    Map<String, List<String>> adj,
  ) {
    final goalPt = nodos[goal]!;
    final Map<String, double> gScore = {start: 0.0};
    final Map<String, double> fScore = {
      start: _distMetros(nodos[start]!.latitude, nodos[start]!.longitude,
          goalPt.latitude, goalPt.longitude),
    };
    final Map<String, String> cameFrom = {};
    final SplayTreeSet<String> openSet = SplayTreeSet<String>((a, b) {
      final cmp =
          (fScore[a] ?? double.infinity).compareTo(fScore[b] ?? double.infinity);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    openSet.add(start);

    int iteraciones = 0;
    while (openSet.isNotEmpty && iteraciones < 150000) {
      iteraciones++;
      final current = openSet.first;
      if (current == goal) {
        final path = <LatLng>[];
        String? curr = current;
        while (curr != null) {
          path.add(nodos[curr]!);
          curr = cameFrom[curr];
        }
        return path.reversed.toList();
      }

      openSet.remove(current);
      final currPt = nodos[current]!;
      for (final neighbor in adj[current] ?? const <String>[]) {
        final nPt = nodos[neighbor]!;
        final tentativeG = (gScore[current] ?? double.infinity) +
            _distMetros(currPt.latitude, currPt.longitude, nPt.latitude,
                nPt.longitude);
        if (tentativeG < (gScore[neighbor] ?? double.infinity)) {
          openSet.remove(neighbor);
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeG;
          fScore[neighbor] = tentativeG +
              _distMetros(nPt.latitude, nPt.longitude, goalPt.latitude,
                  goalPt.longitude);
          openSet.add(neighbor);
        }
      }
    }
    return [];
  }
}
