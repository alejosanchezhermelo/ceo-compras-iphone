# CEO Compras (iPhone) — contexto para Claude

App nativa de iPhone (SwiftUI) de la app de compras de CEO Construcciones. La app principal es la
web/PWA (https://sistemaceoconstrucciones.netlify.app/, código en
`C:\Users\Compras\OneDrive\Documents\App-Compras\2026-05-27-app-local\index.html`). Esta app lee
la MISMA base de Firebase. Se instala gratis con **SideStore**, igual que la app del gym
(`C:\Users\Compras\OneDrive\Desktop\App Gym`, de donde salió la receta de compilación).
Repo PÚBLICO: https://github.com/alejosanchezhermelo/ceo-compras-iphone (rama `main`).

## El usuario (Alejo)
- Español rioplatense, voseo. No es programador: pasos cortos, sin tecnicismos.
- Antes de construir algo nuevo, proponer y esperar su OK. No agregar cosas que no pidió.
- Al terminar un build: qué cambió, link de instalación y link a la versión anterior.

## Estado al 2026-10-23 noche: v0.8 (build-10) = diseño PWA + grupos A y B + Cargar factura (QR AFIP). Antes: v0.4 (build-4) instalada y funcionando con datos reales: crea/edita OC; primera OC real 1603 verificada TODO BIEN y WhatsApp al encargado OK. (v0.1 fue la primera instalada.) Código de dispositivo YA registrado ("iPhone Alejo (app nativa)"); se registra por API con la llave de servicio de la carpeta de la web (herramientas/*adminsdk*.json).

## Etapas (decididas el 2026-10-23)
- **Etapa 1 (esta): SOLO LECTURA.** Face ID nativo al abrir, lista de OC (pestañas, búsqueda,
  filtros obra/encargado, orden), ficha, PDF (ver/imprimir), compartir PDF (WhatsApp) y mail.
  **No escribe nada en Firebase.** Diferencias con la web por eso: generar el PDF no anota
  "OC PDF No X generada" en el historial; una OC sin `numOCPDF` no se puede generar acá.
- **Etapa 2 (pendiente de que Alejo decida tras probar la 1):** crear/editar OC. Guardar una OC en
  la web hace 5 cosas que hay que replicar igual (`_doSaveOrden` en index.html): número +
  `config/nextOCNum`, alta en la lista `proveedores` si es nuevo, `obraId`/`provId`, evento en
  `historial` (`logE`), aviso por WhatsApp al encargado (`notifyE`, CallMeBot). Antes de escribir:
  arreglar en la web los 2 puntos débiles (lista `proveedores` se guarda entera con `set` → pisadas;
  número de OC sin transacción) y armar prueba que compare OC guardadas desde iPhone y desde la web.
  Backup de Firebase antes de habilitar escritura.
- Alejo usa el iPhone para ver/crear/editar OC y mandarlas por WhatsApp. Facturas, conciliación y
  Excel quedan en la PC (no portarlos).

## Etapa 2 (crear/editar OC) — HABILITADA CON DATOS REALES en v0.4 (2026-10-23, OK de Alejo tras prueba TODO BIEN)
- Interruptor "Modo prueba" en Ajustes: lee y escribe en `pruebas-iphone/` (copia de la base real armada el
  23/10 14:58; foto inicial en `App-Compras/respaldos/*pruebas-iphone-inicial.json`). Franja roja.
- `Config.escrituraReal = true` desde v0.4. Backup previo: `App-Compras/respaldos/2026-10-23-1526-firebase-backup-pre-escritura-real-iphone.json`.
  Verificador con `--real` compara la base real contra ese backup (ojo: también lista lo que se haga desde la PC).
- Guardar (`Store.guardar`) = `_doSaveOrden` de la web: proveedor nuevo a la lista (PUT condicional con ETag,
  reintenta si la PC lo cambió), y en UN solo PATCH multi-ruta: la OC, obrasData/provData si son nuevos
  (`getObraId`/`getProvId`), evento de historial; después `config/nextOCNum` con ETag. WhatsApp al encargado
  (CallMeBot, contactos leídos SIEMPRE de `waContacts` real) solo en datos reales.
- Diferencia a propósito: al editar, el iPhone SÍ guarda la fecha de entrega (la web no: bug de la web).
- No guarda si no llegaron en vivo config/ordenes/obrasData/provData/proveedores (evita el bug de duplicados).
- Verificador (solo lectura): script `verificar_prueba.py` (en el scratchpad de la sesión del 23/10; si no
  está, rehacerlo: compara `pruebas-iphone` contra la foto inicial con las reglas de la web).
- **LECCIÓN v0.2:** Firebase REST es solo HTTP/1.1 → cada escucha SSE ocupa una conexión; iOS permite 6 por
  servidor por defecto → con 9 escuchas, 3 quedaban colgadas y nunca se podía guardar (el error salía al pie
  del formulario y no se veía). Arreglo v0.3: `httpMaximumConnectionsPerHost = 16` y error en alerta.

## Cómo se conecta (sin SDK de Firebase, por REST) — `Firebase.swift`
- Base con App Check OBLIGATORIO + reglas `auth != null`. Hacen falta los dos:
  1. Usuario anónimo: `identitytoolkit accounts:signUp` (refresh con `securetoken`), guardado en llavero.
  2. Sello App Check: `exchangeDebugToken` contra la **app web** (`Config.appId`) con el "código de
     dispositivo" (UUID que genera cada iPhone, en su llavero). **Ese código hay que registrarlo una
     vez** en Firebase → App Check → app web → debug tokens. Es una llave: NUNCA va al repo ni al .ipa.
- Lectura en vivo por SSE (`Accept: text/event-stream`) de 5 nodos: config, ordenes, obras,
  encargados, historial (no se baja `pruebas`, que pesa 640 KB). `JSONTree` aplica put/patch.
- Copia local en Caches (`ceo-datos.json`) para abrir al instante y sin señal.
- Probado desde la PC el 2026-10-23 (script en el scratchpad de esa sesión): anónimo + sello → 200;
  sin sello → "Missing appcheck token"; código no registrado → 403 "App attestation failed".

## Reglas copiadas de la web (si la web cambia, cambiar acá)
- Contraseña: `config.password || 'compras123'`; si mide 64 es SHA-256. Face ID guarda ese valor y
  se anula si cambia.
- OC formato viejo/nuevo: se lee `obra`/`proveedor` como texto (están en las 442 OC).
- Filtros/orden = `renderC()`. Etiquetas = `cardOC()`. Facturas = `_facLista()`.
- PDF = `generarPDFDoc()` (jsPDF + autoTable, medidas en mm). **La web lee `it.unidad` pero los
  ítems guardan `unit`** → la columna Unidad sale vacía en la web; acá se replica igual a propósito.
  Si Alejo pide arreglarlo, cambiarlo en los dos lados juntos.

## Cómo se compila y publica (no hay Mac)
1. Subir `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` en `project.yml`.
2. `git commit` + `git push origin main` → GitHub Actions (macOS): XcodeGen → xcodebuild sin firmar
   → `CEOCompras.ipa` → Release `build-N`.
3. `gh run watch <id> -R alejosanchezhermelo/ceo-compras-iphone`; si falla:
   `gh run view <id> --log | grep " error:"`.
- `gh` en Bash: `export PATH="$PATH:/c/Program Files/GitHub CLI"`.
- Solo documentación: `[skip ci]` en el commit.
- Instalar: `https://github.com/alejosanchezhermelo/ceo-compras-iphone/releases/latest/download/CEOCompras.ipa`
  → Safari → SideStore → My Apps → + → elegir el .ipa.
- Bundle ID fijo: `com.alejosanchez.ceocompras` (no cambiarlo: gasta App IDs, 10 por semana).
- SideStore gratis: máximo 3 apps activas (SideStore + gym + esta = lleno).

## Estructura
`Config` (datos públicos), `Keychain`, `Firebase` (REST + SSE), `JSONTree` (+ lectores tolerantes),
`Models` (OC, filtros, formatos), `Store` (estado, login, Face ID, bloqueo a los 5 min, caché),
`Biometria`, `PDFOC`, `Views/` (`ListaOC`, `DetalleOC`, `PantallasEntrada`: login/código/ajustes,
`Componentes`).

## Reglas técnicas
- Swift 5 en modo de lenguaje; sin regex `/.../`.
- La ventana de Face ID pone la app "inactiva": el bloqueo/Face ID se dispara solo al volver de
  `.background`, nunca de `.inactive` (si no, entra en bucle).

## v0.5–v0.8 (2026-10-23)
- Diseño PWA: `Views/Tema.swift` (colores de :root, fuentes CEOSyne/CEODMSans/CEODMMono en `Fuentes/`, OFL), modo claro fijo.
- Barra propia de 6 pestañas (`ContenidoPestanas` en CEOComprasApp.swift): Órdenes, Actividad, Ajustes, Precios, Proveedores, Facturas.
- Grupo A `StoreAcciones.swift` · Grupo B `StoreGrupoB.swift` · Facturas QR `StoreFacturas.swift` + `LectorQR.swift` + `Views/PantallaFacturas.swift`.
- Reglas de la web portadas: `Facturas.swift` (importe, N° combinado, CUIT). Listas guardadas enteras por la web → `editarLista` con ETag.
- OJO: no repetir nombres de archivo entre carpetas (Xcode falla: pasó con Facturas.swift en v0.8).
- OJO: NO usar TabView con 6 pestañas (iOS arma un menú "More" escondido; pasó en v0.8-0.10). Las pantallas van en un ZStack en `ContenidoPestanas`.
