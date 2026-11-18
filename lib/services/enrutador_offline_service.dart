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
  /// Descarga la red de calles/caminos de OpenStreetMap con timeout largo y progreso real
  static Future<bool> descargarRedVialLocal({
    required String rutaMapas,
    required double lat,
    required double lon,
    double radioKm = 15.0,
    void Function(String estado, double? progreso)? onProgreso,
  }) async {
    final radioMetros = (radioKm * 1000).round();
    final query = '''
[out:json][timeout:110];
(
  way["highway"~"motorway|trunk|primary|secondary|tertiary|unclassified|residential|track|path"](around:$radioMetros,$lat,$lon);
);
(._;>;);
out skel qt;
''';

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

    for (final host in hosts) {
      try {
        onProgreso?.call(
          'Consultando $host (${radioKm.round()} km). El servidor puede tardar 15-45s...',
          null,
        );

        final url = 'https://$host/api/interpreter';
        final res = await dio.post<String>(
          url,
          data: {'data': query},
          onReceiveProgress: (recibidos, total) {
            final mb = (recibidos / (1024 * 1024)).toStringAsFixed(2);
            if (total > 0) {
              final pct = (recibidos / total).clamp(0.0, 1.0);
              onProgreso?.call(
                'Descargando calles: ${(pct * 100).toStringAsFixed(0)}% ($mb MB)',
                pct,
              );
            } else {
              onProgreso?.call('Descargando calles: $mb MB recibidos...', null);
            }
          },
        );

        if (res.statusCode != 200 || res.data == null) {
          onProgreso?.call(
            '$host respondió HTTP ${res.statusCode}, probando respaldo...',
            null,
          );
          continue;
        }

        onProgreso?.call('Indexando intersecciones para enrutamiento A*...', 1.0);
        final decoded = jsonDecode(res.data!) as Map<String, dynamic>;
        final elements = decoded['elements'] as List<dynamic>? ?? [];

        final Map<String, List<double>> nodos = {};
        final List<List<String>> vias = [];

        for (final el in elements) {
          final tipo = el['type'];
          if (tipo == 'node') {
            final id = el['id'].toString();
            final nLat = (el['lat'] as num).toDouble();
            final nLon = (el['lon'] as num).toDouble();
            nodos[id] = [nLat, nLon];
          } else if (tipo == 'way') {
            final nds = (el['nodes'] as List<dynamic>?)
                    ?.map((n) => n.toString())
                    .toList() ??
                [];
            if (nds.length >= 2) vias.add(nds);
          }
        }

        if (nodos.isEmpty || vias.isEmpty) {
          onProgreso?.call('Sin calles registradas en esa zona.', null);
          return false;
        }

        final archivo = File('$rutaMapas/red_vial.json');
        await archivo.writeAsString(jsonEncode({
          'lat': lat,
          'lon': lon,
          'radioKm': radioKm,
          'nodos': nodos,
          'vias': vias,
        }));

        onProgreso?.call(
          '✅ Red vial lista (${nodos.length} intersecciones indexadas)',
          1.0,
        );
        return true;
      } catch (e) {
        onProgreso?.call(
          'Error/Timeout en $host, probando servidor alternativo...',
          null,
        );
      }
    }

    onProgreso?.call(
      '⚠️ No se pudo completar la descarga en ninguno de los servidores OSM.',
      null,
    );
    return false;
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
        final raw = jsonDecode(await archivo.readAsString()) as Map<String, dynamic>;
        final nodosRaw = raw['nodos'] as Map<String, dynamic>;
        final viasRaw = raw['vias'] as List<dynamic>;

        final Map<String, LatLng> nodos = {};
        nodosRaw.forEach((k, v) {
          final arr = v as List<dynamic>;
          nodos[k] = LatLng((arr.first as num).toDouble(), (arr.elementAt(1) as num).toDouble());
        });

        // Construir grafo bidireccional
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

        // Buscar nodo vial más cercano al origen y al destino (máx 1.5 km)
        String? startId;
        String? goalId;
        double minStart = 1500.0;
        double minGoal = 1500.0;

        adj.forEach((id, _) {
          final pt = nodos[id]!;
          final dS = _distMetros(origen.latitude, origen.longitude, pt.latitude, pt.longitude);
          if (dS < minStart) {
            minStart = dS;
            startId = id;
          }
          final dG = _distMetros(destino.latitude, destino.longitude, pt.latitude, pt.longitude);
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
              origenDato: 'Red Vial Offline (A*)',
            );
          }
        }
      } catch (_) {}
    }

    // Respaldo: Línea directa por rumbo y distancia
    return ResultadoRuta(
      puntos: [origen, destino],
      esPorCalles: false,
      origenDato: 'Directo por rumbo (sin red vial)',
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
      start: _distMetros(nodos[start]!.latitude, nodos[start]!.longitude, goalPt.latitude, goalPt.longitude),
    };
    final Map<String, String> cameFrom = {};
    final SplayTreeSet<String> openSet = SplayTreeSet<String>((a, b) {
      final cmp = (fScore[a] ?? double.infinity).compareTo(fScore[b] ?? double.infinity);
      return cmp != 0 ? cmp : a.compareTo(b);
    });
    openSet.add(start);

    int iteraciones = 0;
    while (openSet.isNotEmpty && iteraciones < 35000) {
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
            _distMetros(currPt.latitude, currPt.longitude, nPt.latitude, nPt.longitude);
        if (tentativeG < (gScore[neighbor] ?? double.infinity)) {
          openSet.remove(neighbor);
          cameFrom[neighbor] = current;
          gScore[neighbor] = tentativeG;
          fScore[neighbor] = tentativeG +
              _distMetros(nPt.latitude, nPt.longitude, goalPt.latitude, goalPt.longitude);
          openSet.add(neighbor);
        }
      }
    }
    return [];
  }
}
