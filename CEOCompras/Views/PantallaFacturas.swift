import SwiftUI
import PhotosUI

/// Pestaña Facturas: cargar una factura leyendo el QR de AFIP (cámara, PDF o imagen), elegir las OC y guardar.
/// Mismos pasos que la pestaña Facturas de la PWA (sin el detalle línea por línea de las facturas mensuales).
struct PantallaFacturas: View {
    @Environment(Store.self) private var store

    enum Paso { case inicio, leyendo, aviso(String), manual(avisoQR: Bool), duplicada(String), flujo, guardada(Int) }
    struct EnCurso { var num: String; var total: Double; var cuit: String; var fuente: String }

    @State private var paso: Paso = .inicio
    @State private var f: EnCurso?
    @State private var textoPDF = ""
    @State private var pdf: Data?
    // entradas
    @State private var camara = false
    @State private var avisoCamara: String?
    @State private var elegirPDF = false
    @State private var foto: PhotosPickerItem?
    // carga a mano
    @State private var mPv = ""
    @State private var mCmp = ""
    @State private var mTot = ""
    // elegir OC
    @State private var tildadas: [String: String] = [:]
    @State private var busqueda = ""
    @State private var provEscrito = ""
    @State private var preguntaSuma: String?
    @State private var combo: ArchivoPDF?
    @State private var opcionesOC: OC?
    @State private var trabajando = false
    @State private var error: String?
    // modo pistola (se recuerda la última elección)
    @AppStorage("facturas-modo-pistola") private var modoPistola = false
    @State private var pistolaAbierta = false
    @State private var tanda: [CargadaPistola] = []
    @State private var preguntaVaciar = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.modoPrueba { FranjaPrueba() }
                    Text("🧾 Cargar factura").font(T.syne(20)).foregroundStyle(T.bl)
                    switch paso {
                    case .inicio: inicio
                    case .leyendo:
                        HStack { ProgressView(); Text("Leyendo la factura…").font(T.sans(13)).foregroundStyle(T.bl) }.padding()
                    case .aviso(let m): avisoAmarillo(m, botonManual: true)
                    case .manual(let avisoQR): manual(avisoQR)
                    case .duplicada(let m): duplicada(m)
                    case .flujo: flujo
                    case .guardada(let n): guardada(n)
                    }
                }
                .padding(14)
            }
            .background(T.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos() } }
            .fileImporter(isPresented: $elegirPDF, allowedContentTypes: [.pdf]) { leerPDF($0) }
            .onChange(of: foto) { _, item in if let item { leerFoto(item) } }
            .fullScreenCover(isPresented: $camara) { camaraVista }
            .fullScreenCover(isPresented: $pistolaAbierta) { PistolaFacturas(cargadas: $tanda) }
            .confirmationDialog("¿Vaciar la lista de esta tanda?", isPresented: $preguntaVaciar, titleVisibility: .visible) {
                Button("Vaciar la lista") { tanda = [] }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("Las facturas quedan guardadas en sus OC; solo se borra esta lista.") }
            .sheet(item: $combo) { VisorPDF(archivo: $0) }
            .sheet(item: $opcionesOC) { OpcionesOC(oc: $0) }
            .alert(preguntaSuma ?? "", isPresented: Binding(get: { preguntaSuma != nil }, set: { if !$0 { preguntaSuma = nil } })) {
                Button("Guardar igual") { grabar() }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    // MARK: 1) Inicio: cómo entra la factura

    private var inicio: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Modo", selection: $modoPistola) {
                Text("Normal").tag(false)
                Text("🔫 Pistola").tag(true)
            }
            .pickerStyle(.segmented)
            if modoPistola { inicioPistola } else { inicioNormal }
        }
    }

    // MARK: 1b) Modo pistola: muchas facturas seguidas

    private var inicioPistola: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Para cargar una pila de facturas seguidas: la cámara queda prendida, apuntás al QR, tocás la OC y pasás a la siguiente. Cada factura va entera a una OC.")
                    .font(T.sans(13)).foregroundStyle(T.tx3)
                if !EscanerQR.disponible {
                    Text("Este iPhone no puede usar la cámara para leer QR.").font(T.sans(13)).foregroundStyle(T.rd)
                } else if !store.puedeEditar {
                    Text("Guardar no está habilitado.").font(T.sans(13)).foregroundStyle(T.rd)
                } else {
                    Button { pistolaAbierta = true } label: {
                        Text(tanda.isEmpty ? "🔫 Empezar a escanear" : "🔫 Seguir escaneando").font(T.sans(16, .semibold))
                    }
                    .buttonStyle(BotonGrande(color: T.bl))
                }
            }
            .padding(14)
            .tarjeta()
            if !tanda.isEmpty { tarjetaTanda }
        }
    }

    private var tarjetaTanda: some View {
        let ids = ocsDeLaTanda()
        return VStack(alignment: .leading, spacing: 10) {
            Text("✅ \(tanda.count) factura\(tanda.count == 1 ? "" : "s") cargada\(tanda.count == 1 ? "" : "s") en esta tanda")
                .font(T.sans(15, .bold)).foregroundStyle(Color(hex: 0x065F46))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(tanda) { c in
                    Text("\(c.facNum) → OC \(c.ocNum) · \(c.proveedor)").font(T.sans(12)).foregroundStyle(Color(hex: 0x065F46)).lineLimit(1)
                }
            }
            Button {
                imprimirTanda()
            } label: {
                Text("🖨️ Imprimir las \(ids.count) OC (un solo PDF)").font(T.sans(15, .semibold))
            }
            .buttonStyle(BotonGrande(color: T.bl))
            .disabled(trabajando || ids.isEmpty)
            if trabajando { HStack { ProgressView(); Text("Armando el PDF…").font(T.sans(13)).foregroundStyle(T.bl) } }
            Button("Vaciar la lista (empezar otra tanda)") { preguntaVaciar = true }
                .buttonStyle(BotonPWA(tipo: .blanco))
        }
        .padding(16)
        .background(Color(hex: 0xECFDF5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xA7F3D0)))
    }

    /// OC de la tanda, sin repetir, en el orden en que se escanearon.
    private func ocsDeLaTanda() -> [OC] {
        var vistos = Set<String>()
        return tanda.compactMap { c in
            guard vistos.insert(c.ocId).inserted else { return nil }
            return store.ordenes.first { $0.id == c.ocId }
        }
    }

    /// Anota "OC PDF No … generada" en cada una (como imprimirlas de a una) y arma un solo PDF con todas.
    private func imprimirTanda() {
        let ocs = ocsDeLaTanda()
        if ocs.isEmpty { return }
        trabajando = true
        Task {
            var nums: [String: Int] = [:]
            if store.puedeEditar {
                let r = await store.registrarPDFsTanda(ocs)
                if let e = r.error { trabajando = false; error = e; return }
                nums = r.nums
            }
            trabajando = false
            do {
                let titulo = "OC de \(ocs.count) facturas"
                let url = try PDFOC.tanda(ocs.map { ($0, nums[$0.id] ?? $0.numOCPDF ?? Int($0.num) ?? 0) }, nombre: titulo)
                combo = ArchivoPDF(url: url, titulo: titulo)
            } catch {
                self.error = "No se pudo armar el PDF"
            }
        }
    }

    private var inicioNormal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("La app lee sola el número y el importe del QR de AFIP. No hace falta descargar la factura: alcanza con la cámara.")
                .font(T.sans(13)).foregroundStyle(T.tx3)
            if EscanerQR.disponible {
                Button { avisoCamara = nil; camara = true } label: { Text("📷 Escanear el QR con la cámara").font(T.sans(15, .semibold)) }
                    .buttonStyle(BotonGrande(color: T.bl))
            }
            Button { elegirPDF = true } label: { Text("📄 Elegir el PDF de la factura").font(T.sans(14, .semibold)) }
                .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl)))
            PhotosPicker(selection: $foto, matching: .images) {
                Text("🖼 Elegir una captura o foto del QR").font(T.sans(14, .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bl, lineWidth: 1))
                    .foregroundStyle(T.bl)
            }
            Button { abrirManual(texto: "", avisoQR: false) } label: { Text("✍️ Cargar a mano").font(T.sans(13)) }
                .buttonStyle(BotonPWA(tipo: .blanco))
            Text("💡 Si la factura te llegó por WhatsApp o mail, guardá el PDF en Archivos y elegilo con \"📄 Elegir el PDF\": así después podés imprimir la OC y la factura juntas.")
                .font(T.sans(12)).foregroundStyle(T.tx3)
        }
        .padding(14)
        .tarjeta()
    }

    private var camaraVista: some View {
        ZStack(alignment: .bottom) {
            EscanerQR { leido in recibirDeCamara(leido) }.ignoresSafeArea()
            VStack(spacing: 10) {
                Text(avisoCamara ?? "Apuntá al QR de AFIP de la factura (abajo, al pie)")
                    .font(T.sans(14, .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    .padding(12).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                Button("Cancelar") { camara = false }.buttonStyle(BotonGrande(color: Color(hex: 0xF0F0F0), texto: T.tx))
            }
            .padding(20)
        }
    }

    // MARK: 2) Avisos y carga a mano

    private func avisoAmarillo(_ m: String, botonManual: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(m).font(T.sans(13)).foregroundStyle(Color(hex: 0x92400E))
            if botonManual {
                Button("✍️ Cargar a mano") { abrirManual(texto: textoPDF, avisoQR: false) }.buttonStyle(BotonPWA())
            }
            Button("Volver") { reiniciar() }.buttonStyle(BotonPWA(tipo: .blanco))
        }
        .padding(14)
        .background(Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xFCD34D)))
    }

    private func manual(_ avisoQR: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if avisoQR {
                Text("⚠️ El QR de esta factura no es válido.\nEl sistema del proveedor imprimió un QR que no corresponde a esta factura, así que no se puede usar. "
                     + (textoPDF.isEmpty ? "Completá los datos a mano y confirmá." : "Revisá los datos que tomé del PDF y confirmá."))
                    .font(T.sans(13)).foregroundStyle(Color(hex: 0x92400E))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("✍️ Cargar factura a mano").font(T.sans(14, .bold)).foregroundStyle(T.bl)
            Text("Revisá los datos (precargué lo que pude leer) y confirmá.").font(T.sans(12)).foregroundStyle(T.tx3)
            HStack {
                Text("N° de factura").font(T.sans(13)).foregroundStyle(T.tx3).frame(width: 105, alignment: .leading)
                TextField("0001", text: $mPv).keyboardType(.numberPad).multilineTextAlignment(.center).campoPWA().frame(width: 76)
                Text("-").bold().foregroundStyle(T.tx3)
                TextField("00000001", text: $mCmp).keyboardType(.numberPad).multilineTextAlignment(.center).campoPWA()
            }
            HStack {
                Text("Importe total").font(T.sans(13)).foregroundStyle(T.tx3).frame(width: 105, alignment: .leading)
                Text("$").foregroundStyle(T.tx3)
                TextField("0,00", text: $mTot).keyboardType(.decimalPad).multilineTextAlignment(.trailing).campoPWA()
            }
            HStack {
                Button("Continuar") { confirmarManual() }.buttonStyle(BotonPWA())
                Button("Cancelar") { reiniciar() }.buttonStyle(BotonPWA(tipo: .blanco))
            }
        }
        .padding(16)
        .tarjeta()
    }

    private func duplicada(_ m: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(m).font(T.sans(14)).foregroundStyle(Color(hex: 0x991B1B))
            Button("Volver") { reiniciar() }.buttonStyle(BotonPWA(tipo: .blanco))
        }
        .padding(16)
        .background(Color(hex: 0xFEE2E2), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xFCA5A5)))
    }

    // MARK: 3) Datos de la factura + elegir OC

    @ViewBuilder private var flujo: some View {
        if let f {
            let prov = store.proveedorPorCuit(f.cuit)
            datosFactura(f, prov)
            elegirOC(f, prov)
        }
    }

    private func datosFactura(_ f: EnCurso, _ prov: FichaProveedor?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(f.fuente == "manual" ? "✍️ CARGADA A MANO" : f.fuente == "camara" ? "📷 QR ESCANEADO CON LA CÁMARA"
                 : f.fuente == "imagen" ? "📋 QR LEÍDO DE LA IMAGEN" : "✓ FACTURA LEÍDA DEL PDF")
                .font(T.mono(11, .medium)).foregroundStyle(T.gn)
            fila("N° de factura") { Text(f.num).font(T.mono(14, .medium)) }
            fila("Importe total") { Text(Formato.pesos(f.total)).font(T.sans(14, .bold)) }
            fila("CUIT proveedor") {
                if f.cuit.isEmpty { Text("no detectado").foregroundStyle(T.am) } else { Text(Facturas.fmtCuit(f.cuit)) }
            }
            fila("Proveedor") {
                if let prov {
                    (Text(prov.nombre).foregroundStyle(T.gn).bold() + Text(" (en tu padrón)").foregroundStyle(T.tx3).font(T.sans(12)))
                } else {
                    Text("Proveedor nuevo").foregroundStyle(T.am).bold()
                }
            }
            if prov == nil && !f.cuit.isEmpty && store.puedeEditar { vincular(f) }
        }
        .font(T.sans(14))
        .padding(16)
        .tarjeta()
    }

    private func fila<V: View>(_ t: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(t).foregroundStyle(T.tx3).frame(width: 125, alignment: .leading)
            v()
            Spacer(minLength: 0)
        }
    }

    /// El CUIT no está en el padrón: elegir a qué proveedor corresponde o crearlo.
    private func vincular(_ f: EnCurso) -> some View {
        let q = provEscrito.trimmingCharacters(in: .whitespaces).lowercased()
        var vistos = Set<String>()
        let todos = store.fichasProveedores.filter { !$0.nombre.isEmpty && vistos.insert($0.nombre.lowercased()).inserted }
        let sugerencias = Array((q.isEmpty ? todos : todos.filter { $0.nombre.lowercased().contains(q) }).prefix(8))
        return VStack(alignment: .leading, spacing: 6) {
            Divider()
            Text("El CUIT \(Facturas.fmtCuit(f.cuit)) no está en el padrón. ¿A qué proveedor corresponde?")
                .font(T.sans(12)).foregroundStyle(T.tx3)
            TextField("Escribí el nombre del proveedor…", text: $provEscrito).campoPWA()
            ForEach(sugerencias) { p in
                Button(p.nombre) {
                    correr({ await store.vincularCuit(p, cuit: f.cuit) }, ok: "✅ CUIT vinculado a \(p.nombre)")
                }
                .font(T.sans(13)).foregroundStyle(T.tx)
            }
            let val = provEscrito.trimmingCharacters(in: .whitespaces)
            if !val.isEmpty && !sugerencias.contains(where: { $0.nombre.lowercased() == val.lowercased() }) {
                Button("➕ Crear proveedor \"\(val)\"") {
                    correr({ await store.crearProveedor(val, cuit: f.cuit) }, ok: "✅ Proveedor creado con el CUIT")
                }
                .font(T.sans(13, .semibold)).foregroundStyle(T.bl)
            }
        }
    }

    private func elegirOC(_ f: EnCurso, _ prov: FichaProveedor?) -> some View {
        let lista = store.ocsParaFactura(proveedor: prov, busqueda: busqueda, tildadas: Set(tildadas.keys))
        let n = tildadas.count
        return VStack(alignment: .leading, spacing: 10) {
            (Text("¿A qué OC corresponde?").foregroundStyle(T.bl).bold()
             + Text(prov.map { " — \($0.nombre)" } ?? "").foregroundStyle(T.tx3))
                .font(T.sans(13))
            TextField("🔍 Buscar OC, obra o proveedor", text: $busqueda).campoPWA()
            VStack(spacing: 0) {
                if lista.isEmpty {
                    Text("No hay OC para mostrar. Probá el buscador.").font(T.sans(13)).foregroundStyle(T.tx3).padding(12)
                }
                ForEach(lista.prefix(80)) { o in filaOC(o, f) }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bd))
            resumen(f)
            if pdf != nil {
                Button("🖨️ Imprimir / compartir OC + factura") { armarCombo(f) }
                    .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl))).disabled(n == 0)
            } else {
                Text("La factura entró sin el PDF (cámara o imagen), así que no se puede armar el PDF \"OC + factura\". La OC se imprime con su botón de siempre.")
                    .font(T.sans(12)).foregroundStyle(T.tx3)
                    .padding(10).background(T.sf2, in: RoundedRectangle(cornerRadius: 8))
            }
            if store.puedeEditar {
                Button("Guardar factura en las OC") { guardar(f) }
                    .buttonStyle(BotonGrande(color: n == 0 ? T.bd : T.bl))
                    .disabled(n == 0 || trabajando)
            }
            Button("Cancelar") { reiniciar() }.buttonStyle(BotonPWA(tipo: .blanco))
        }
        .padding(16)
        .tarjeta()
    }

    private func filaOC(_ o: OC, _ f: EnCurso) -> some View {
        let tildada = tildadas[o.id] != nil
        return HStack(spacing: 10) {
            Button { tildar(o.id, !tildada, f) } label: {
                Image(systemName: tildada ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20)).foregroundStyle(tildada ? T.bl : T.tx3)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text("OC \(o.num)").font(T.syne(13)).foregroundStyle(T.bl)
                Text((o.obra.isEmpty ? "—" : o.obra) + (o.proveedor.isEmpty ? "" : " · \(o.proveedor)"))
                    .font(T.sans(12)).foregroundStyle(T.tx3).lineLimit(1)
            }
            Spacer()
            if tildada {
                if tildadas.count == 1 {
                    Text("= total").font(T.sans(12)).foregroundStyle(T.tx3)
                } else {
                    TextField("importe", text: Binding(get: { tildadas[o.id] ?? "" }, set: { tildadas[o.id] = $0 }))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).font(T.sans(13))
                        .frame(width: 110).padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.bd))
                }
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { tildar(o.id, !tildada, f) }
        .overlay(alignment: .bottom) { Rectangle().fill(T.bd).frame(height: 1) }
    }

    /// `_facResumenHTML`
    @ViewBuilder private func resumen(_ f: EnCurso) -> some View {
        let n = tildadas.count
        if n == 0 {
            Text("Tildá una o más OC.").font(T.sans(13)).foregroundStyle(T.tx3)
        } else if n == 1 {
            cartel("1 OC · se le asigna el total: \(Formato.pesos(f.total))", verde: true)
        } else {
            let valores = tildadas.values.map { Facturas.importe($0) }
            if valores.contains(where: { $0 == nil }) {
                cartel("Cargá el importe de las \(n) OC tildadas", verde: false)
            } else {
                let suma = valores.compactMap { $0 }.reduce(0, +)
                if abs(suma - f.total) < 0.05 {
                    cartel("✓ La suma coincide con el total de la factura", verde: true)
                } else {
                    let dif = f.total - suma
                    cartel("Suma \(Formato.pesos(suma)) / Total \(Formato.pesos(f.total)) · \(dif > 0 ? "faltan" : "sobran") \(Formato.pesos(abs(dif)))", verde: false)
                }
            }
        }
    }

    private func cartel(_ t: String, verde: Bool) -> some View {
        Text(t).font(T.sans(13, .semibold))
            .foregroundStyle(verde ? Color(hex: 0x065F46) : Color(hex: 0x92400E))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(verde ? Color(hex: 0xD1FAE5) : Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 8))
    }

    private func guardada(_ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("✅ Factura \(f?.num ?? "") guardada en \(n) OC").font(T.sans(15, .bold)).foregroundStyle(Color(hex: 0x065F46))
            Text("Cada OC quedó con el N° de factura y su importe.").font(T.sans(12)).foregroundStyle(Color(hex: 0x065F46))
            if pdf != nil, let f {
                Button("🖨️ Imprimir / compartir OC + factura") { armarCombo(f) }.buttonStyle(BotonPWA())
            }
            // Imprimir cada OC (como "Generar OC" de la ficha), aunque la factura haya entrado sin PDF
            ForEach(store.ordenes.filter { tildadasGuardadas.contains($0.id) }.sorted { $0.numeroEntero < $1.numeroEntero }) { o in
                Button("📄 Imprimir OC \(o.num)") { generarOC(o) }
                    .buttonStyle(BotonPWA(tipo: .suave(T.blL, T.bl, T.blM)))
                    .disabled(trabajando)
            }
            Button("➕ Cargar otra factura") { reiniciar() }.buttonStyle(BotonPWA(tipo: .blanco))
        }
        .padding(16)
        .background(Color(hex: 0xECFDF5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xA7F3D0)))
    }

    // MARK: Acciones

    private func reiniciar() {
        paso = .inicio; f = nil; pdf = nil; textoPDF = ""; tildadas = [:]; busqueda = ""; provEscrito = ""; foto = nil
        tildadasGuardadas = []
    }

    private func recibirDeCamara(_ leido: String) {
        guard camara else { return }
        switch LectorQR.evaluar([leido], texto: "") {
        case .ok(let d, _):
            camara = false
            pdf = nil; textoPDF = ""
            iniciar(d, texto: "", fuente: "camara")
        case .qrInvalido:
            camara = false
            pdf = nil; textoPDF = ""
            abrirManual(texto: "", avisoQR: true)
        default:
            avisoCamara = "Ese QR no es el de AFIP. Apuntá al QR que está al pie de la factura (el que dice AFIP al lado)."
        }
    }

    private func leerPDF(_ r: Result<URL, Error>) {
        guard case .success(let url) = r else { return }
        let acceso = url.startAccessingSecurityScopedResource()
        defer { if acceso { url.stopAccessingSecurityScopedResource() } }
        guard let datos = try? Data(contentsOf: url) else { paso = .aviso("No se pudo abrir el archivo."); return }
        paso = .leyendo
        Task {
            let res = await Task.detached(priority: .userInitiated) { LectorQR.leerPDF(datos) }.value
            pdf = datos
            switch res {
            case .ok(let d, let t):
                textoPDF = t
                iniciar(d, texto: t, fuente: "pdf")
            case .qrInvalido(let t):
                textoPDF = t
                abrirManual(texto: t, avisoQR: true)
            case .sinQR(let t):
                textoPDF = t
                paso = .aviso("No se pudo leer el QR de AFIP de esta factura.\nEl QR puede venir borroso o de baja calidad. Igual podés cargar los datos a mano.")
            case .noEsAfip:
                paso = .aviso("No se pudo leer el QR de AFIP de esta factura. Igual podés cargar los datos a mano.")
            }
        }
    }

    private func leerFoto(_ item: PhotosPickerItem) {
        paso = .leyendo
        Task {
            guard let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d), let cg = img.cgImage else {
                paso = .aviso("No se pudo abrir la imagen.")
                return
            }
            let codigos = await Task.detached(priority: .userInitiated) { LectorQR.qrs(en: cg) }.value
            pdf = nil; textoPDF = ""
            switch LectorQR.evaluar(codigos, texto: "") {
            case .ok(let dq, _): iniciar(dq, texto: "", fuente: "imagen")
            case .qrInvalido: abrirManual(texto: "", avisoQR: true)
            case .noEsAfip: paso = .aviso("Se leyó un QR, pero no es el de AFIP.\nElegí una imagen del QR que está al pie de la factura (el que dice AFIP al lado).")
            case .sinQR: paso = .aviso("No se encontró un QR legible en la imagen.\nProbá con una captura más cerca del QR (que ocupe casi toda la imagen). Si no sale, cargala a mano.")
            }
            foto = nil
        }
    }

    /// `_facIniciarConDatos`
    private func iniciar(_ d: LectorQR.DatosQR, texto: String, fuente: String) {
        let cuit = LectorQR.cuitProveedor(texto: texto, qrCuit: d.cuitQR, receptor: d.receptor)
        empezar(EnCurso(num: d.num, total: d.total, cuit: cuit, fuente: fuente))
    }

    private func empezar(_ e: EnCurso) {
        let dup = Facturas.yaCargada(e.num, cuit: e.cuit, total: e.total, en: store.ordenes)
        if !dup.isEmpty {
            paso = .duplicada("⚠ Esta factura ya está cargada.\nLa factura N° \(e.num) ya está vinculada a: "
                              + dup.map { "OC \($0.num)" }.joined(separator: ", ")
                              + ".\nSi te equivocaste, quitala desde la ficha de la OC y volvé a cargarla.")
            return
        }
        f = e
        tildadas = [:]
        busqueda = ""
        provEscrito = ""
        paso = .flujo
    }

    private func abrirManual(texto: String, avisoQR: Bool) {
        let n = LectorQR.numeroDeTexto(texto)
        mPv = n.pv; mCmp = n.cmp
        mTot = LectorQR.totalDeTexto(texto).map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? ""
        paso = .manual(avisoQR: avisoQR)
    }

    /// `_facConfirmarManual`
    private func confirmarManual() {
        let pv = Facturas.soloDigitos(mPv), cmp = Facturas.soloDigitos(mCmp)
        if pv.isEmpty || cmp.isEmpty { error = "Completá las dos partes del número de factura."; return }
        guard let total = Facturas.importe(mTot), total > 0 else { error = "Cargá un importe total válido (ej: 131970,34)."; return }
        let cuit = LectorQR.cuitProveedor(texto: textoPDF, qrCuit: "", receptor: "")
        empezar(EnCurso(num: LectorQR.formatoNumero(pv, cmp), total: total, cuit: cuit, fuente: "manual"))
    }

    /// `_facToggleOC`: con una sola OC tildada, se le asigna el total.
    private func tildar(_ id: String, _ si: Bool, _ f: EnCurso) {
        if si { tildadas[id] = "" } else { tildadas[id] = nil }
        if tildadas.count == 1, let unica = tildadas.keys.first {
            tildadas[unica] = String(format: "%.2f", f.total).replacingOccurrences(of: ".", with: ",")
        }
    }

    @State private var tildadasGuardadas: [String] = []
    @State private var importesAGuardar: [String: Double] = [:]

    private func guardar(_ f: EnCurso) {
        let ids = Array(tildadas.keys)
        if ids.isEmpty { error = "Tildá al menos una OC"; return }
        var imp: [String: Double] = [:]
        for id in ids {
            let v = ids.count > 1 ? Facturas.importe(tildadas[id] ?? "") : f.total
            guard let v, v > 0 else { error = "Falta cargar el importe de alguna OC"; return }
            imp[id] = v
        }
        importesAGuardar = imp
        let suma = imp.values.reduce(0, +)
        if ids.count > 1 && abs(suma - f.total) >= 0.05 {
            preguntaSuma = "La suma (\(Formato.pesos(suma))) no coincide con el total de la factura (\(Formato.pesos(f.total))). ¿Guardar igual?"
        } else {
            grabar()
        }
    }

    private func grabar() {
        guard let f else { return }
        let imp = importesAGuardar
        trabajando = true
        Task {
            let e = await store.guardarFacturaQR(num: f.num, total: f.total, cuit: f.cuit, importes: imp)
            trabajando = false
            if let e { error = e; return }
            store.aviso = "✅ Factura asociada a \(imp.count) OC"
            tildadasGuardadas = Array(imp.keys)
            paso = .guardada(imp.count)
            // Como al cargar la factura desde la ficha: con una sola OC, se abre para imprimir
            if imp.count == 1, let id = imp.keys.first, let o = store.ordenes.first(where: { $0.id == id }) {
                generarOC(o)
            }
        }
    }

    private func armarCombo(_ f: EnCurso) {
        guard let pdf else { return }
        let ids = tildadas.isEmpty ? tildadasGuardadas : Array(tildadas.keys)
        let ocs = store.ordenes.filter { ids.contains($0.id) }.sorted { $0.numeroEntero < $1.numeroEntero }
        do {
            let url = try PDFOC.combinado(ocs: ocs, factura: pdf, nombre: "OC + factura \(f.num)")
            combo = ArchivoPDF(url: url, titulo: "OC + factura \(f.num)")
        } catch {
            self.error = "No se pudo armar el PDF"
        }
    }

    /// "Generar OC" de la ficha: anota el PDF en el historial y abre Imprimir / WhatsApp / Mail.
    private func generarOC(_ o: OC) {
        trabajando = true
        Task {
            let e = store.puedeEditar ? await store.registrarPDF(o) : nil
            trabajando = false
            if let e { error = e } else { opcionesOC = o }
        }
    }

    private func correr(_ t: @escaping () async -> String?, ok: String) {
        trabajando = true
        Task {
            let e = await t()
            trabajando = false
            if let e { error = e } else { store.aviso = ok }
        }
    }
}
