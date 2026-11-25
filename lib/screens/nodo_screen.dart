import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/ble_mesh_service.dart';
import '../services/mesh_chat_service.dart';
import '../services/nodo_config_service.dart';
import '../services/servidor_local.dart';
import '../services/dead_drop_service.dart';
import '../services/sync_cartografia_service.dart';
import '../services/idioma_service.dart';


class NodoScreen extends StatefulWidget {
  final String rutaBase;
  final void Function(double lat, double lon)? onAbrirCoordenada;
  final VoidCallback? onCambioIdioma;
  const NodoScreen({
    super.key,
    required this.rutaBase,
    this.onAbrirCoordenada,
    this.onCambioIdioma,
  });


  @override
  State<NodoScreen> createState() => _NodoScreenState();
}

class _NodoScreenState extends State<NodoScreen> {
  final ServidorLocalService _servidorWifi = ServidorLocalService();
  final TextEditingController _msgCtrl = TextEditingController();
  NodoConfig _config = NodoConfig();
  bool _bleActivo = false;
  bool _wifiActivo = false;
  bool _sosActivo = false;
  bool _grabandoPtt = false;
  bool _verCanalPrivado = false;
  Timer? _timerSos;
  final Map<String, double> _progresoDescargasVecino = {};

  static const MethodChannel _sysChannel =
      MethodChannel('com.emergencia.aegis_node/kiwix');


  @override
  void initState() {
    super.initState();
    _cargarConfig();
    DeadDropService.inicializar();
  }
    @override
  void dispose() {
    _timerSos?.cancel();
    _msgCtrl.dispose();
    super.dispose();
  }


  Future<void> _cargarConfig() async {
    final c = await NodoConfigService.cargar();
    if (mounted) setState(() => _config = c);
  }

  Future<void> _toggleMallaBle(bool activar) async {
    if (activar) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothAdvertise,
        Permission.bluetoothConnect,
        Permission.notification,
      ].request();

      await BleMeshService.iniciarMalla(_config);
    } else {
      await BleMeshService.detenerMalla();
    }
    if (mounted) setState(() => _bleActivo = activar);
  }

  Future<void> _togglePortalWifi(bool activar) async {
    if (activar) {
      await _servidorWifi.iniciarServidor(widget.rutaBase);
      await WakelockPlus.enable();
    } else {
      await _servidorWifi.detenerServidor();
      await WakelockPlus.disable();
    }
    if (mounted) setState(() => _wifiActivo = activar);
  }

  Future<void> _enviarMensaje() async {
    if (_config.alias.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Color(0xFFFF6D00),
          content: Text(
            IdiomaService.t('aviso_alias'),
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
      _abrirConfiguracionNodo();
      return;
    }

    final texto = _msgCtrl.text.trim();
    if (texto.isEmpty) return;
    _msgCtrl.clear();


    String? gpsStr;
    if (_config.compartirGps) {
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 3)),
        );
        gpsStr =
            '${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}';
      } catch (_) {}
    }

    await MeshChatService.publicarMensajeLocal(
      autor: _config.alias,
      texto: texto,
      ttlInicial: _config.ttlMaximo,
      gps: gpsStr,
      esPrivado: _verCanalPrivado && _config.claveGrupo.trim().isNotEmpty,
      claveGrupo: _config.claveGrupo,
    );
  }
    Future<void> _iniciarGrabacionPtt() async {
    if (_config.alias.trim().isEmpty) {
      _abrirConfiguracionNodo();
      return;
    }
    final status = await Permission.microphone.request();
    if (!status.isGranted) return;

    HapticFeedback.mediumImpact();
    try {
      final ok = await _sysChannel.invokeMethod<bool>('iniciarPtt') ?? false;
      if (ok && mounted) {
        setState(() => _grabandoPtt = true);
        // Corte automático a los 4 segundos para mantener el paquete ligero (~5 KB)
        Future.delayed(const Duration(seconds: 4), () {
          if (_grabandoPtt) _detenerYEnviarPtt();
        });
      }
    } catch (_) {}
  }

  Future<void> _detenerYEnviarPtt() async {
    if (!_grabandoPtt) return;
    setState(() => _grabandoPtt = false);
    HapticFeedback.lightImpact();

    try {
      final payloadPtt = await _sysChannel.invokeMethod<String>('detenerPtt');
      if (payloadPtt != null && payloadPtt.startsWith('PTT:v1:')) {
        await MeshChatService.publicarMensajeLocal(
          autor: _config.alias,
          texto: payloadPtt,
          ttlInicial: _config.ttlMaximo,
          esPrivado: _verCanalPrivado && _config.claveGrupo.trim().isNotEmpty,
          claveGrupo: _config.claveGrupo,
        );
      }
    } catch (_) {}
  }

  Future<void> _activarODetenerSos() async {
    if (_sosActivo) {
      _timerSos?.cancel();
      setState(() => _sosActivo = false);
      MeshChatService.publicarAvisoSistema(IdiomaService.t('sos_apagado_aviso'));
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() => _sosActivo = true);

    // Si la Malla BLE estaba apagada, la encendemos automáticamente
    if (!_bleActivo) {
      await _toggleMallaBle(true);
    }

    await _emitirPulsoSos();
    _timerSos = Timer.periodic(const Duration(minutes: 2), (_) {
      if (_sosActivo) _emitirPulsoSos();
    });
  }
    Future<void> _abrirDialogoDeadDrop() async {
    final destCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    bool soloGrupoPrivado =
        _verCanalPrivado && _config.claveGrupo.trim().isNotEmpty;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF121212),
          title: Text(IdiomaService.t('dead_drop_titulo'),
              style: TextStyle(color: Color(0xFFFF6D00), fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                IdiomaService.t('dead_drop_desc'),
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: destCtrl,
                decoration: InputDecoration(
                  labelText: IdiomaService.t('dead_drop_dest'),
                  filled: true,
                  fillColor: Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: msgCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: IdiomaService.t('dead_drop_msg'),
                  filled: true,
                  fillColor: Color(0xFF1A1A1A),
                ),
              ),
              if (_config.claveGrupo.trim().isNotEmpty)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text (IdiomaService.t('dead_drop_cifrar'),
                      style: TextStyle(fontSize: 12)),
                  value: soloGrupoPrivado,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) => setDlg(() => soloGrupoPrivado = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text (IdiomaService.t('cancelar'), style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00E676),
                  foregroundColor: Colors.black),
              onPressed: () async {
                final texto = msgCtrl.text.trim();
                if (texto.isEmpty) return;

                String payloadFinal = texto;
                if (soloGrupoPrivado && _config.claveGrupo.trim().isNotEmpty) {
                  try {
                    final sobre = jsonEncode({'t': texto});
                    final cifrado =
                        await _sysChannel.invokeMethod<String>('cifrarAes', {
                      'texto': sobre,
                      'clave': _config.claveGrupo.trim(),
                    });
                    if (cifrado != null) payloadFinal = cifrado;
                  } catch (_) {}
                }

                final nuevoDrop = PaqueteDeadDrop(
                  id: 'drop_${DateTime.now().microsecondsSinceEpoch}',
                  remitente: _config.alias.isEmpty ? 'Nodo' : _config.alias,
                  destinatarioAlias: destCtrl.text.trim(),
                  texto: payloadFinal,
                  esPrivado: soloGrupoPrivado,
                  creadoEn: DateTime.now(),
                );
                await DeadDropService.agregarDeadDrop(nuevoDrop);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                MeshChatService.publicarAvisoSistema(
                  '📦 Dead Drop guardado (${destCtrl.text.trim().isEmpty ? "Cualquier vecino" : "Para: ${destCtrl.text.trim()}"}).',
                );
              },
              child: Text(IdiomaService.t('dead_drop_guardar')),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _emitirPulsoSos() async {
    int bateria = -1;
    try {
      bateria = await _sysChannel.invokeMethod<int>('obtenerBateria') ?? -1;
    } catch (_) {}

    String? gpsStr;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      ).timeout(const Duration(seconds: 6));
      gpsStr =
          '${pos.latitude.toStringAsFixed(6)},${pos.longitude.toStringAsFixed(6)}';
    } catch (_) {}

    final aliasEfectivo =
        _config.alias.trim().isEmpty ? 'NODO-SOS' : _config.alias.trim();
    final batTexto = bateria >= 0 ? ' • BAT: $bateria%' : '';
    final cuerpoSos =
        '$batTexto ${IdiomaService.t('sos_cuerpo')}';
    await MeshChatService.publicarMensajeLocal(
      autor: aliasEfectivo,
      texto: cuerpoSos,
      ttlInicial: 20, // Máximo alcance posible en la malla
      gps: gpsStr,
    );

  }

  
  void _abrirConfiguracionNodo() {
    final aliasCtrl = TextEditingController(text: _config.alias);
    final claveCtrl = TextEditingController(text: _config.claveGrupo);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(IdiomaService.t('config_nodo'),
                    style: TextStyle(
                        color: Color(0xFFFF6D00), fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                TextField(
                  controller: aliasCtrl,
                  decoration: InputDecoration(
                    labelText: IdiomaService.t('alias_label'),
                    filled: true,
                    fillColor: Color(0xFF1A1A1A),
                  ),
                ),
             const SizedBox(height: 10),
             TextField(
               controller: claveCtrl,
               obscureText: true,
               decoration: InputDecoration(
                 labelText: IdiomaService.t('clave_grupo'),
                 hintText: IdiomaService.t('clave_grupo_hint'),
                 prefixIcon: Icon(Icons.lock_outline, color: Color(0xFF00E676)),
                 filled: true,
                 fillColor: Color(0xFF1A1A1A),
               ),
             ),
                const SizedBox(height: 12),
                Text(
                  IdiomaService.esEspanol
                      ? 'Idioma de la Aplicación:'
                      : 'App Language:',
                  style: const TextStyle(fontSize: 13),
                ),
                DropdownButton<String>(
                  value: IdiomaService.codigoActual,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(IdiomaService.esEspanol
                          ? 'Automático (Sistema)'
                          : 'Automatic (System)'),
                    ),
                    const DropdownMenuItem(
                      value: 'es',
                      child: Text('Español'),
                    ),
                    const DropdownMenuItem(
                      value: 'en',
                      child: Text('English'),
                    ),
                  ],
                  onChanged: (val) async {
                    if (val != null) {
                      await IdiomaService.establecerIdioma(val);
                      setModalState(() {});
                      if (mounted) setState(() {});
                      widget.onCambioIdioma?.call();
                    }
                  },
                ),
                SwitchListTile(
                  title:Text(IdiomaService.t('rol_maestro')),
                  subtitle: Text(_config.esMaestro
                      ? IdiomaService.t('rol_maestro_sub')
                      : IdiomaService.t('rol_repetidor_sub')),
                  value: _config.esMaestro,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) => setModalState(() => _config.esMaestro = v),
                ),
                Text('${IdiomaService.t('ttl_max')} ${_config.ttlMaximo}',
                    style: const TextStyle(fontSize: 13)),
                Slider(
                  value: _config.ttlMaximo.toDouble(),
                  min: 1,
                  max: 20,
                  divisions: 19,
                  activeColor: const Color(0xFFFF6D00),
                  label: '${_config.ttlMaximo} saltos',
                  onChanged: (v) =>
                      setModalState(() => _config.ttlMaximo = v.toInt()),
                ),
                 Text(IdiomaService.t('perfil_energia'),
                    style: TextStyle(fontSize: 13)),
                DropdownButton<PerfilEnergiaMesh>(
                  value: _config.perfilEnergia,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  items: [
                    DropdownMenuItem(
                        value: PerfilEnergiaMesh.ultraAhorro,
                        child: Text(IdiomaService.t('energia_ultra'))),
                    DropdownMenuItem(
                        value: PerfilEnergiaMesh.equilibrado,
                        child: Text(IdiomaService.t('energia_eq'))),
                    DropdownMenuItem(
                        value: PerfilEnergiaMesh.rescateActivo,
                        child: Text(IdiomaService.t('energia_rescate'))),
                  ],
                  onChanged: (p) {
                    if (p != null) {
                      setModalState(() => _config.perfilEnergia = p);
                    }
                  },
                ),
                const Divider(),
                SwitchListTile(
                  title: Text(IdiomaService.t('cfg_chat')),
                  value: _config.chatActivo,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) => setModalState(() => _config.chatActivo = v),
                ),
                SwitchListTile(
                  title: Text(IdiomaService.t('cfg_gps')),
                  subtitle: Text(IdiomaService.t('cfg_gps_sub')),
                  value: _config.compartirGps,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) =>
                      setModalState(() => _config.compartirGps = v),
                ),
                SwitchListTile(
                  title: Text(IdiomaService.t('cfg_wifi_files')),
                  value: _config.compartirArchivos,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) =>
                      setModalState(() => _config.compartirArchivos = v),
                ),
                SwitchListTile(
                  title:Text(IdiomaService.t('cfg_notif')),
                  subtitle: Text(IdiomaService.t('cfg_notif_sub')),
                  value: _config.notificarMensajes,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) =>
                     setModalState(() => _config.notificarMensajes = v),
                ),
                                SwitchListTile(
                  title: Text(IdiomaService.t('cfg_sync_mapas')),
                  subtitle: Text(
                      IdiomaService.t('cfg_sync_mapas_sub')),
                  value: _config.syncMapasYRutas,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (v) =>
                      setModalState(() => _config.syncMapasYRutas = v),
                ),
                SwitchListTile(
                  title: Text(IdiomaService.t('cfg_sync_wp')),
                  subtitle: Text(
                      IdiomaService.t('cfg_sync_wp_sub')),
                  value: _config.syncWaypointsPersonales,
                  activeThumbColor: const Color(0xFFFF6D00),
                  onChanged: (v) => setModalState(
                      () => _config.syncWaypointsPersonales = v),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black),
               onPressed: () async {
                 _config.alias = aliasCtrl.text.trim();
                 _config.claveGrupo = claveCtrl.text.trim();
                 if (_config.claveGrupo.isEmpty) _verCanalPrivado = false;
                 await NodoConfigService.guardar(_config);
                 if (_bleActivo) {
                   await BleMeshService.detenerMalla();
                   await BleMeshService.iniciarMalla(_config);
                 }
                 if (!ctx.mounted) return;
                 Navigator.pop(ctx);
                 setState(() {});
               },

                  child: Text(IdiomaService.t('guardar_cfg'),
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
    void _abrirRadarVecinos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF121212),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final vecinos = BleMeshService.listaVecinosActivos;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    IdiomaService.t('radar_titulo'),
                    style: TextStyle(
                      color: Color(0xFFFF6D00),
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  Text(
                    '${vecinos.length} activos',
                    style: const TextStyle(color: Color(0xFF00E676), fontSize: 12),
                  ),
                ],
              ),
              const Divider(color: Colors.grey),
              if (vecinos.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    (IdiomaService.t('radar_vacio')),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...vecinos.map((v) {
                  final haceSeg =
                      DateTime.now().difference(v.ultimaVezVisto).inSeconds;
                  final String calidad;
                  final Color colorSenal;
                  if (v.rssi >= -65) {
                    calidad = IdiomaService.t('radar_fuerte');
                    colorSenal = const Color(0xFF00E676);
                  } else if (v.rssi >= -82) {
                    calidad = IdiomaService.t('radar_media');
                    colorSenal = const Color(0xFFFF6D00);
                  } else {
                    calidad = IdiomaService.t('radar_debil');
                    colorSenal = Colors.redAccent;
                  }

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.radar, color: colorSenal),
                    title: Text(
                      v.alias,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    subtitle: Text(
                      '$calidad • Visto hace ${haceSeg}s',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    trailing: Text(
                      '${v.rssi} dBm',
                      style: TextStyle(
                        color: colorSenal,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }


@override
Widget build(BuildContext context) {
  return Column(
    children: [
      Container(
        color: const Color(0xFF121212),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child:Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_config.alias.isEmpty ? (IdiomaService.t('sin_alias')) : _config.alias} • ${_config.esMaestro ? (IdiomaService.t('maestro')) : (IdiomaService.t('repetidor')) } (TTL ${_config.ttlMaximo})',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00E676),
                              fontSize: 13),
                        ),
                        InkWell(
                          onTap: _bleActivo ? _abrirRadarVecinos : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: StreamBuilder<int>(
                              stream: BleMeshService.streamVecinos,
                              initialData: BleMeshService.cantidadNodosVecinos,
                              builder: (context, snap) {
                                final cant = snap.data ?? 0;
                                return Text(
                                  _bleActivo
                                      ? '${IdiomaService.t('ble_activa')} $cant (${IdiomaService.t('ver_radar')})'
                                      : (IdiomaService.t('ble_apagada')),
                                  style: TextStyle(
                                    color: _bleActivo
                                        ? const Color(0xFF00E676)
                                        : Colors.grey,
                                    fontSize: 12,
                                    decoration: _bleActivo
                                        ? TextDecoration.underline
                                        : TextDecoration.none,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onLongPress: _activarODetenerSos,
                    onTap: () {
                      if (_sosActivo) {
                        _activarODetenerSos();
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: Duration(seconds: 2),
                            backgroundColor: Colors.redAccent,
                            content: Text(
                              IdiomaService.t('sos_tip'),
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: _sosActivo
                            ? Colors.red
                            : Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.redAccent, width: 1.5),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sos, color: Colors.white, size: 17),
                          if (_sosActivo) ...[
                            const SizedBox(width: 3),
                            Text(
                              IdiomaService.t('sos_activo_corto'),
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Switch(
                    value: _bleActivo,
                    activeThumbColor: const Color(0xFF00E676),
                    onChanged: _toggleMallaBle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings, color: Color(0xFFFF6D00)),
                    tooltip: 'Configurar Nodo y Batería',
                    onPressed: _abrirConfiguracionNodo,
                  ),
                ],
              ),
        ),
        ExpansionTile(
          backgroundColor: const Color(0xFF121212),
          collapsedBackgroundColor: const Color(0xFF121212),
          leading: Icon(Icons.wifi_tethering,
              color: _wifiActivo ? const Color(0xFF00E676) : Colors.grey),
          title: Text((IdiomaService.t('portal_wifi')),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          trailing: Switch(
            value: _wifiActivo,
            activeThumbColor: const Color(0xFFFF6D00),
            onChanged: _togglePortalWifi,
          ),
          children: [
            if (_wifiActivo)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(8),
                      child: QrImageView(
                          data: _servidorWifi.urlAcceso, size: 130),
                    ),
                    const SizedBox(height: 6),
                    Text(_servidorWifi.urlAcceso,
                        style: const TextStyle(
                            color: Color(0xFF00E676),
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
          ],
        ),
             if (_config.chatActivo && _config.claveGrupo.trim().isNotEmpty)
       Container(
         color: const Color(0xFF0D0D0D),
         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
         child: Row(
           children: [
             Expanded(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: !_verCanalPrivado
                       ? const Color(0xFFFF6D00)
                       : const Color(0xFF1A1A1A),
                   foregroundColor:
                       !_verCanalPrivado ? Colors.black : Colors.grey,
                 ),
                 onPressed: () => setState(() => _verCanalPrivado = false),
                 icon: const Icon(Icons.public, size: 16),
                 label: Text((IdiomaService.t('canal_abierto')),
                     style: TextStyle(
                         fontSize: 11, fontWeight: FontWeight.bold)),
               ),
             ),
             const SizedBox(width: 8),
             Expanded(
               child: ElevatedButton.icon(
                 style: ElevatedButton.styleFrom(
                   backgroundColor: _verCanalPrivado
                       ? const Color(0xFF00E676)
                       : const Color(0xFF1A1A1A),
                   foregroundColor:
                       _verCanalPrivado ? Colors.black : Colors.grey,
                 ),
                 onPressed: () => setState(() => _verCanalPrivado = true),
                 icon: const Icon(Icons.lock, size: 16),
                 label: Text((IdiomaService.t('grupo_privado')),
                     style: TextStyle(
                         fontSize: 11, fontWeight: FontWeight.bold)),
               ),
             ),
           ],
         ),
       ),

        Expanded(
          child: !_config.chatActivo
              ? Center(
                  child: Text((IdiomaService.t('chat_desactivado')),
                      style: TextStyle(color: Colors.grey)))
              : StreamBuilder<List<MensajeMesh>>(
                  stream: MeshChatService.streamMensajes,
                  initialData: MeshChatService.mensajes,
                  builder: (context, snapshot) {
                    final todos = snapshot.data ?? [];
                    final msgs = todos
                        .where((m) =>
                            m.esPrivado ==
                            (_verCanalPrivado &&
                                _config.claveGrupo.trim().isNotEmpty))
                        .toList();

                    if (msgs.isEmpty) {
                      return Center(
                        child: Text(
                            _verCanalPrivado &&
                                    _config.claveGrupo.trim().isNotEmpty
                                ? IdiomaService.t('sin_msgs_privado')
                                : IdiomaService.t('sin_msgs_abierto'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey)),
                      );
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs.elementAt(i);
                                                if (m.texto.startsWith('OFERTA_MAPA:')) {
                          final ofertaId =
                              m.texto.substring('OFERTA_MAPA:'.length);
                          final oferta =
                              SyncCartografiaService.ofertasActivas[ofertaId];
                          if (oferta == null) return const SizedBox.shrink();

                          return Card(
                            color: const Color(0xFF1A1A1A),
                            shape: RoundedRectangleBorder(
                              side: const BorderSide(
                                  color: Color(0xFF00E676), width: 1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    '${IdiomaService.t('oferta_titulo')} ${oferta.autor.toUpperCase()}',
                                    style: const TextStyle(
                                      color: Color(0xFF00E676),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Asegúrate de que ${oferta.autor} tenga su Portal Web Wi-Fi activo (IP ${oferta.ip}) y toca para instalar directo:',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 11),
                                  ),
                                  const SizedBox(height: 8),
                                  ...oferta.archivosFaltantes.map((archivo) {
                                    final etiqueta =
                                        oferta.etiquetas[archivo] ?? archivo;
                                    final claveProg =
                                        '${oferta.ip}_$archivo';
                                    final prog =
                                        _progresoDescargasVecino[claveProg];
                                    final descargando = prog != null;

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          ElevatedButton.icon(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  const Color(0xFFFF6D00),
                                              foregroundColor: Colors.black,
                                            ),
                                            icon: Icon(
                                              descargando
                                                  ? Icons.downloading
                                                  : Icons.download,
                                              size: 18,
                                            ),
                                            label: Text(
                                              descargando
                                                  ? 'Descargando ${(prog * 100).toStringAsFixed(0)}%...'
                                                  : '${IdiomaService.t('descargar_btn')} $etiqueta',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12),
                                            ),
                                            onPressed: descargando
                                                ? null
                                                : () async {
                                                    setState(() {
                                                      _progresoDescargasVecino[
                                                          claveProg] = 0.01;
                                                    });
                                                    final ok =
                                                        await SyncCartografiaService
                                                            .descargarArchivoDesdeVecino(
                                                      ip: oferta.ip,
                                                      nombreArchivo: archivo,
                                                      onProgreso: (pct) {
                                                        if (mounted) {
                                                          setState(() {
                                                            _progresoDescargasVecino[
                                                                claveProg] = pct;
                                                          });
                                                        }
                                                      },
                                                    );
                                                    if (!mounted) return;
                                                    setState(() {
                                                      _progresoDescargasVecino
                                                          .remove(claveProg);
                                                    });
                                                    if (!context.mounted) return;
                                                    ScaffoldMessenger.of(
                                                            context)
                                                        .showSnackBar(
                                                      SnackBar(
                                                        backgroundColor: ok
                                                            ? const Color(
                                                                0xFF00E676)
                                                            : Colors.redAccent,
                                                        content: Text(
                                                          ok
                                                              ? '✅ $archivo instalado en tus Mapas Offline.'
                                                              : '⚠️ No se pudo conectar a ${oferta.ip}:8080.',
                                                          style: TextStyle(
                                                              color: ok
                                                                  ? Colors.black
                                                                  : Colors
                                                                      .white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold),
                                                        ),
                                                      ),
                                                    );
                                                  },
                                          ),
                                          if (descargando) ...[
                                            const SizedBox(height: 4),
                                            LinearProgressIndicator(
                                              value: prog,
                                              color: const Color(0xFF00E676),
                                              backgroundColor:
                                                  const Color(0xFF2A2A2A),
                                            ),
                                          ],
                                        ],
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                          );
                        }
                        return Card(
                          color: const Color(0xFF121212),
                          child: ListTile(
                            title: Row(
                              children: [
                                Text(m.autor,
                                    style: const TextStyle(
                                        color: Color(0xFF00E676),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13)),
                                const Spacer(),
                                Text(
                                    'Saltos: ${m.saltosRecorridos} | TTL: ${m.ttl}',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 10)),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (m.texto.startsWith('PTT:v1:'))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF00E676),
                                        foregroundColor: Colors.black,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 4),
                                      ),
                                      icon: const Icon(Icons.play_arrow,
                                          size: 18),
                                      label:Text((IdiomaService.t('nota_voz_ptt')),
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11)),
                                      onPressed: () {
                                        _sysChannel
                                            .invokeMethod('reproducirPtt', {
                                          'payload': m.texto,
                                        });
                                      },
                                    ),
                                  )
                                else
                                  Text(m.texto),
                                if (m.gps != null)
                                  InkWell(
                                    onTap: () {

                                      final partes = m.gps!.split(',');
                                      if (partes.length == 2) {
                                        final lat = double.tryParse(partes.first.trim());
                                        final lon = double.tryParse(partes.elementAt(1).trim());
                                        if (lat != null && lon != null) {
                                          widget.onAbrirCoordenada?.call(lat, lon);
                                        }
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(
                                        '📍 GPS: ${m.gps} ${IdiomaService.t('ver_en_mapa')}',
                                        style: const TextStyle(
                                          color: Color(0xFFFF6D00),
                                          fontSize: 11,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                  ),

                              ],
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                DeadDropService.esImportante(m.id)
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                color: DeadDropService.esImportante(m.id)
                                    ? const Color(0xFFFF6D00)
                                    : Colors.grey,
                                size: 18,
                              ),
                              tooltip: IdiomaService.t('tip_pin'),
                              onPressed: () async {
                                await DeadDropService.alternarImportante(m);
                                setState(() {});
                              },
                            ),
                          ),
                        );
                      }
                    );
                  },
              ),
        ),
        if (_config.chatActivo)
          Container(
            color: const Color(0xFF121212),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _msgCtrl,
                    onSubmitted: (_) => _enviarMensaje(),
                    decoration: InputDecoration(
                      hintText: (IdiomaService.t('hint_mensaje')),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.inventory_2_outlined,
                      color: Color(0xFFFF6D00)),
                  tooltip: IdiomaService.t('tip_dead_drop'),
                  onPressed: _abrirDialogoDeadDrop,
                ),
                GestureDetector(
                  onLongPressStart: (_) => _iniciarGrabacionPtt(),
                  onLongPressEnd: (_) => _detenerYEnviarPtt(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _grabandoPtt
                          ? Colors.redAccent
                          : const Color(0xFF1E1E1E),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _grabandoPtt ? Icons.graphic_eq : Icons.mic,
                      color:
                          _grabandoPtt ? Colors.white : const Color(0xFF00E676),
                      size: 22,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Color(0xFFFF6D00)),
                  onPressed: _enviarMensaje,
                ),
              ],
            ),
          ),

      ],
    );
  }
}