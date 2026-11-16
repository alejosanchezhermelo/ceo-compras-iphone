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
    /// N° de OC que la factura nombra en su texto y que existen (v0.24). Solo vale si hay PDF.
    @State private var nombradasPDF: [String] = []
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
    /// v0.24: "Guardar y mandar a administración": el PDF "OC + factura" va directo al menú de compartir.
    @State private var compartirDirecto: ArchivoPDF?
    @State private var mandarAlGuardar = false
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
                    ic("receipt", "Cargar factura").font(T.syne(20)).foregroundStyle(T.bl)
                    // v0.24: llegaron más PDF mientras hay una factura a medio cargar: esperan su turno
                    if !enInicio && !store.pdfsEntrantes.isEmpty { cartelEnEspera }
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
            .conEncabezado()
            .fileImporter(isPresented: $elegirPDF, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { agregarElegidos($0) }
            .onChange(of: foto) { _, item in if let item { leerFoto(item) } }
            // v0.24: PDF que llegaron desde "Compartir" (o elegidos de a varios): se toma el próximo cuando la pantalla está libre
            .onChange(of: store.pdfsEntrantes.count, initial: true) { tomarDeLaCola() }
            .onChange(of: store.fase) { tomarDeLaCola() }
            .fullScreenCover(isPresented: $camara) { camaraVista }
            .fullScreenCover(isPresented: $pistolaAbierta) { PistolaFacturas(cargadas: $tanda) }
            .confirmationDialog("¿Vaciar la lista de esta tanda?", isPresented: $preguntaVaciar, titleVisibility: .visible) {
                Button("Vaciar la lista") { tanda = [] }
                Button("Cancelar", role: .cancel) {}
            } message: { Text("Las facturas quedan guardadas en sus OC; solo se borra esta lista.") }
            .sheet(item: $combo) { VisorPDF(archivo: $0) }
            .sheet(item: $compartirDirecto) { a in
                HojaCompartir(items: [a.url], alTerminar: { _, hecho in
                    if hecho { store.aviso = "✅ Factura guardada y compartida" }
                })
                .presentationDetents([.medium, .large])
            }
            .sheet(item: $opcionesOC) { OpcionesOC(oc: $0) }
            .alert(preguntaSuma ?? "", isPresented: Binding(get: { preguntaSuma != nil }, set: { if !$0 { preguntaSuma = nil } })) {
                Button("Guardar igual") { grabar() }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .vibrarAlError(error)
        }
    }

    // MARK: 1) Inicio: cómo entra la factura

    private var inicio: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Modo", selection: $modoPistola) {
                Text("Normal").tag(false)
                Text("Pistola").tag(true)
            }
            .pickerStyle(.segmented)
            if !store.pdfsEntrantes.isEmpty { colaEnInicio }
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
                        ic("qrcode.viewfinder", tanda.isEmpty ? "Empezar a escanear" : "Seguir escaneando").font(T.sans(16, .semibold))
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
            ic("checkmark.circle.fill", "\(tanda.count) factura\(tanda.count == 1 ? "" : "s") cargada\(tanda.count == 1 ? "" : "s") en esta tanda")
                .font(T.sans(15, .bold)).foregroundStyle(Color(hex: 0x065F46))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(tanda) { c in
                    Text("\(c.facNum) → OC \(c.ocNum) · \(c.proveedor)").font(T.sans(12)).foregroundStyle(Color(hex: 0x065F46)).lineLimit(1)
                }
            }
            Button {
                imprimirTanda()
            } label: {
                ic("printer", "Imprimir las \(ids.count) OC (un solo PDF)").font(T.sans(15, .semibold))
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
                Button { avisoCamara = nil; camara = true } label: { ic("camera", "Escanear el QR con la cámara").font(T.sans(15, .semibold)) }
                    .buttonStyle(BotonGrande(color: T.bl))
            }
            Button { elegirPDF = true } label: { ic("doc.text", "Elegir el PDF de la factura (uno o varios)").font(T.sans(14, .semibold)) }
                .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl)))
            PhotosPicker(selection: $foto, matching: .images) {
                ic("photo", "Elegir una captura o foto del QR").font(T.sans(14, .semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bl, lineWidth: 1))
                    .foregroundStyle(T.bl)
            }
            Button { abrirManual(texto: "", avisoQR: false) } label: { ic("square.and.pencil", "Cargar a mano").font(T.sans(13)) }
                .buttonStyle(BotonPWA(tipo: .blanco))
            ic("lightbulb", "Si la factura te llegó por mail, WhatsApp o Safari: mantené apretado el PDF, tocá Compartir y elegí \"Copiar a CEO Compras\". La app la lee sola y así después podés imprimir la OC y la factura juntas.")
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
                Button { abrirManual(texto: textoPDF, avisoQR: false) } label: { ic("square.and.pencil", "Cargar a mano") }.buttonStyle(BotonPWA())
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
                ic("exclamationmark.triangle", "El QR de esta factura no es válido.\nEl sistema del proveedor imprimió un QR que no corresponde a esta factura, así que no se puede usar. "
                     + (textoPDF.isEmpty ? "Completá los datos a mano y confirmá." : "Revisá los datos que tomé del PDF y confirmá."))
                    .font(T.sans(13)).foregroundStyle(Color(hex: 0x92400E))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 10))
            }
            ic("square.and.pencil", "Cargar factura a mano").font(T.sans(14, .bold)).foregroundStyle(T.bl)
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
            (f.fuente == "manual" ? ic("square.and.pencil", "CARGADA A MANO") : f.fuente == "camara" ? ic("camera", "QR ESCANEADO CON LA CÁMARA")
                 : f.fuente == "imagen" ? ic("photo", "QR LEÍDO DE LA IMAGEN") : ic("checkmark", "FACTURA LEÍDA DEL PDF"))
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
                Button {
                    correr({ await store.crearProveedor(val, cuit: f.cuit) }, ok: "✅ Proveedor creado con el CUIT")
                } label: { ic("plus", "Crear proveedor \"\(val)\"") }
                .font(T.sans(13, .semibold)).foregroundStyle(T.bl)
            }
        }
    }

    private func elegirOC(_ f: EnCurso, _ prov: FichaProveedor?) -> some View {
        let lista = store.ocsParaFactura(proveedor: prov, busqueda: busqueda, tildadas: Set(tildadas.keys))
        let n = tildadas.count
        // v0.24: la única OC tildada es una de las que nombra la factura (la detectó la lectura): hay botón para mandarla a administración
        let idsNombradas = Set(store.ocsDeNumeros(nombradas).map { $0.id })
        let porLectura = pdf != nil && n == 1 && tildadas.keys.contains(where: { idsNombradas.contains($0) })
        return VStack(alignment: .leading, spacing: 10) {
            (Text("¿A qué OC corresponde?").foregroundStyle(T.bl).bold()
             + Text(prov.map { " — \($0.nombre)" } ?? "").foregroundStyle(T.tx3))
                .font(T.sans(13))
            nombradasVista(f, prov)
            TextField("Buscar OC, obra o proveedor", text: $busqueda).campoPWA()
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
                Button { armarCombo(f) } label: { ic("printer", "Imprimir / compartir OC + factura") }
                    .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl))).disabled(n == 0)
            } else {
                Text("La factura entró sin el PDF (cámara o imagen), así que no se puede armar el PDF \"OC + factura\". La OC se imprime con su botón de siempre.")
                    .font(T.sans(12)).foregroundStyle(T.tx3)
                    .padding(10).background(T.sf2, in: RoundedRectangle(cornerRadius: 8))
            }
            if store.puedeEditar {
                if porLectura {
                    Button { mandarAlGuardar = true; guardar(f) } label: {
                        ic("paperplane.fill", "Guardar y mandar a administración").font(T.sans(15, .semibold))
                    }
                    .buttonStyle(BotonGrande(color: T.bl))
                    .disabled(trabajando)
                    Button("Guardar factura en las OC") { mandarAlGuardar = false; guardar(f) }
                        .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl)))
                        .disabled(trabajando)
                } else {
                    Button("Guardar factura en las OC") { mandarAlGuardar = false; guardar(f) }
                        .buttonStyle(BotonGrande(color: n == 0 ? T.bd : T.bl))
                        .disabled(n == 0 || trabajando)
                }
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
                    cartel("La suma coincide con el total de la factura", verde: true, icono: "checkmark.circle.fill")
                } else {
                    let dif = f.total - suma
                    cartel("Suma \(Formato.pesos(suma)) / Total \(Formato.pesos(f.total)) · \(dif > 0 ? "faltan" : "sobran") \(Formato.pesos(abs(dif)))", verde: false)
                }
            }
        }
    }

    private func cartel(_ t: String, verde: Bool, icono: String? = nil) -> some View {
        (icono.map { ic($0, t) } ?? Text(t)).font(T.sans(13, .semibold))
            .foregroundStyle(verde ? Color(hex: 0x065F46) : Color(hex: 0x92400E))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(verde ? Color(hex: 0xD1FAE5) : Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 8))
    }

    private func guardada(_ n: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ic("checkmark.circle.fill", "Factura \(f?.num ?? "") guardada en \(n) OC").font(T.sans(15, .bold)).foregroundStyle(Color(hex: 0x065F46))
            Text("Cada OC quedó con el N° de factura y su importe.").font(T.sans(12)).foregroundStyle(Color(hex: 0x065F46))
            if pdf != nil, let f {
                Button { armarCombo(f) } label: { ic("printer", "Imprimir / compartir OC + factura") }.buttonStyle(BotonPWA())
                tarjetaMensajeAdmin(f)
            }
            // Imprimir cada OC (como "Generar OC" de la ficha), aunque la factura haya entrado sin PDF
            ForEach(store.ordenes.filter { tildadasGuardadas.contains($0.id) }.sorted { $0.numeroEntero < $1.numeroEntero }) { o in
                Button { generarOC(o) } label: { ic("doc.text", "Imprimir OC \(o.num)") }
                    .buttonStyle(BotonPWA(tipo: .suave(T.blL, T.bl, T.blM)))
                    .disabled(trabajando)
            }
            if !store.pdfsEntrantes.isEmpty {
                Button { siguienteDeLaCola() } label: {
                    ic("arrow.right.circle.fill", "Siguiente factura (\(store.pdfsEntrantes.count) en espera)").font(T.sans(15, .semibold))
                }
                .buttonStyle(BotonGrande(color: T.bl))
            }
            Button { reiniciar() } label: { ic("plus", "Cargar otra factura") }.buttonStyle(BotonPWA(tipo: .blanco))
        }
        .padding(16)
        .background(Color(hex: 0xECFDF5), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: 0xA7F3D0)))
    }

    // MARK: La factura nombra una OC (v0.24)

    private var nombradas: [String] { pdf == nil ? [] : nombradasPDF }

    private enum EstadoNombrada {
        case tildada                        // quedó tildada: cartel azul
        case paraTildar                     // es del proveedor y no tiene factura, pero no está tildada (la destildó)
        case sumar                          // es del proveedor y ya tiene factura: se puede SUMAR esta
        case preguntarCuit(FichaProveedor)  // el CUIT de la factura no está en el padrón y esa OC es de un proveedor sin CUIT
        case otroProveedor                  // es de otro proveedor: aviso, sin tildar
        case sinConfirmar                   // no se pudo confirmar de qué proveedor es la factura: sin tildar
    }

    private func estadoNombrada(_ o: OC, _ f: EnCurso, _ prov: FichaProveedor?) -> EstadoNombrada {
        if tildadas[o.id] != nil { return .tildada }
        if let prov {
            if !store.esDeProveedor(o, prov) { return .otroProveedor }
            return o.tieneFactura ? .sumar : .paraTildar
        }
        // El CUIT de la factura no está en el padrón (o la factura no trae CUIT).
        guard !f.cuit.isEmpty, let fp = store.fichaProveedor(o) else { return .sinConfirmar }
        if !fp.cuit.isEmpty { return .otroProveedor }   // esa OC es de un proveedor que ya tiene OTRO CUIT
        guard !o.tieneFactura, store.puedeEditar,
              let ficha = store.fichasProveedores.first(where: { $0.id == fp.id }) else { return .sinConfirmar }
        return .preguntarCuit(ficha)
    }

    /// Las OC que nombra la factura, arriba de la lista: con la obra y el proveedor bien a la vista.
    @ViewBuilder private func nombradasVista(_ f: EnCurso, _ prov: FichaProveedor?) -> some View {
        let ocs = store.ocsDeNumeros(nombradas)
        if !ocs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ocs) { o in lineaNombrada(o, f, prov) }
            }
        }
    }

    @ViewBuilder private func lineaNombrada(_ o: OC, _ f: EnCurso, _ prov: FichaProveedor?) -> some View {
        switch estadoNombrada(o, f, prov) {
        case .tildada:
            cajaNombrada(azul: true) {
                textoNombra(o, "  →  la tildé. Revisá antes de guardar.")
            }
        case .paraTildar:
            cajaNombrada(azul: true) {
                textoNombra(o, ". Todavía no tiene factura.")
                Button("Tildar la OC \(o.num)") { tildar(o.id, true, f) }
                    .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl))).disabled(trabajando)
            }
        case .sumar:
            cajaNombrada(azul: false) {
                textoNombra(o, ". Esa OC ya tiene la factura \(o.facturaPrincipal?.num ?? "cargada"). ¿Esta es otra factura de la misma OC?")
                if !tildadas.isEmpty {
                    Text("Para sumarla a esta OC, primero destildá las otras OC de la lista: la factura entera se suma a una sola.")
                        .font(T.sans(12, .semibold))
                }
                Button("Sumar esta factura a la OC \(o.num)") { sumarEn(o, f) }
                    .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl)))
                    .disabled(trabajando || !store.puedeEditar || !tildadas.isEmpty)
            }
        case .preguntarCuit(let ficha):
            cajaNombrada(azul: false) {
                textoNombra(o, ". El CUIT de la factura (\(Facturas.fmtCuit(f.cuit))) no está en tu padrón, así que no la tildé. ¿Es de \(ficha.nombre)?")
                Button("Sí, tildar y anotar el CUIT") { vincularYTildar(o, ficha, f) }
                    .buttonStyle(BotonPWA(tipo: .suave(.white, T.bl, T.bl))).disabled(trabajando)
            }
        case .otroProveedor:
            cajaNombrada(azul: false) {
                textoNombra(o, ", pero esa OC es de un proveedor distinto al de esta factura. No la tildé. Si igual es esa, buscala abajo por número y tildala.")
            }
        case .sinConfirmar:
            cajaNombrada(azul: false) {
                textoNombra(o, ", pero no pude confirmar de qué proveedor es la factura, así que no la tildé. Si es esa, tildala abajo.")
            }
        }
    }

    /// Caja azul (la OC quedó tildada) o ámbar (hay que mirar algo).
    private func cajaNombrada<C: View>(azul: Bool, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { contenido() }
            .font(T.sans(13))
            .foregroundStyle(azul ? T.bl : Color(hex: 0x92400E))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(azul ? T.blL : Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(azul ? T.blM : Color(hex: 0xFCD34D)))
    }

    /// "La factura nombra la OC 1580 · Obra · Proveedor" + el resto; la obra y el proveedor van en negrita.
    private func textoNombra(_ o: OC, _ cola: String) -> Text {
        var t = Text("La factura nombra la ")
        t = t + Text("OC \(o.num)").bold()
        t = t + Text(" · ")
        t = t + Text(o.obra.isEmpty ? "sin obra" : o.obra).bold()
        t = t + Text(" · ")
        t = t + Text(o.proveedor.isEmpty ? "sin proveedor" : o.proveedor).bold()
        t = t + Text(cola)
        return t
    }

    /// La OC que nombra la factura ya tiene otra factura: se SUMA esta (igual que el modo pistola; nunca pisa la anterior).
    private func sumarEn(_ o: OC, _ f: EnCurso) {
        guard store.puedeEditar, !trabajando, tildadas.isEmpty else { return }
        trabajando = true
        Task {
            let r = await store.guardarFacturaPistola(o, num: f.num, total: f.total, cuit: f.cuit)
            trabajando = false
            if let e = r.error { error = e; return }
            store.aviso = "✅ Factura sumada a la OC \(o.num)"
            tildadas = [:]
            importesAGuardar = [o.id: f.total]
            tildadasGuardadas = [o.id]
            paso = .guardada(1)
            if pdf != nil { armarCombo(f) }
        }
    }

    /// "Sí, tildar y anotar el CUIT": se le anota el CUIT al proveedor de la OC (camino de "vincular") y se tilda la OC.
    private func vincularYTildar(_ o: OC, _ p: FichaProveedor, _ f: EnCurso) {
        guard !trabajando else { return }
        trabajando = true
        Task {
            let e = await store.vincularCuit(p, cuit: f.cuit)
            trabajando = false
            if let e { error = e; return }
            store.aviso = "✅ CUIT vinculado a \(p.nombre)"
            tildar(o.id, true, f)
        }
    }

    // MARK: Acciones

    private func reiniciar() {
        paso = .inicio; f = nil; pdf = nil; textoPDF = ""; tildadas = [:]; busqueda = ""; provEscrito = ""; foto = nil
        tildadasGuardadas = []
        nombradasPDF = []
        mandarAlGuardar = false
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

    // MARK: Cola de PDF (v0.24)

    private var enInicio: Bool {
        if case .inicio = paso { return true }
        return false
    }

    private var cartelEnEspera: some View {
        let n = store.pdfsEntrantes.count
        return ic("tray.full", "Hay \(n) factura\(n == 1 ? "" : "s") en espera. Cuando termines con esta, sigue la próxima.")
            .font(T.sans(12, .semibold)).foregroundStyle(T.bl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(T.blL, in: RoundedRectangle(cornerRadius: 8))
    }

    /// En el inicio con PDF esperando (no se tomaron solos, p. ej. porque se cerró algo recién): botón para seguir.
    private var colaEnInicio: some View {
        let n = store.pdfsEntrantes.count
        return VStack(alignment: .leading, spacing: 8) {
            ic("tray.full", "Hay \(n) factura\(n == 1 ? "" : "s") en espera").font(T.sans(14, .bold)).foregroundStyle(T.bl)
            Button { tomarDeLaCola() } label: { ic("arrow.right.circle.fill", "Leer la siguiente").font(T.sans(15, .semibold)) }
                .buttonStyle(BotonGrande(color: T.bl))
        }
        .padding(14)
        .background(T.blL, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.blM))
    }

    /// Toma el próximo PDF de la cola y lo lee, solo si la pantalla está libre (una factura a medio cargar NO se pisa:
    /// arriba avisa "Hay N en espera") y la app no está bloqueada con Face ID.
    private func tomarDeLaCola() {
        guard store.fase == .adentro, !store.pdfsEntrantes.isEmpty, enInicio else { return }
        camara = false; pistolaAbierta = false; elegirPDF = false   // si había algo abierto encima, se cierra
        let siguiente = store.pdfsEntrantes.removeFirst()
        procesarPDF(siguiente.datos)
    }

    /// Desde la pantalla "guardada": vuelve al inicio y sigue con la próxima de la cola.
    private func siguienteDeLaCola() {
        reiniciar()
        tomarDeLaCola()
    }

    /// El selector de Archivos (ahora de a varios): todo va a la misma cola.
    private func agregarElegidos(_ r: Result<[URL], Error>) {
        guard case .success(let urls) = r, !urls.isEmpty else { return }
        var leidos = 0
        for url in urls {
            let acceso = url.startAccessingSecurityScopedResource()
            defer { if acceso { url.stopAccessingSecurityScopedResource() } }
            guard let datos = try? Data(contentsOf: url) else { continue }
            if store.encolarPDF(datos, nombre: url.deletingPathExtension().lastPathComponent) { leidos += 1 }
        }
        if leidos == 0 { paso = .aviso("No se pudo abrir el archivo.") }
    }

    /// Lee el PDF de una factura (QR de AFIP + texto). Antes era `leerPDF`, que leía el archivo elegido.
    private func procesarPDF(_ datos: Data) {
        paso = .leyendo
        let validos = store.numerosDeOC()
        Task {
            let res = await Task.detached(priority: .userInitiated) { LectorQR.leerPDF(datos) }.value
            // v0.24: ¿la factura dice a qué OC corresponde? (texto del PDF y, si ahí no aparece, la hoja leída como imagen)
            var nombradas: [String] = []
            var hayPDFValido = true
            if case .noEsAfip = res { hayPDFValido = false }
            if hayPDFValido {
                let texto = res.textoDelPDF
                nombradas = await Task.detached(priority: .userInitiated) {
                    LectorQR.ocsNombradasEn(datos, texto: texto, validos: validos)
                }.value
            }
            pdf = datos
            nombradasPDF = nombradas
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
        // v0.24: la factura nombra una OC: si es del proveedor y todavía no tiene factura, queda tildada (y se avisa arriba).
        // Si el proveedor no se conoce, o la OC es de otro, NO se tilda nada: arriba se explica por qué.
        if pdf != nil, let prov = store.proveedorPorCuit(e.cuit) {
            let aTildar = store.ocsDeNumeros(nombradasPDF).filter { !$0.tieneFactura && store.esDeProveedor($0, prov) }
            for o in aTildar { tildadas[o.id] = aTildar.count == 1 ? textoImporte(e.total) : "" }
        }
        paso = .flujo
    }

    private func textoImporte(_ n: Double) -> String {
        String(format: "%.2f", n).replacingOccurrences(of: ".", with: ",")
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
        guard !trabajando else { return }   // un segundo toque no guarda dos veces
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
        guard let f, !trabajando else { return }
        let imp = importesAGuardar
        let mandar = mandarAlGuardar
        mandarAlGuardar = false
        trabajando = true
        Task {
            // v0.24: antes de escribir se mira en la base si alguna OC ya tiene factura (la copia en memoria puede venir atrasada)
            let e = await store.guardarFacturaSinPisar(num: f.num, total: f.total, cuit: f.cuit, importes: imp)
            trabajando = false
            if let e { error = e; return }
            store.aviso = "✅ Factura asociada a \(imp.count) OC"
            tildadasGuardadas = Array(imp.keys)
            paso = .guardada(imp.count)
            if imp.count == 1 {
                if pdf != nil {
                    // v0.24: con el PDF de la factura se abre directo "OC + factura" con el mensaje para administración
                    // (o, con "Guardar y mandar a administración", directo el menú de compartir)
                    armarCombo(f, compartirYa: mandar)
                } else if let id = imp.keys.first, let o = store.ordenes.first(where: { $0.id == id }) {
                    // Sin PDF (cámara, foto, a mano): como al cargar la factura desde la ficha, se abre la OC para imprimir
                    generarOC(o)
                }
            }
        }
    }

    /// Las OC de esta factura (las tildadas o, ya guardada, las guardadas), por número.
    private func ocsDeLaFactura() -> [OC] {
        let ids = tildadas.isEmpty ? tildadasGuardadas : Array(tildadas.keys)
        return store.ordenes.filter { ids.contains($0.id) }.sorted { $0.numeroEntero < $1.numeroEntero }
    }

    /// Texto para administración: obra a imputar, proveedor, factura y OC (`Facturas.mensajeAdmin`).
    private func mensajeParaAdmin(_ f: EnCurso, _ ocs: [OC]) -> String {
        let prov = store.proveedorPorCuit(f.cuit)
        let datos = ocs.map { o in
            Facturas.OCParaMensaje(num: o.num, obra: o.obra,
                                   importe: ocs.count > 1 ? Facturas.importe(tildadas[o.id] ?? "") : f.total)
        }
        return Facturas.mensajeAdmin(factura: f.num, total: f.total, proveedor: prov?.nombre ?? ocs.first?.proveedor ?? "",
                                     cuit: f.cuit, ocs: datos)
    }

    /// El mensaje a la vista (por si hay que pegarlo de nuevo) y un botón para copiarlo.
    private func tarjetaMensajeAdmin(_ f: EnCurso) -> some View {
        let msg = mensajeParaAdmin(f, ocsDeLaFactura())
        return VStack(alignment: .leading, spacing: 6) {
            Rotulo(texto: "Mensaje para administración")
            Text(msg).font(T.mono(12)).foregroundStyle(T.tx)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                UIPasteboard.general.string = msg
                store.aviso = "✅ Mensaje copiado: pegalo en WhatsApp"
            } label: { ic("doc.on.doc", "Copiar el mensaje") }
                .buttonStyle(BotonPWA(tipo: .blanco))
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bd))
    }

    /// Arma el PDF "OC + factura" (con el mensaje para administración). `compartirYa`: lo manda directo al menú de
    /// compartir y deja el mensaje copiado (para pegarlo en WhatsApp); si no, se abre el visor.
    private func armarCombo(_ f: EnCurso, compartirYa: Bool = false) {
        guard let pdf else { return }
        let ocs = ocsDeLaFactura()
        do {
            let url = try PDFOC.combinado(ocs: ocs, factura: pdf, nombre: "OC + factura \(f.num)")
            let mensaje = mensajeParaAdmin(f, ocs)
            let archivo = ArchivoPDF(url: url, titulo: "OC + factura \(f.num)", mensaje: mensaje)
            if compartirYa {
                UIPasteboard.general.string = mensaje
                store.aviso = "✅ Mensaje copiado: pegalo en WhatsApp"
                compartirDirecto = archivo
            } else {
                combo = archivo
            }
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
