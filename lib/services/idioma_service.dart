import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

class IdiomaService {
  static String? _idiomaForzado;

  static bool get esEspanol {
    if (_idiomaForzado != null) return _idiomaForzado == 'es';
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return code == 'es';
  }

  static String get codigoActual => _idiomaForzado ?? 'auto';
  static Future<void> cargarPreferencia() async {
  final prefs = await SharedPreferences.getInstance();
  final guardado = prefs.getString('aegis_idioma');
  _idiomaForzado = (guardado == 'es' || guardado == 'en') ? guardado : null;
  }
  static Future<void> establecerIdioma(String? codigo) async {
  final prefs = await SharedPreferences.getInstance();
  if (codigo == 'es' || codigo == 'en') {
    _idiomaForzado = codigo;
    await prefs.setString('aegis_idioma', codigo!);
    } else {
    _idiomaForzado = null;
    await prefs.remove('aegis_idioma');
    }
  }

  static String t(String clave) {
    final mapa = esEspanol ? _es : _en;
    return mapa[clave] ?? _es[clave] ?? clave;
  }

  static const Map<String, String> _es = {
    // Navegación principal
    'tab_nodo': 'Nodo',
    'tab_manuales': 'Manuales',
    'tab_mapas': 'Mapas',
    'tab_wiki': 'Wiki ZIM',
    'tab_preparar': 'Preparar',

    // Pantalla Nodo
    'sin_alias': 'SIN ALIAS',
    'maestro': 'MAESTRO',
    'repetidor': 'REPETIDOR',
    'ble_activa': 'Malla BLE Activa • Vecinos:',
    'ver_radar': 'Ver radar ▸',
    'ble_apagada': 'Malla BLE Apagada (Ahorro máximo)',
    'sos_activo_corto': 'ACTIVO',
    'sos_tip': 'Mantén presionado el botón SOS 2 segundos para emitir alerta de emergencia.',
    'sos_apagado_aviso': 'Baliza SOS desactivada.',
    'portal_wifi': 'Portal Web Wi-Fi (Opcional / Archivos)',
    'canal_abierto': 'CANAL ABIERTO',
    'grupo_privado': 'GRUPO PRIVADO',
    'chat_desactivado': 'Chat desactivado en Configuración del Nodo',
    'sin_msgs_privado': 'Sin mensajes cifrados en este grupo.\nComparte la misma Clave AES-256 con tu equipo.',
    'sin_msgs_abierto': 'Sin mensajes en la malla.\nEnciende BLE o Wi-Fi para comunicarte.',
    'hint_mensaje': 'Mensaje de emergencia a la malla...',
    'nota_voz_ptt': 'NOTA DE VOZ PTT (4s)',
    'ver_en_mapa': '(Tocar para ver en mapa)',
    'saltos_label': 'Saltos',
    'aviso_alias': 'Configura tu indicativo o alias antes de enviar mensajes.',
    'sos_cuerpo': '🚨 [BALIZA SOS] • REQUIERO ASISTENCIA INMEDIATA',
    'radar_fuerte': 'Señal Fuerte (Cerca)',
    'radar_media': 'Señal Media',
    'radar_debil': 'Señal Débil (Al límite)',
    'radar_visto': 'Visto hace',
    'oferta_titulo': '🗺️ MAPAS / RUTAS DISPONIBLES EN',
    'oferta_desc': 'Activa el Portal Web Wi-Fi en el equipo emisor y toca para instalar directo:',
    'descargar_btn': 'Descargar',
    'descargando_btn': 'Descargando',
    'tip_dead_drop': 'Dejar Dead Drop (Buzón Muerto)',
    'tip_pin': 'Fijar como importante para sincronización',

    //DescargasScreen
    'prep_titulo_sec': 'SELECCIONA EL TIPO DE RECURSO A PREPARAR',
    'cat_mapas': 'Mapas',
    'cat_wikis': 'Wikis ZIM',
    'cat_manuales': 'Manuales PDF',
    'url_opcional': 'URL directa opcional...',
    'tip_url': 'Descargar URL personalizada',
    'sec_mapas_gps': 'SUGERENCIAS DE MAPAS (SEGÚN TU GPS:',
    'sec_wikis': 'ENCICLOPEDIAS ZIM',
    'sec_manuales': 'MANUALES TÉCNICOS Y DE EMERGENCIA (PDF)',
    'btn_explorar_mapas': 'EXPLORAR POR CONTINENTE / PAÍS / PROVINCIA / CIUDAD',
    'red_vial_titulo': 'RED VIAL OFFLINE (RUTAS POR CALLES)',
    'red_vial_desc': 'Descarga las calles y caminos (45 km alrededor de tu GPS) para calcular rutas esquina por esquina sin Internet.',
    'btn_descargando_calles': 'DESCARGANDO CALLES (45 KM)...',
    'btn_descargar_calles': 'DESCARGAR RED VIAL (45 KM)',
    'btn_buscar_manuales': 'BUSCAR MANUALES LIBRES EN BASE MUNDIAL (PDF)',
    'hint_kiwix': 'Buscar tema en catálogo Kiwix (ej. electrónica, física)...',
    'badge_tu_zona': 'TU ZONA GPS',


    // Dead Drop y Radar en Nodo
    'dead_drop_titulo': '📦 BUZÓN MUERTO (DEAD DROP)',
    'dead_drop_desc': 'Guarda un paquete en este nodo. Cuando el destinatario pase en rango BLE, se entregará automáticamente.',
    'dead_drop_dest': 'Alias Destinatario (vacío = cualquier vecino)',
    'dead_drop_msg': 'Mensaje táctico o instrucciones...',
    'dead_drop_cifrar': 'Cifrar con clave de grupo AES-256',
    'dead_drop_guardar': 'GUARDAR EN BUZÓN',
    'radar_titulo': 'RADAR DE NODOS VECINOS (BLE)',
    'radar_vacio': 'Ningún nodo vecino detectado en los últimos 25 segundos.',

    // Configuración Nodo
    'config_nodo': 'CONFIGURACIÓN Y PRIVACIDAD DEL NODO',
    'alias_label': 'Indicativo / Alias de Usuario',
    'clave_grupo': 'Clave de Grupo AES-256 (Opcional)',
    'clave_grupo_hint': 'Vacío = solo canal abierto comunitario',
    'rol_maestro': 'Rol: Nodo Maestro (Punto de Mando)',
    'rol_maestro_sub': 'Coordina red y difusión',
    'rol_repetidor_sub': 'Modo Repetidor / Campo (Reenvía saltos)',
    'ttl_max': 'Saltos máximos en Malla (TTL):',
    'perfil_energia': 'Perfil de Energía (Ahorro de Batería):',
    'energia_ultra': 'Ultra-Ahorro (Escucha cada 45s)',
    'energia_eq': 'Equilibrado (Escucha cada 12s)',
    'energia_rescate': 'Rescate Activo (Continuo)',
    'cfg_chat': 'Activar Chat de Emergencia',
    'cfg_gps': 'Compartir mi Ubicación GPS',
    'cfg_gps_sub': 'Adjunta coordenadas a tus mensajes',
    'cfg_wifi_files': 'Compartir Archivos en Portal Wi-Fi',
    'cfg_notif': 'Notificar mensajes entrantes',
    'cfg_notif_sub': 'Emite alerta en segundo plano al recibir',
    'cfg_sync_mapas': 'Compartir Mapas y Red Vial en Malla',
    'cfg_sync_mapas_sub': 'Avisa a vecinos qué mapas y calles offline tienes',
    'cfg_sync_wp': 'Compartir mis Waypoints Personales',
    'cfg_sync_wp_sub': 'Desactivado por defecto para proteger tus ubicaciones',
    'guardar_cfg': 'GUARDAR CONFIGURACIÓN',
    'cancelar': 'Cancelar',

    // Pantalla Manuales
    'buscar_pdf': 'Buscar manual PDF...',
    'sin_pdf': 'Sin manuales PDF instalados.\nImporta archivos desde tu teléfono para leerlos sin conexión.',
    'importar_pdf': 'Importar archivos .PDF',

    // Pantalla Mapas
    'gps_espera': 'GPS en espera',
    'sin_mapas': 'Sin mapas offline cargados',
    'sin_mapas_desc': 'Descarga mapas en la pestaña Preparar o importa archivos .mbtiles desde tu teléfono.',
    'importar_mapas': 'Importar mapas .mbtiles',
    'rastros_gpx': 'RASTROS GPX GUARDADOS',

    // Pantalla Wiki
    'sin_zim': 'Sin archivos .ZIM instalados',
    'sin_zim_desc': 'Descarga paquetes en la pestaña Preparar o importa archivos .ZIM desde tu teléfono.',
    'importar_zim': 'Importar archivos .ZIM',
    'recargar_carpeta': 'Recargar carpeta',
    'buscar_tema': 'Buscar tema en',
        // Importadores y avisos en Manuales, Mapas y Wiki
    'imp_pdf_titulo': 'IMPORTANDO MANUALES PDF',
    'imp_copiando': 'Copiando',
    'imp_de': 'de',
    'imp_archivos': 'archivos...',
    'imp_pdf_ok': 'manual(es) PDF importados correctamente.',
    'imp_pdf_err': 'No seleccionaste archivos .pdf válidos',
    'imp_zim_titulo': 'IMPORTANDO ENCICLOPEDIAS ZIM',
    'imp_zim_ok': 'enciclopedia(s) .zim importadas y listas.',
    'imp_zim_err': 'No seleccionaste archivos .zim válidos',
    'imp_map_titulo': 'IMPORTANDO CARTOGRAFÍA',
    'imp_map_ok': 'archivo(s) cartográficos importados.',
    'imp_map_err': 'Selecciona archivos .mbtiles, red_vial.json, waypoints.json o .gpx',

    // Diálogos de Waypoints y Rastros en Mapas
    'wp_nuevo_titulo': 'NUEVO WAYPOINT TÁCTICO',
    'wp_nombre_hint': 'Nombre (ej. Campamento, Agua, Peligro)',
    'wp_tipo_base': '🏕️ Campamento / Base',
    'wp_tipo_agua': '💧 Agua Potable / Recurso',
    'wp_tipo_peligro': '⚠️ Peligro / Zona Bloqueada',
    'wp_tipo_auxilio': '🏥 Punto Médico / Auxilio',
    'wp_coords': 'Coordenadas:',
    'wp_guiar': 'GUIAR DESDE MI UBICACIÓN',
    'wp_transmitir': 'TRANSMITIR WAYPOINT A LA MALLA BLE',
    'wp_transmitido_ok': 'Waypoint transmitido a la malla.',
    'wp_eliminar': 'Eliminar Marcador',
    'gpx_renombrar': 'RENOMBRAR RASTRO GPX',
    'gpx_nuevo_nombre': 'Nuevo nombre del recorrido',
    'gpx_vacio': 'Aún no has grabado ningún rastro GPX.\nUsa el botón circular cian arriba para empezar a grabar tu recorrido.',
    'gpx_puntos': 'puntos registrados',
    'gpx_guardado_ok': 'Rastro GPX guardado',

    // Exploradores y Visor PDF
    'exp_mapas_titulo': 'EXPLORADOR MUNDIAL DE MAPAS',
    'exp_pdf_titulo': 'BUSCADOR DE MANUALES LIBRES (PDF)',
    'exp_pdf_hint': 'Buscar manual (ej. primeros auxilios, radio, solar)...',
    'visor_pagina': 'Página',
    'exp_mapas_hint': 'Buscar ciudad entre +30.000 localidades...',
    'exp_mapas_mundial': 'Mapa Mundial Base (Zoom 0–5)',
    'exp_mapas_mundial_sub': 'Cobertura global de continentes, países y capitales',
    'exp_mapas_tu_gps': 'TU UBICACIÓN GPS',
    'exp_mapas_calle': 'Nivel Calle Z10–15',
    'exp_pdf_buscar_btn': 'Buscar',
    'exp_pdf_vacio': 'Escribe un tema técnico o de emergencia',
  };

  static const Map<String, String> _en = {
    // Main Navigation
    'tab_nodo': 'Node',
    'tab_manuales': 'Manuals',
    'tab_mapas': 'Maps',
    'tab_wiki': 'Wiki ZIM',
    'tab_preparar': 'Prepare',

    // Node Screen
    'sin_alias': 'NO ALIAS',
    'maestro': 'MASTER',
    'repetidor': 'REPEATER',
    'ble_activa': 'BLE Mesh Active • Peers:',
    'ver_radar': 'Radar ▸',
    'ble_apagada': 'BLE Mesh Off (Max battery saver)',
    'sos_activo_corto': 'ACTIVE',
    'sos_tip': 'Hold the SOS button for 2 seconds to broadcast an emergency beacon.',
    'sos_apagado_aviso': 'SOS beacon deactivated.',
    'portal_wifi': 'Wi-Fi Web Portal (Optional / Files)',
    'canal_abierto': 'OPEN CHANNEL',
    'grupo_privado': 'PRIVATE GROUP',
    'chat_desactivado': 'Chat disabled in Node Settings',
    'sin_msgs_privado': 'No encrypted messages in this group.\nShare the same AES-256 key with your team.',
    'sin_msgs_abierto': 'No mesh messages yet.\nTurn on BLE or Wi-Fi to communicate.',
    'hint_mensaje': 'Emergency mesh message...',
    'nota_voz_ptt': 'PTT VOICE NOTE (4s)',
    'ver_en_mapa': '(Tap to view on map)',
    'saltos_label': 'Hops',
    'aviso_alias': 'Set your callsign or alias before sending messages.',
    'sos_cuerpo': '🚨 [SOS BEACON] • IMMEDIATE ASSISTANCE REQUIRED',
    'radar_fuerte': 'Strong Signal (Close)',
    'radar_media': 'Medium Signal',
    'radar_debil': 'Weak Signal (At limit)',
    'radar_visto': 'Seen',
    'oferta_titulo': '🗺️ MAPS / ROUTES AVAILABLE ON',
    'oferta_desc': 'Enable Wi-Fi Web Portal on the sender device and tap to install directly:',
    'descargar_btn': 'Download',
    'descargando_btn': 'Downloading',
    'tip_dead_drop': 'Leave Dead Drop (Mailbox)',
    'tip_pin': 'Pin as important for sync',

    //DownloadScreen
    'prep_titulo_sec': 'SELECT RESOURCE TYPE TO PREPARE',
    'cat_mapas': 'Maps',
    'cat_wikis': 'ZIM Wikis',
    'cat_manuales': 'PDF Manuals',
    'url_opcional': 'Optional direct URL...',
    'tip_url': 'Download custom URL',
    'sec_mapas_gps': 'MAP SUGGESTIONS (BASED ON GPS:',
    'sec_wikis': 'ZIM ENCYCLOPEDIAS',
    'sec_manuales': 'TECHNICAL & EMERGENCY MANUALS (PDF)',
    'btn_explorar_mapas': 'BROWSE BY CONTINENT / COUNTRY / STATE / CITY',
    'red_vial_titulo': 'OFFLINE ROAD NETWORK (STREET ROUTING)',
    'red_vial_desc': 'Download streets and roads (45 km around your GPS) for turn-by-turn offline routing.',
    'btn_descargando_calles': 'DOWNLOADING ROADS (45 KM)...',
    'btn_descargar_calles': 'DOWNLOAD ROAD NETWORK (45 KM)',
    'btn_buscar_manuales': 'SEARCH FREE MANUALS IN GLOBAL REPO (PDF)',
    'hint_kiwix': 'Search Kiwix catalog (e.g. electronics, physics)...',
    'badge_tu_zona': 'YOUR GPS ZONE',

    // Dead Drop & Radar
    'dead_drop_titulo': '📦 DEAD DROP MAILBOX',
    'dead_drop_desc': 'Store a packet on this node. When the recipient comes within BLE range, it will be delivered automatically.',
    'dead_drop_dest': 'Recipient Alias (empty = any peer)',
    'dead_drop_msg': 'Tactical message or instructions...',
    'dead_drop_cifrar': 'Encrypt with AES-256 group key',
    'dead_drop_guardar': 'STORE IN DEAD DROP',
    'radar_titulo': 'NEARBY PEERS RADAR (BLE)',
    'radar_vacio': 'No peer nodes detected in the last 25 seconds.',

    // Node Settings
    'config_nodo': 'NODE SETTINGS & PRIVACY',
    'alias_label': 'User Callsign / Alias',
    'clave_grupo': 'AES-256 Group Key (Optional)',
    'clave_grupo_hint': 'Empty = open community channel only',
    'rol_maestro': 'Role: Master Node (Command Point)',
    'rol_maestro_sub': 'Coordinates network and broadcasts',
    'rol_repetidor_sub': 'Repeater / Field Mode (Relays hops)',
    'ttl_max': 'Max Mesh Hops (TTL):',
    'perfil_energia': 'Power Profile (Battery Saver):',
    'energia_ultra': 'Ultra-Saver (Scans every 45s)',
    'energia_eq': 'Balanced (Scans every 12s)',
    'energia_rescate': 'Active Rescue (Continuous)',
    'cfg_chat': 'Enable Emergency Chat',
    'cfg_gps': 'Share my GPS Location',
    'cfg_gps_sub': 'Attaches coordinates to your messages',
    'cfg_wifi_files': 'Share Files on Wi-Fi Portal',
    'cfg_notif': 'Notify incoming messages',
    'cfg_notif_sub': 'Alerts in background when receiving',
    'cfg_sync_mapas': 'Share Maps & Road Network on Mesh',
    'cfg_sync_mapas_sub': 'Notifies peers of available offline maps and roads',
    'cfg_sync_wp': 'Share my Personal Waypoints',
    'cfg_sync_wp_sub': 'Disabled by default to protect your locations',
    'guardar_cfg': 'SAVE SETTINGS',
    'cancelar': 'Cancel',

    // Manuals Screen
    'buscar_pdf': 'Search PDF manual...',
    'sin_pdf': 'No PDF manuals installed.\nImport files from your phone to read offline.',
    'importar_pdf': 'Import .PDF files',

    // Maps Screen
    'gps_espera': 'Waiting for GPS',
    'sin_mapas': 'No offline maps loaded',
    'sin_mapas_desc': 'Download maps in the Prepare tab or import .mbtiles files from your phone.',
    'importar_mapas': 'Import .mbtiles maps',
    'rastros_gpx': 'SAVED GPX TRACKS',

    // Wiki Screen
    'sin_zim': 'No .ZIM files installed',
    'sin_zim_desc': 'Download packages in the Prepare tab or import .ZIM files from your phone.',
    'importar_zim': 'Import .ZIM files',
    'recargar_carpeta': 'Reload folder',
    'buscar_tema': 'Search topic in',

        // Importers & alerts in Manuals, Maps, and Wiki
    'imp_pdf_titulo': 'IMPORTING PDF MANUALS',
    'imp_copiando': 'Copying',
    'imp_de': 'of',
    'imp_archivos': 'files...',
    'imp_pdf_ok': 'PDF manual(s) imported successfully.',
    'imp_pdf_err': 'No valid .pdf files selected',
    'imp_zim_titulo': 'IMPORTING ZIM ENCYCLOPEDIAS',
    'imp_zim_ok': '.zim encyclopedia(s) imported and ready.',
    'imp_zim_err': 'No valid .zim files selected',
    'imp_map_titulo': 'IMPORTING CARTOGRAPHY',
    'imp_map_ok': 'cartographic file(s) imported.',
    'imp_map_err': 'Select .mbtiles, red_vial.json, waypoints.json, or .gpx files',

    // Waypoint & GPX Dialogs in Maps
    'wp_nuevo_titulo': 'NEW TACTICAL WAYPOINT',
    'wp_nombre_hint': 'Name (e.g. Basecamp, Water, Hazard)',
    'wp_tipo_base': '🏕️ Basecamp / Shelter',
    'wp_tipo_agua': '💧 Drinking Water / Resource',
    'wp_tipo_peligro': '⚠️ Hazard / Blocked Area',
    'wp_tipo_auxilio': '🏥 Medical / Aid Point',
    'wp_coords': 'Coordinates:',
    'wp_guiar': 'NAVIGATE FROM MY LOCATION',
    'wp_transmitir': 'BROADCAST WAYPOINT TO BLE MESH',
    'wp_transmitido_ok': 'Waypoint broadcast to mesh.',
    'wp_eliminar': 'Delete Marker',
    'gpx_renombrar': 'RENAME GPX TRACK',
    'gpx_nuevo_nombre': 'New track name',
    'gpx_vacio': 'No GPX tracks recorded yet.\nTap the cyan record button above to start logging your path.',
    'gpx_puntos': 'points logged',
    'gpx_guardado_ok': 'GPX track saved',

    // Explorers & PDF Viewer
    'exp_mapas_titulo': 'GLOBAL OFFLINE MAP EXPLORER',
    'exp_pdf_titulo': 'FREE MANUALS SEARCH (PDF)',
    'exp_pdf_hint': 'Search manual (e.g. first aid, radio, solar)...',
    'visor_pagina': 'Page',
    'exp_mapas_hint': 'Search city among +30,000 locations...',
    'exp_mapas_mundial': 'Base World Map (Zoom 0-5)',
    'exp_mapas_mundial_sub': 'Global coverage of continents, countries, and capitals',
    'exp_mapas_tu_gps': 'YOUR GPS LOCATION',
    'exp_mapas_calle': 'Street Level Z10-15',
    'exp_pdf_buscar_btn': 'Search',
    'exp_pdf_vacio': 'Type a technical or emergency topic',
  };
}
