package com.emergencia.aegis_node

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.ParcelUuid
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.kiwix.libzim.Archive
import org.kiwix.libzim.SuggestionSearcher
import java.io.File
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.net.URLDecoder
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    companion object {
        var errorCargaNativa: String? = null

        init {
            val libs = listOf("c++_shared", "zim", "zim_wrapper", "kiwix", "kiwix_wrapper")
            for (lib in libs) {
                try {
                    System.loadLibrary(lib)
                } catch (t: Throwable) {
                    errorCargaNativa = "Fallo al cargar lib$lib.so: ${t.message}"
                }
            }
        }
    }

    private val CHANNEL = "com.emergencia.aegis_node/kiwix"
    private var archive: Archive? = null
    private var pfdActual: ParcelFileDescriptor? = null
    private var zimServerSocket: ServerSocket? = null
    private val zimPort = 8081
    private var sensorManager: SensorManager? = null
    private var brujulaListener: SensorEventListener? = null
    private var pttRecorder: android.media.MediaRecorder? = null
    private var pttFile: File? = null
    private var pttPlayer: android.media.MediaPlayer? = null
    private var activeAdvertiseCallback: AdvertiseCallback? = null
    private var gattServer: BluetoothGattServer? = null
    private var methodChannelRef: MethodChannel? = null
    private val gattBuffers = ConcurrentHashMap<String, StringBuilder>()
    private val SERVICE_UUID = UUID.fromString("0000ae61-0000-1000-8000-00805f9b34fb")
    private val CHAR_UUID = UUID.fromString("0000ae62-0000-1000-8000-00805f9b34fb")

    private val NOTIF_CHAT_ID = 2081
    private val mensajesSinLeer = ArrayList<String>()

    private fun iniciarServidorZimLocal() {
        if (zimServerSocket != null && !zimServerSocket!!.isClosed) return
        thread(isDaemon = true) {
            try {
                val server = ServerSocket(zimPort, 50, InetAddress.getByName("127.0.0.1"))
                zimServerSocket = server
                while (!server.isClosed) {
                    val client = server.accept()
                    thread(isDaemon = true) { atenderPeticionZim(client) }
                }
            } catch (_: Throwable) {
            }
        }
    }

    private fun atenderPeticionZim(socket: Socket) {
        try {
            socket.use { s ->
                val input = s.getInputStream().bufferedReader()
                val requestLine = input.readLine() ?: return
                val partes = requestLine.split(" ")
                if (partes.size < 2) return

                var rawPath = URLDecoder.decode(partes[1].substringBefore("?"), "UTF-8")
                if (rawPath.startsWith("/")) rawPath = rawPath.substring(1)

                val arch = archive
                if (arch == null) {
                    enviarRespuesta(s, "503 Service Unavailable", "text/plain", "Sin ZIM activo".toByteArray())
                    return
                }

                val entry = if (rawPath.isEmpty()) {
                    arch.mainEntry
                } else {
                    try {
                        arch.getEntryByPath(rawPath)
                    } catch (_: Throwable) {
                        try {
                            arch.getEntryByTitle(rawPath.replace("_", " "))
                        } catch (_: Throwable) {
                            null
                        }
                    }
                }

                if (entry == null) {
                    enviarRespuesta(s, "404 Not Found", "text/plain", "No encontrado: $rawPath".toByteArray())
                    return
                }

                val item = entry.getItem(true)
                val mime = item.mimetype.ifEmpty { "text/html; charset=utf-8" }
                var data = item.data.data

                if (mime.contains("text/html")) {
                    val htmlOriginal = String(data, Charsets.UTF_8)
                    val inyeccionOscura = "<style>body{background:#000!important;color:#e0e0e0!important;font-family:sans-serif!important}a{color:#FF6D00!important}h1,h2,h3{color:#00E676!important}</style>"
                    data = (inyeccionOscura + htmlOriginal).toByteArray(Charsets.UTF_8)
                }

                enviarRespuesta(s, "200 OK", mime, data)
            }
        } catch (_: Throwable) {
        }
    }

    private fun enviarRespuesta(socket: Socket, status: String, mime: String, body: ByteArray) {
        val out = socket.getOutputStream()
        val headers = "HTTP/1.1 $status\r\nContent-Type: $mime\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n"
        out.write(headers.toByteArray(Charsets.UTF_8))
        out.write(body)
        out.flush()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("abrir_nodo", false)) {
            mensajesSinLeer.clear()
            methodChannelRef?.invokeMethod("abrirPestanaNodo", null)
        }
    }

    override fun onDestroy() {
        try {
            brujulaListener?.let { sensorManager?.unregisterListener(it) }
            brujulaListener = null
            val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            val advertiser = btManager.adapter?.bluetoothLeAdvertiser
            activeAdvertiseCallback?.let {
                advertiser?.stopAdvertising(it)
            }
            activeAdvertiseCallback = null
            gattServer?.close()
            gattServer = null
            gattBuffers.clear()
            stopService(Intent(this, MeshForegroundService::class.java))
        } catch (_: Throwable) {}
        super.onDestroy()
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        iniciarServidorZimLocal()

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannelRef = channel

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "abrirZim" -> {
                    val ruta = call.argument<String>("ruta")
                    if (ruta != null && File(ruta).exists()) {
                        try {
                            pfdActual?.close()
                            val file = File(ruta)
                            val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            pfdActual = pfd
                            archive = Archive(pfd.fileDescriptor)
                            errorCargaNativa = null
                            result.success("http://127.0.0.1:$zimPort/")
                        } catch (t: Throwable) {
                            val detalle = errorCargaNativa ?: t.message ?: t.toString()
                            result.error("ZIM_ERROR", detalle, null)
                        }
                    } else {
                        result.error("NO_FILE", "Archivo ZIM no encontrado", null)
                    }
                }
                "buscar" -> {
                    val query = call.argument<String>("query") ?: ""
                    val arch = archive
                    if (arch == null) {
                        result.error("NO_READER", "Primero abre un archivo ZIM", null)
                    } else {
                        try {
                            val sugerencias = ArrayList<Map<String, String>>()
                            val searcher = SuggestionSearcher(arch)
                            val search = searcher.suggest(query)
                            val results = search.getResults(0, 20)
                            for (entry in results) {
                                sugerencias.add(mapOf("title" to entry.title, "path" to entry.path))
                            }
                            result.success(sugerencias)
                        } catch (_: Throwable) {
                            result.success(ArrayList<Map<String, String>>())
                        }
                    }
                }
                "emitirBle" -> {
                    val bytes = call.argument<ByteArray>("datos")
                    val mId = call.argument<Int>("manufacturerId") ?: 0xAE61
                    if (bytes == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                        val advertiser = btManager.adapter?.bluetoothLeAdvertiser
                        if (advertiser == null) {
                            result.error("NO_BLE_ADV", "Este dispositivo no soporta BLE Advertising", null)
                            return@setMethodCallHandler
                        }
                        activeAdvertiseCallback?.let {
                            try { advertiser.stopAdvertising(it) } catch (_: Throwable) {}
                        }
                        val settings = AdvertiseSettings.Builder()
                            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
                            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                            .setConnectable(true)
                            .build()
                        val data = AdvertiseData.Builder()
                            .setIncludeDeviceName(false)
                            .addServiceUuid(ParcelUuid(SERVICE_UUID))
                            .addManufacturerData(mId, bytes)
                            .build()
                        val callback = object : AdvertiseCallback() {}
                        activeAdvertiseCallback = callback
                        advertiser.startAdvertising(settings, data, callback)
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("BLE_ERR", t.message, null)
                    }
                }
                "iniciarGattServer" -> {
                    try {
                        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                        if (gattServer == null) {
                            val serverCallback = object : BluetoothGattServerCallback() {
                                override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
                                    super.onConnectionStateChange(device, status, newState)
                                }

                                override fun onServiceAdded(status: Int, service: BluetoothGattService) {
                                    super.onServiceAdded(status, service)
                                }

                                override fun onMtuChanged(device: BluetoothDevice, mtu: Int) {
                                    super.onMtuChanged(device, mtu)
                                }

                                override fun onCharacteristicWriteRequest(
                                    device: BluetoothDevice,
                                    requestId: Int,
                                    characteristic: BluetoothGattCharacteristic,
                                    preparedWrite: Boolean,
                                    responseNeeded: Boolean,
                                    offset: Int,
                                    value: ByteArray
                                ) {
                                    if (responseNeeded) {
                                        gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, 0, null)
                                    }
                                    val fragmento = String(value, Charsets.UTF_8)
                                    val sb = gattBuffers.getOrPut(device.address) { StringBuilder() }
                                    if (fragmento.trimStart().startsWith("{")) {
                                        sb.clear()
                                    }
                                    sb.append(fragmento)
                                    val acumulado = sb.toString()
                                    if (acumulado.trim().endsWith("}")) {
                                        gattBuffers.remove(device.address)
                                        runOnUiThread {
                                            methodChannelRef?.invokeMethod("onMensajeGattRecibido", acumulado)
                                        }
                                    }
                                }
                            }
                            gattServer = btManager.openGattServer(this, serverCallback)
                            val service = BluetoothGattService(SERVICE_UUID, BluetoothGattService.SERVICE_TYPE_PRIMARY)
                            val char = BluetoothGattCharacteristic(
                                CHAR_UUID,
                                BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
                                BluetoothGattCharacteristic.PERMISSION_WRITE
                            )
                            service.addCharacteristic(char)
                            gattServer?.addService(service)
                        }
                        val svcIntent = Intent(this, MeshForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(svcIntent)
                        } else {
                            startService(svcIntent)
                        }
                        result.success(true)
                    } catch (t: Throwable) {
                        result.error("GATT_ERR", t.message, null)
                    }
                }
                "detenerBle" -> {
                    try {
                        val btManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
                        val advertiser = btManager.adapter?.bluetoothLeAdvertiser
                        activeAdvertiseCallback?.let {
                            advertiser?.stopAdvertising(it)
                        }
                        activeAdvertiseCallback = null
                        gattServer?.close()
                        gattServer = null
                        gattBuffers.clear()
                        stopService(Intent(this, MeshForegroundService::class.java))
                    } catch (_: Throwable) {}
                    result.success(true)
                }
                "notificarMensaje" -> {
                    val autor = call.argument<String>("autor") ?: "Nodo"
                    val cuerpo = call.argument<String>("cuerpo") ?: ""
                    try {
                        mensajesSinLeer.add("$autor: $cuerpo")
                        val total = mensajesSinLeer.size
                        val manager = getSystemService(NotificationManager::class.java)

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val ch = NotificationChannel(
                                "aegis_msg_alert",
                                "Alertas de Chat Malla",
                                NotificationManager.IMPORTANCE_HIGH
                            )
                            manager.createNotificationChannel(ch)
                        }

                        val tapIntent = Intent(this, MainActivity::class.java).apply {
                            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                            putExtra("abrir_nodo", true)
                        }
                        val pendingIntent = PendingIntent.getActivity(
                            this,
                            NOTIF_CHAT_ID,
                            tapIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )

                        val inbox = Notification.InboxStyle()
                        for (linea in mensajesSinLeer.takeLast(6)) {
                            inbox.addLine(linea)
                        }
                        inbox.setSummaryText("$total mensajes nuevos en la malla")

                        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Notification.Builder(this, "aegis_msg_alert")
                        } else {
                            @Suppress("DEPRECATION")
                            Notification.Builder(this)
                        }

                        val tituloAgrupado = if (total == 1) {
                            "Mensaje de $autor"
                        } else {
                            "AegisNode ($total mensajes nuevos)"
                        }

                        val notif = builder
                            .setContentTitle(tituloAgrupado)
                            .setContentText("$autor: $cuerpo")
                            .setStyle(inbox)
                            .setSmallIcon(android.R.drawable.ic_dialog_email)
                            .setContentIntent(pendingIntent)
                            .setAutoCancel(true)
                            .build()

                        manager.notify(NOTIF_CHAT_ID, notif)
                    } catch (_: Throwable) {}
                    result.success(true)
                }
                "limpiarNotificaciones" -> {
                    try {
                        mensajesSinLeer.clear()
                        val manager = getSystemService(NotificationManager::class.java)
                        manager.cancel(NOTIF_CHAT_ID)
                    } catch (_: Throwable) {}
                    result.success(true)
                }
                "obtenerBateria" -> {
                    try {
                        val bm = getSystemService(Context.BATTERY_SERVICE) as android.os.BatteryManager
                        val nivel = bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY)
                        result.success(nivel)
                    } catch (_: Throwable) {
                        result.success(-1)
                    }
                }
                "cifrarAes" -> {
                    val texto = call.argument<String>("texto") ?: ""
                    val clave = call.argument<String>("clave") ?: ""
                    try {
                        val digest = java.security.MessageDigest.getInstance("SHA-256")
                        val keyBytes = digest.digest(clave.toByteArray(Charsets.UTF_8))
                        val secretKey = javax.crypto.spec.SecretKeySpec(keyBytes, "AES")

                        val iv = ByteArray(12)
                        java.security.SecureRandom().nextBytes(iv)
                        val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(javax.crypto.Cipher.ENCRYPT_MODE, secretKey, javax.crypto.spec.GCMParameterSpec(128, iv))
                        val cifrado = cipher.doFinal(texto.toByteArray(Charsets.UTF_8))

                        val combinado = ByteArray(iv.size + cifrado.size)
                        System.arraycopy(iv, 0, combinado, 0, iv.size)
                        System.arraycopy(cifrado, 0, combinado, iv.size, cifrado.size)
                        val b64 = android.util.Base64.encodeToString(combinado, android.util.Base64.NO_WRAP)
                        result.success("ENC:v1:$b64")
                    } catch (t: Throwable) {
                        result.error("AES_ENC_ERR", t.message, null)
                    }
                }
                "descifrarAes" -> {
                    val payload = call.argument<String>("payload") ?: ""
                    val clave = call.argument<String>("clave") ?: ""
                    try {
                        if (!payload.startsWith("ENC:v1:") || clave.isEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val b64 = payload.removePrefix("ENC:v1:")
                        val combinado = android.util.Base64.decode(b64, android.util.Base64.NO_WRAP)
                        if (combinado.size < 13) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val iv = combinado.copyOfRange(0, 12)
                        val cifrado = combinado.copyOfRange(12, combinado.size)

                        val digest = java.security.MessageDigest.getInstance("SHA-256")
                        val keyBytes = digest.digest(clave.toByteArray(Charsets.UTF_8))
                        val secretKey = javax.crypto.spec.SecretKeySpec(keyBytes, "AES")

                        val cipher = javax.crypto.Cipher.getInstance("AES/GCM/NoPadding")
                        cipher.init(javax.crypto.Cipher.DECRYPT_MODE, secretKey, javax.crypto.spec.GCMParameterSpec(128, iv))
                        val plano = String(cipher.doFinal(cifrado), Charsets.UTF_8)
                        result.success(plano)
                    } catch (_: Throwable) {
                        result.success(null)
                    }
                }
                             "iniciarPtt" -> {
                 try {
                     pttRecorder?.release()
                     val outFile = File(cacheDir, "ptt_temp.amr")
                     if (outFile.exists()) outFile.delete()
                     pttFile = outFile

                     val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                         android.media.MediaRecorder(this)
                     } else {
                         @Suppress("DEPRECATION")
                         android.media.MediaRecorder()
                     }
                     recorder.setAudioSource(android.media.MediaRecorder.AudioSource.MIC)
                     recorder.setOutputFormat(android.media.MediaRecorder.OutputFormat.AMR_NB)
                     recorder.setAudioEncoder(android.media.MediaRecorder.AudioEncoder.AMR_NB)
                     recorder.setAudioSamplingRate(8000)
                     recorder.setAudioEncodingBitRate(4750)
                     recorder.setMaxDuration(4500) // Máximo 4.5 segundos (~5 KB)
                     recorder.setOutputFile(outFile.absolutePath)
                     recorder.prepare()
                     recorder.start()
                     pttRecorder = recorder
                     result.success(true)
                 } catch (t: Throwable) {
                     result.error("PTT_REC_ERR", t.message, null)
                 }
             }
             "detenerPtt" -> {
                 try {
                     pttRecorder?.stop()
                 } catch (_: Throwable) {}
                 try {
                     pttRecorder?.release()
                 } catch (_: Throwable) {}
                 pttRecorder = null

                 val f = pttFile
                 if (f != null && f.exists() && f.length() > 100) {
                     val b64 = android.util.Base64.encodeToString(f.readBytes(), android.util.Base64.NO_WRAP)
                     result.success("PTT:v1:$b64")
                 } else {
                     result.success(null)
                 }
             }
             "reproducirPtt" -> {
                 val payload = call.argument<String>("payload") ?: ""
                 try {
                     if (!payload.startsWith("PTT:v1:")) {
                         result.success(false)
                         return@setMethodCallHandler
                     }
                     val b64 = payload.removePrefix("PTT:v1:")
                     val bytes = android.util.Base64.decode(b64, android.util.Base64.NO_WRAP)
                     val playFile = File(cacheDir, "ptt_play.amr")
                     playFile.writeBytes(bytes)

                     pttPlayer?.release()
                     val player = android.media.MediaPlayer()
                     player.setDataSource(playFile.absolutePath)
                     player.prepare()
                     player.start()
                     pttPlayer = player
                     result.success(true)
                 } catch (_: Throwable) {
                     result.success(false)
                 }
             }

                else -> result.notImplemented()
            }
        }

        val brujulaChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.emergencia.aegis_node/brujula")
        brujulaChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "iniciarBrujula" -> {
                    if (sensorManager == null) {
                        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
                    }
                    val rotSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                    if (rotSensor == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    brujulaListener?.let { sensorManager?.unregisterListener(it) }
                    val listener = object : SensorEventListener {
                        private val rotMatrix = FloatArray(9)
                        private val orientation = FloatArray(3)
                        private var ultimoEnvio = 0L

                        override fun onSensorChanged(event: SensorEvent) {
                            val ahora = System.currentTimeMillis()
                            if (ahora - ultimoEnvio < 100) return
                            ultimoEnvio = ahora

                            SensorManager.getRotationMatrixFromVector(rotMatrix, event.values)
                            SensorManager.getOrientation(rotMatrix, orientation)
                            var azimutGrados = Math.toDegrees(orientation[0].toDouble())
                            if (azimutGrados < 0) azimutGrados += 360.0
                            runOnUiThread {
                                brujulaChannel.invokeMethod("onBrujulaActualizada", azimutGrados)
                            }
                        }

                        override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}
                    }
                    brujulaListener = listener
                    sensorManager?.registerListener(listener, rotSensor, SensorManager.SENSOR_DELAY_UI)
                    result.success(true)
                }
                "detenerBrujula" -> {
                    brujulaListener?.let { sensorManager?.unregisterListener(it) }
                    brujulaListener = null
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
