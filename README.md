# AegisNode // OFFLINE

**AegisNode** es una aplicación móvil de código abierto para Android diseñada para operar como **estación táctil de conocimiento autónomo, navegación cartográfica y comunicación descentralizada sin conexión a Internet** durante emergencias, apagones prolongados, desastres naturales o expediciones fuera de cobertura.

---

## Características Principales

### 1. Red en Malla Bluetooth Low Energy (BLE Multi-Hop Mesh)
* **Comunicación sin infraestructura:** Permite intercambiar mensajes de texto y reportes entre dispositivos cercanos con AegisNode sin necesidad de señal celular, routers ni puntos de acceso Wi-Fi.
* **Protocolo de saltos configurables (TTL):** Cada mensaje puede configurarse para viajar de **1 a 20 saltos** entre nodos intermedios (*Modo Maestro* o *Modo Repetidor*), ampliando el alcance de la red de forma descentralizada con control anti-duplicados.
* **Entrega fiable GATT y ejecución en segundo plano:** Utiliza conexiones GATT con confirmación de recepción y un servicio nativo en primer plano (*Foreground Service*) que mantiene la escucha activa con la pantalla apagada y se detiene limpiamente al cerrar la aplicación.
* **Gestión de batería (*Duty-Cycling*):** Incluye tres perfiles de consumo energético (**Ultra-Ahorro**, **Equilibrado** y **Rescate Activo**) sobre una interfaz OLED negra pura (`#000000`).
* **Coordenadas GPS clicables:** Opcionalmente, el usuario puede adjuntar su ubicación GPS de alta precisión a los mensajes; al tocar las coordenadas recibidas, el mapa offline se abre y centra automáticamente en ese punto.

### 2. Portal Web Local Wi-Fi (Opcional bajo demanda)
* **Difusión sin Internet:** Permite encender un servidor HTTP local (`puerto 8080`) con código QR para que cualquier teléfono, tablet o computadora cercana (incluso sin tener AegisNode instalado) pueda conectarse vía Hotspot Wi-Fi, participar en la bitácora local y descargar manuales desde su navegador web.

### 3. Cartografía Offline y Navegación GPS (`MBTiles`)
* **Mapas vectoriales/ráster sin conexión:** Renderiza mapas locales en formato `.mbtiles` con zoom táctico de hasta nivel 17, brújula magnetométrica, cálculo de distancia y rumbo hacia objetivos, y posicionamiento por hardware GNSS/GPS puro.
* **Descarga previa automatizada:** Permite generar paquetes regionales bajo demanda a partir de teselas abiertas de OpenStreetMap antes de perder conectividad.

### 4. Enciclopedias y Bases de Conocimiento Offline (`ZIM` / Libzim)
* **Motor nativo C++ (`libzim`):** Lee archivos `.zim` completos de forma local e instantánea con búsqueda indexada y tema oscuro inyectado para lectura nocturna (medicina de emergencia, supervivencia, guías técnicas, Wikipedia, iFixit, etc.).
* **Catálogo integrado:** Conexión directa con el catálogo abierto OPDS de Kiwix para descargar paquetes esenciales o buscar enciclopedias por temática.

### 5. Biblioteca Local de Manuales (`PDF`)
* Visor integrado y gestor de documentos técnicos, protocolos y guías personales almacenados localmente en `/storage/emulated/0/AegisNode/manuales`.

---

## Guía Rápida de Uso

1. **Preparación previa (con conexión a Internet):**
   * Abre la pestaña **Preparar** y descarga los paquetes **Wiki ZIM** esenciales (como *WikiMed* o *Wikipedia Esencial*) y los **Mapas Offline** de tu región o ciudad.
   * Opcionalmente, copia tus propios archivos `.pdf`, `.mbtiles` o `.zim` en las carpetas `/AegisNode/manuales`, `/AegisNode/mapas` y `/AegisNode/wikis` del almacenamiento interno.
2. **Operación en emergencia (100% Offline):**
   * **Chat y Malla:** Ve a la pestaña **Nodo**, toca el ícono de configuración (`⚙️`) para definir tu **Indicativo / Alias**, tu perfil de batería y tus opciones de privacidad, y activa el interruptor **Malla BLE**.
   * **Compartir con dispositivos sin la app:** Enciende el Zona Wi-Fi / Hotspot de tu teléfono, activa **Portal Web Wi-Fi** en la pestaña **Nodo** y muestra el código QR para que otros usuarios accedan desde su navegador.
   * **Navegación y consulta:** Usa las pestañas **Manuales**, **Mapas** y **Wiki ZIM** sin consumir datos móviles ni requerir señal.

---

## Compilación desde el Código Fuente

### Requisitos
* Flutter SDK (`3.x` o superior)
* Android SDK (`compileSdk 37`, `targetSdk 35`, `minSdk 26`)
* Java / JDK 17

### Pasos
```bash
git clone https://github.com
cd AegisNode
flutter pub get
flutter build apk --release --split-per-abi
```
El instalador optimizado para dispositivos Android modernos de 64 bits se generará en:
`build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

---

## Propiedad Intelectual, Licencias y Política de Uso de Datos

1. **Licencia y Condiciones de Uso del Código:**
   * El código fuente original de **AegisNode** se publica como **Software Libre y de Código Abierto** bajo la licencia **MIT** (o **Apache 2.0**).
   * **Se autoriza expresamente a cualquier persona a usar, copiar, estudiar, modificar, fusionar, publicar y distribuir** este software y sus derivados, con fines personales, comunitarios o comerciales, **con la única condición de conservar el aviso de derechos de autor y mencionar la autoría original del proyecto AegisNode** en el código fuente y en la documentación de las versiones derivadas.
   * Las bibliotecas de terceros integradas (`org.kiwix:libzim`, `flutter_map`, `flutter_blue_plus`, `shelf`, `sqflite`, `geolocator`, entre otras) mantienen sus respectivas licencias libres originales (GPLv3, Apache 2.0, BSD-3-Clause y MIT).

   * Todas las dependencias de terceros incluidas en `pubspec.yaml` y bibliotecas nativas (`org.kiwix:libzim`, `flutter_map`, `flutter_blue_plus`, `shelf`, `sqflite`, `geolocator`, entre otras) pertenecen a sus respectivos autores y se utilizan bajo sus correspondientes licencias compatibles de software libre (GPLv3, Apache 2.0, BSD-3-Clause y MIT).
2. **Contenidos y Enciclopedias Externas:**
   * **AegisNode no aloja, distribuye ni comercializa archivos protegidos por derechos de autor.** La aplicación actúa exclusivamente como un cliente de descarga y visor local de archivos proporcionados por el propio usuario o descargados directamente por este desde repositorios públicos abiertos.
   * Los paquetes `.zim` descargados a través del catálogo público de **Kiwix** (`library.kiwix.org`) pertenecen a sus respectivos proyectos origen (Fundación Wikimedia, WikiMed, iFixit, Proyecto Gutenberg, etc.) bajo sus licencias libres correspondientes (**CC BY-SA**, **CC BY** o Dominio Público). El usuario es el único responsable de respetar los derechos de autor de cualquier archivo externo que incorpore manualmente en su dispositivo.
3. **Uso Responsable de Servidores de Mapas (Política de Teselas):**
   * Los datos cartográficos utilizados para generar archivos `.mbtiles` provienen de **OpenStreetMap** (`© OpenStreetMap contributors`, licencia **ODbL**).
   * **Prohibición de descargas masivas abusivas:** El usuario se compromete a utilizar la herramienta de descarga de mapas únicamente para uso personal y preparación puntual de zonas locales de emergencia, respetando estrictamente la *Tile Usage Policy* de OpenStreetMap (evitando descargas masivas, automatizadas o de regiones extensas que sobrecarguen los servidores comunitarios gratuitos). Para despliegues masivos o institucionales, el usuario deberá configurar su propio servidor de teselas o generar los archivos `.mbtiles` localmente.

---

## Seguridad, Privacidad y Exención de Responsabilidad

1. **Software No Auditado en Seguridad:**
   * **AegisNode es un proyecto comunitario independiente que NO ha sido sometido a una auditoría formal de seguridad informática ni criptográfica.** Aunque el código fuente está abierto a revisión pública, pueden existir vulnerabilidades técnicas no detectadas.
2. **Ausencia de Cifrado y Riesgos de Privacidad en Comunicaciones:**
   * **Transmisión en texto claro (*Plaintext*):** Tanto los mensajes difundidos a través de la **Malla Bluetooth Low Energy (BLE)** como el tráfico servido mediante el **Portal Web Wi-Fi local (HTTP)** operan **sin cifrado de extremo a extremo ni autenticación fuerte**.
   * **Riesgos inherentes:** Cualquier persona con un dispositivo compatible dentro del alcance de la señal Bluetooth o conectada a la misma red Wi-Fi local puede interceptar, leer o retransmitir los mensajes enviados, los alias configurados y las **coordenadas GPS** compartidas. **No utilice AegisNode para transmitir información confidencial, datos personales sensibles ni ubicaciones en contextos donde la exposición de su posición represente un riesgo para su integridad física.**
3. **Exención General de Responsabilidad (Disclaimer):**
   * **Uso bajo riesgo exclusivo del usuario:** **AegisNode** se distribuye *"TAL CUAL"* (*"AS IS"*), sin garantías expresas ni implícitas de ningún tipo, incluyendo garantías de disponibilidad continua, alcance de señal, entrega garantizada de mensajes, integridad de datos o idoneidad para un propósito particular.
   * **No sustituye servicios oficiales de emergencia:** Esta herramienta está concebida únicamente como un complemento auxiliar de resiliencia comunitaria y consulta offline. En ninguna circunstancia reemplaza a los sistemas oficiales de protección civil, servicios médicos profesionales, radiocomunicaciones homologadas de rescate (VHF/UHF/satelital) ni las directivas de las autoridades competentes.
   * **Limitaciones físicas y de sistema operativo:** El rendimiento de la malla Bluetooth y el consumo energético dependen del hardware del dispositivo, el nivel de batería, los obstáculos del entorno y las restricciones de segundo plano del fabricante de Android. Los autores y colaboradores no asumen responsabilidad alguna por pérdidas de datos, fallos de comunicación, bloqueos de IP por abuso de servidores externos, daños materiales o lesiones personales derivadas del uso o imposibilidad de uso de esta aplicación.

## Créditos y Desarrollo

* **Concepción, diseño funcional, pruebas en campo y autoría:** [fenork]
* **Asistencia en arquitectura de software e implementación de código:** Desarrollado en colaboración con **Google Gemini** (asistente de IA).
