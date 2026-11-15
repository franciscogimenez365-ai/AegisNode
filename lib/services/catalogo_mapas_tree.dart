import 'package:dio/dio.dart';

class NodoGeografico {
  final String nombre;
  final String nivel; // 'Continente', 'País', 'Provincia', 'Ciudad'
  final List<double>? bbox; // [minLat, maxLat, minLon, maxLon] si es descargable
  final int minZoom;
  final int maxZoom;
  final List<NodoGeografico> hijos;

  const NodoGeografico({
    required this.nombre,
    required this.nivel,
    this.bbox,
    this.minZoom = 10,
    this.maxZoom = 15,
    this.hijos = const [],
  });
}

class CatalogoMapasTree {
  static final Dio _dio = Dio(BaseOptions(
    headers: {'User-Agent': 'PocketAEGIS-EmergencyApp/1.0'},
  ));

  // Busca cualquier ciudad/pueblo del mundo en OpenStreetMap Nominatim
  static Future<List<NodoGeografico>> buscarCiudadGlobal(String query) async {
    if (query.trim().length < 3) return [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'limit': '8',
    });
    final res = await _dio.get<List<dynamic>>(uri.toString());
    final lista = res.data ?? [];

    return lista.map((item) {
      final bb = (item['boundingbox'] as List<dynamic>)
          .map((e) => double.tryParse(e.toString()) ?? 0.0)
          .toList();
      // Nominatim devuelve [minLat, maxLat, minLon, maxLon]
      return NodoGeografico(
        nombre: item['display_name'].toString().split(',').take(3).join(','),
        nivel: 'Ciudad / Zona GPS',
        bbox: bb.length == 4 ? bb : null,
        minZoom: 10,
        maxZoom: 15,
      );
    }).where((n) => n.bbox != null).toList();
  }

  static const List<NodoGeografico> arbolMundial = [
    NodoGeografico(
      nombre: 'Mapa Mundial Base (Zoom 0–5)',
      nivel: 'Global',
      bbox: [-85.0, 85.0, -180.0, 180.0],
      minZoom: 0,
      maxZoom: 5,
    ),
    NodoGeografico(
      nombre: 'Sudamérica',
      nivel: 'Continente',
      hijos: [
        NodoGeografico(
          nombre: 'Argentina',
          nivel: 'País',
          bbox: [-55.0, -21.8, -73.5, -53.6],
          minZoom: 4,
          maxZoom: 8,
          hijos: [
            NodoGeografico(
              nombre: 'Buenos Aires (Provincia y CABA)',
              nivel: 'Provincia',
              hijos: [
                NodoGeografico(
                  nombre: 'AMBA y CABA (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-34.92, -34.42, -58.78, -58.18],
                ),
                NodoGeografico(
                  nombre: 'La Plata y Alrededores (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-35.02, -34.82, -58.10, -57.85],
                ),
                NodoGeografico(
                  nombre: 'Mar del Plata (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-38.12, -37.90, -57.68, -57.50],
                ),
                NodoGeografico(
                  nombre: 'Bahía Blanca (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-38.80, -38.65, -62.35, -62.18],
                ),
              ],
            ),
            NodoGeografico(
              nombre: 'Córdoba',
              nivel: 'Provincia',
              hijos: [
                NodoGeografico(
                  nombre: 'Córdoba Capital (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-31.50, -31.32, -64.30, -64.10],
                ),
                NodoGeografico(
                  nombre: 'Villa Carlos Paz y Punilla (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-31.48, -31.25, -64.55, -64.42],
                ),
              ],
            ),
            NodoGeografico(
              nombre: 'Santa Fe',
              nivel: 'Provincia',
              hijos: [
                NodoGeografico(
                  nombre: 'Rosario (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-33.05, -32.85, -60.75, -60.60],
                ),
                NodoGeografico(
                  nombre: 'Santa Fe Capital (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-31.68, -31.55, -60.76, -60.64],
                ),
              ],
            ),
            NodoGeografico(
              nombre: 'Mendoza',
              nivel: 'Provincia',
              hijos: [
                NodoGeografico(
                  nombre: 'Gran Mendoza (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-32.98, -32.82, -68.92, -68.76],
                ),
              ],
            ),
          ],
        ),
        NodoGeografico(
          nombre: 'Chile',
          nivel: 'País',
          hijos: [
            NodoGeografico(
              nombre: 'Región Metropolitana',
              nivel: 'Provincia',
              hijos: [
                NodoGeografico(
                  nombre: 'Santiago de Chile (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-33.58, -33.34, -70.78, -70.52],
                ),
              ],
            ),
          ],
        ),
        NodoGeografico(
          nombre: 'Uruguay',
          nivel: 'País',
          hijos: [
            NodoGeografico(
              nombre: 'Montevideo',
              nivel: 'Provincia',
              hijos: [
                NodoGeografico(
                  nombre: 'Montevideo Ciudad (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [-34.93, -34.80, -56.28, -56.05],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    NodoGeografico(
      nombre: 'Norteamérica',
      nivel: 'Continente',
      hijos: [
        NodoGeografico(
          nombre: 'México',
          nivel: 'País',
          hijos: [
            NodoGeografico(
              nombre: 'CDMX',
              nivel: 'Estado',
              hijos: [
                NodoGeografico(
                  nombre: 'Ciudad de México Centro (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [19.30, 19.50, -99.22, -99.05],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    NodoGeografico(
      nombre: 'Europa',
      nivel: 'Continente',
      hijos: [
        NodoGeografico(
          nombre: 'España',
          nivel: 'País',
          hijos: [
            NodoGeografico(
              nombre: 'Madrid',
              nivel: 'Comunidad',
              hijos: [
                NodoGeografico(
                  nombre: 'Madrid Centro (Nivel Calle)',
                  nivel: 'Ciudad',
                  bbox: [40.35, 40.48, -3.76, -3.62],
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ];
}
