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
- PDF = `generarPDFDoc()` (jsPDF + autoTable, medidas en mm). Columna Unidad = `it.unit || it.unidad`
  (arreglado en los dos lados el 2026-10-26, v0.13 + SW v33; antes salía vacía).

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

## v0.14 (2026-10-26) — MODO PISTOLA en Facturas (pedido de Alejo: "que yo pueda elegir el modo pistola o normal")
- Selector Normal / 🔫 Pistola arriba de la pestaña Facturas (se recuerda: `@AppStorage("facturas-modo-pistola")`). Modo Normal = igual que antes.
- `Views/PistolaFacturas.swift`: cámara SIEMPRE prendida (pantalla completa); bip + vibración al leer; la factura va ENTERA a 1 OC con un toque (`guardarFacturaQR` con 1 importe); vuelve sola a esperar la próxima. Varias OC por factura → "Saltear" y cargarla en Normal.
- Misma hoja todavía frente a la cámara → "ya la cargaste en esta tanda" (no la toma como duplicada). Ya cargada de antes → aviso rojo. QR trucho (Materiales Avenida) o sin QR → carga a mano ahí mismo.
- CUIT que no está en el padrón: se busca la OC; al elegirla se le anota el CUIT al proveedor de la OC SOLO si no tenía.
- Deshacer por factura = `quitarFacturas` (las candidatas no tenían factura).
- Al terminar, en Facturas: tarjeta de la tanda + "Imprimir las N OC (un solo PDF)" (`registrarPDFsTanda`: anota "OC PDF No … generada" en todas en UN guardado; las que no tienen numOCPDF reciben números seguidos) → `PDFOC.tanda` (una OC por hoja, en orden de escaneo) → visor con imprimir/compartir. La lista vive en memoria (se pierde si se cierra la app; las facturas ya quedaron guardadas).
- **v0.15 (build-17):** BUG de v0.14 en uso real (26/10): la OC 1572 recibió 2 facturas (0028-00112426 $385.334,18 y 0028-00112427 $312.024,10, el proveedor las mandó separadas) y la 2ª PISÓ a la 1ª (la copia en memoria todavía no sabía que la OC ya tenía factura, 14 s después). Arreglo: `guardarFacturaPistola` lee la OC de la base EN ESE MOMENTO y, si ya tiene factura, la SUMA (`Facturas.datos`, como `sumarFactura`); deshacer = `quitarFacturaPistola` (saca solo esa). Las OC de la tanda siguen en la lista con "Ya tiene la X · esta se SUMA".

## v0.16 / v0.17 (2026-10-27) — Pestaña Órdenes IGUAL A LA PWA + un poco de Liquid Glass (pedido de Alejo: "hacela igual a la pwa", "sumalo dale")
- **Las OC se abren ahí mismo en la lista (▼)** como `cardOC`: `TarjetaOC` (ListaOC.swift) + `CuerpoOC` (DetalleOC.swift; ya no hay pantalla aparte ni `navigationDestination`). Abiertas = `abiertas: Set<String>` (`expanded` de la web).
- **Botón flotante "➕ Nueva OC"** (`#fabNuevaOC`) abajo a la derecha; se esconde con el teclado (zona segura > 120, como la barra). Sigue también el "+ Nueva OC" de la barra de herramientas, como la web.
- **Botones 🏆 Proveedores (pasa a la pestaña 4), 🏗 Obras y 👷 Encargados** abajo de los filtros; Obras/Encargados abren `PanelObras`/`PanelEncargados` (Views/PanelesOC.swift) arriba de la lista (= `cOP`/`cEP`). El 📊 Excel NO (Alejo no lo usa).
- **Formulario** (FormularioOC.swift) con el estilo de `#sModal`: rótulos chicos, "Número de OC *", fecha tipo input date (vacía hasta tocar, ✕ la borra), Obra con buscador + sugerencias (`onObraInput`, hasta 8) y "+ Nueva" (`addObraModal` → `store.agregarObra`), Proveedor con sugerencias, **Rubro**, "Responsable de obra *", renglones Descripción/Cant./Unidad/✕, "+ Agregar ítem", "Notas adicionales", Cancelar / Guardar orden. Diferencia a propósito: la web en el celular esconde la columna Unidad; acá queda (Alejo la usa).
- **Rubros:** se escucha el nodo `rubros` (`Store.rubros`, orden por id = como la web), se guarda `b.rubro` al crear y editar (antes el iPhone guardaba "" / el viejo), etiqueta de color `Etiqueta.rubro` (fondo color+22, borde color+55). Al 27/10 la base NO tiene rubros cargados.
- Botones de la OC en una fila que baja de renglón (`Renglones`), orden de la web: Generar OC, Quitar factura, Editar, Urgente, Eliminar. `BotonPWA(lleno: false)` = ancho del texto.
- **v0.17 Liquid Glass (solo iOS 26, `#available`)**: botón flotante (`vidrioAzul()`), barra de abajo flotante de vidrio (pestaña elegida = pastilla azul clara), hoja "OC No …" (`fondoHoja()`). Tarjetas/materiales/botones quedan sólidos A PROPÓSITO (sol de obra + igual a la PWA). En iOS 18 se ve como v0.16. El Mac de GitHub tiene Xcode 26.6 (SDK iOS 26).
- **v0.18 (build-20)** — foto de Alejo con v0.17 en iOS 26: el "➕ Nueva OC" quedaba encimado con la barra de vidrio y no se leía, y arriba "Pedidos · COMPRAS" se veía solo el ícono (iOS 26 pone un círculo de vidrio a los botones de la barra de arriba). Arreglo: `BotonNuevaOC` va en el `safeAreaInset` de `ContenidoPestanas`, JUSTO ARRIBA de la barra (solo en Órdenes; avisa con `store.pedirNuevaOC` y ListaOC abre el formulario), con `.buttonStyle(.glassProminent).tint(T.bl)` en iOS 26. Encabezado en las 6 pestañas con `.conEncabezado()` (Tema.swift): en iOS 26 `.sharedBackgroundVisibility(.hidden)` + `fixedSize()`. **Regla: nada flotante suelto con overlay sobre la barra; y todo ToolbarItem con texto necesita sacarle el fondo en iOS 26.**

## v0.19 (2026-10-27, desde la nube) — Animaciones, vibraciones, menú al mantener apretado, íconos de Apple (pedido de Alejo: "que se vea moderna", puntos 1-7 aprobados uno por uno)
- **Abrir OC (ListaOC):** UNA sola abierta a la vez (`abierta: String?`, antes `abiertas: Set`); se despliega con resorte y la pantalla se acomoda (`ScrollViewReader` → `scrollTo(id, .top)`). Diferencia a propósito con la web (allá pueden quedar varias abiertas).
- **Pestañas (`ContenidoPestanas`):** `ir(a:)` = animación `.snappy`, la pantalla entra corrida 24 pt del lado de la pestaña tocada (`offset`), pastilla/rayita con `matchedGeometryEffect`, ícono con `.symbolEffect(.bounce)`.
- **Vibraciones (`Vibrar` en Tema.swift, UIKit feedback):** pestaña = selección; abrir/cerrar OC = suave; cada `store.aviso` = "listo" (si empieza con 🔴 = firme), en `Raiz.onChange`; errores = `.vibrarAlError(error)` en todas las alertas "No se guardó"; antes de eliminar = aviso.
- **Mantener apretada una OC (`TarjetaOC.contextMenu`, solo en el encabezado para no chocar con los campos de la OC abierta):** vista previa `VistaPreviaOC` + Ver/imprimir PDF, Mandar por WhatsApp (registra "OC PDF No…" como Generar OC y abre Compartir; sin numOCPDF abre la hoja de siempre), Copiar N° de OC, Editar, Marcar/Quitar urgente, Eliminar (confirma). Lo maneja `ListaOC.elegirDelMenu` (espera 0,3 s a que cierre el menú).
- **Contadores de arriba:** `contentTransition(.numericText)`; arrancan en 0 (`contadoresListos`).
- **Íconos:** emojis de botones/títulos/etiquetas → SF Symbols con `ic(simbolo, texto)` (Text con imagen adentro: hereda letra y color). `Etiqueta`/`Divisor` tienen `icono:`. Los cartelitos (`store.aviso`) siguen con emoji en el texto y `IconoAviso.separar` lo cambia por ícono al mostrarlo. NO se tocaron: textos de historial/WhatsApp/PDF (iguales a la web), mensajes del modo Pistola, medallas 🥇🥈🥉.
- **Carga:** `TarjetaFantasma` / `EventoFantasma` con `.brillo()` mientras `ordenes`/`eventos` están vacíos (máx. 10 s, después texto). Con la copia local casi siempre abre con datos, así que se ven poco.
- Todo respeta "Reducir movimiento" donde hay desplazamientos (pestañas, brillo).
- **v0.20:** menú de mantener apretada una OC suma "Copiar materiales" (`ListaOC.textoMateriales`): "Buenas, me pasas cotizacion de estos materiales:" (texto exacto de Alejo, sin cierre) + "• desc — cant unidad" por renglón. Sin N° de OC, obra ni proveedor (es para cotizar con otro proveedor). Solo aparece si la OC tiene materiales.

## v0.21 (2026-10-28, desde la nube) — Sección GASTOS POR OBRA (pedido de Alejo; eligió las opciones A, B, D y C dentro de la ficha)
- **Barra de abajo:** la pestaña 2 ahora es **GASTOS** (`PantallaGastos`, ícono chart.bar). **Ajustes ya no es pestaña:** engranaje arriba a la derecha en todas las pantallas (`BotonAjustes` dentro de `.conEncabezado()`; `store.mostrarAjustes` → hoja en `ContenidoPestanas`). Dentro de Ajustes: `.conEncabezado(ajustes: false)` + botón "Listo".
- **Cálculo (`GastosObra.swift`, enum `Gastos`):** cada factura de `oc.facturas` (si hay lista `facturas`, cada una con su ts e importe; la lista suma igual que la principal) con su importe; si no tiene importe, lo busca en la conciliación (`conciliaciones/{N° factura}/sel/{idOC}` = "12345,67"). El mes es el de la CARGA (ts), no la fecha de emisión (no se guarda). Obras agrupadas sin mayúsculas. Comparación con el mes anterior: si el mes está en curso, contra los mismos días del mes anterior ("a esta altura de…").
- **Facturas repartidas en varias OC sin importe por OC:** se reparten exacto por obra con la conciliación hecha en la PC. La base NO se modifica.
- **`conciliaciones` NO se escucha en vivo** (sería otra conexión fija; ver lección v0.2): `store.cargarConciliaciones()` la lee UNA vez con `leerConHuella` al abrir Gastos y al deslizar para actualizar; queda en la copia local.
- **Pantalla:** tarjeta con ‹ mes › + total (número que rueda) + comparación + selector "Por mes / Total desde …"; **(B)** redondo con Swift Charts `SectorMark` (5 obras con color FIJO = las 5 de más gasto acumulado, paleta validada para daltonismo; resto "Otras"; tocar porción o nombre la resalta); **(A)** ranking de todas las obras con barras que crecen → `NavigationLink(DestinoObra)`; "Compartir resumen de todas las obras" (texto).
- **Ficha (`FichaObra`) = D + C:** total del período + acumulado; **mes a mes** (`BarMark`, mes elegido oscuro); "A quién se le compró" (barra partida 4 + Otros); todas las facturas del período (tocar → `HojaOCGasto` con `CuerpoOC`); "Compartir resumen de {obra}".
- **Este repo es PÚBLICO:** no anotar acá montos, nombres de obras/proveedores ni N° de factura (van en el MEMORY.md del repo privado de la web).
