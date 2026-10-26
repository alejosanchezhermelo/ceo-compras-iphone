import SwiftUI
import AudioToolbox

/// Una factura cargada en la tanda del modo pistola.
struct CargadaPistola: Identifiable, Equatable {
    let id = UUID()
    let facNum: String
    let total: Double
    let ocId: String
    let ocNum: String
    let proveedor: String
    let obra: String
}

/// Modo pistola (pedido de Alejo 2026-10-26): la cámara queda prendida; apuntás al QR de AFIP,
/// tocás la OC y queda guardada (1 OC = el total de la factura). Enseguida está lista para la próxima.
/// Las OC se imprimen todas juntas al final, desde la pestaña Facturas.
struct PistolaFacturas: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var cargadas: [CargadaPistola]

    enum Estado: Equatable { case esperando, factura, manual }
    typealias EnCurso = PantallaFacturas.EnCurso

    @State private var estado: Estado = .esperando
    @State private var f: EnCurso?
    @State private var busqueda = ""
    @State private var flash: String?
    @State private var flashOK = true
    @State private var flashId = 0
    @State private var trabajando = false
    @State private var error: String?
    @State private var aDeshacer: CargadaPistola?
    // carga a mano (QR trucho o sin QR)
    @State private var qrTrucho = false
    @State private var mPv = ""
    @State private var mCmp = ""
    @State private var mTot = ""

    var body: some View {
        VStack(spacing: 0) {
            barraArriba
            ZStack(alignment: .bottom) {
                EscanerQR { recibir($0) }
                if estado != .esperando {
                    Color.black.opacity(0.45)
                    Text("En pausa: elegí la OC de esta factura").font(T.sans(13, .semibold)).foregroundStyle(.white)
                        .frame(maxHeight: .infinity)
                }
                if let flash {
                    Text(flash).font(T.sans(14, .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                        .padding(12).frame(maxWidth: .infinity)
                        .background((flashOK ? Color(hex: 0x15803D) : Color(hex: 0xB91C1C)).opacity(0.92),
                                    in: RoundedRectangle(cornerRadius: 10))
                        .padding(12)
                        .transition(.opacity)
                }
            }
            .frame(height: estado == .esperando ? 330 : 150)
            .clipped()
            .animation(.easeInOut(duration: 0.2), value: estado)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch estado {
                    case .esperando: esperando
                    case .factura: factura
                    case .manual: manual
                    }
                }
                .padding(14)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(T.bg)
        .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
        .confirmationDialog(aDeshacer.map { "¿Deshacer la factura \($0.facNum) de la OC \($0.ocNum)?" } ?? "",
                            isPresented: Binding(get: { aDeshacer != nil }, set: { if !$0 { aDeshacer = nil } }),
                            titleVisibility: .visible) {
            Button("Deshacer", role: .destructive) { if let c = aDeshacer { deshacer(c) } }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: Partes de la pantalla

    private var barraArriba: some View {
        VStack(spacing: 0) {
            if store.modoPrueba { FranjaPrueba() }
            HStack {
                Text("🔫 Modo pistola").font(T.syne(17)).foregroundStyle(T.bl)
                Text("\(cargadas.count) cargada\(cargadas.count == 1 ? "" : "s")")
                    .font(T.sans(12, .semibold)).foregroundStyle(T.gn)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(T.gnL, in: Capsule())
                Spacer()
                Button("Terminar") { dismiss() }
                    .font(T.sans(15, .semibold)).foregroundStyle(T.bl)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .background(T.sf)
    }

    private var esperando: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Apuntá al QR de AFIP de la próxima factura").font(T.sans(15, .bold)).foregroundStyle(T.bl)
            Text("Cuando la lea vas a escuchar un bip. Después tocás la OC y listo.").font(T.sans(12)).foregroundStyle(T.tx3)
            Button("✍️ Esta factura no tiene QR: cargar a mano") { abrirManual(trucho: false) }
                .buttonStyle(BotonPWA(tipo: .blanco))
            if !cargadas.isEmpty {
                Text("CARGADAS EN ESTA TANDA").font(T.mono(11, .medium)).foregroundStyle(T.tx3).padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(cargadas.reversed()) { c in
                        HStack(spacing: 8) {
                            Text("✓").foregroundStyle(T.gn).bold()
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(c.facNum) → OC \(c.ocNum)").font(T.mono(12, .medium)).foregroundStyle(T.tx)
                                Text(c.proveedor + (c.obra.isEmpty ? "" : " · \(c.obra)") + " · " + Formato.pesos(c.total))
                                    .font(T.sans(11)).foregroundStyle(T.tx3).lineLimit(1)
                            }
                            Spacer()
                            Button("Deshacer") { aDeshacer = c }
                                .font(T.sans(12)).foregroundStyle(T.rd).disabled(trabajando)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .overlay(alignment: .bottom) { Rectangle().fill(T.bd).frame(height: 1) }
                    }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bd))
                Text("Cuando termines, tocá \"Terminar\": en la pestaña Facturas vas a tener el botón para imprimir todas las OC juntas.")
                    .font(T.sans(12)).foregroundStyle(T.tx3)
            }
        }
        .padding(14)
        .tarjeta()
    }

    @ViewBuilder private var factura: some View {
        if let f {
            let prov = store.proveedorPorCuit(f.cuit)
            let lista = listaOC(prov)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(f.num).font(T.mono(15, .medium)).foregroundStyle(T.tx)
                    Spacer()
                    Text(Formato.pesos(f.total)).font(T.sans(16, .bold)).foregroundStyle(T.tx)
                }
                if let prov {
                    Text(prov.nombre).font(T.sans(14, .bold)).foregroundStyle(T.gn)
                } else {
                    Text(f.cuit.isEmpty ? "Proveedor sin CUIT: buscá la OC por proveedor, obra o número."
                                        : "El CUIT \(Facturas.fmtCuit(f.cuit)) no está en el padrón: buscá la OC por proveedor, obra o número. Al elegirla, le anoto el CUIT a ese proveedor (si no tenía).")
                        .font(T.sans(12)).foregroundStyle(T.am)
                }
                TextField("🔍 Buscar OC, obra o proveedor", text: $busqueda).campoPWA()
                Text(lista.isEmpty ? "No hay OC sin factura para mostrar. Probá el buscador."
                                   : "Tocá la OC de esta factura (se le asigna el total; si la OC ya tiene otra factura, se suman):")
                    .font(T.sans(12)).foregroundStyle(T.tx3)
                VStack(spacing: 6) {
                    ForEach(lista.prefix(40)) { o in
                        Button { guardarEn(o) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("OC \(o.num)").font(T.syne(15)).foregroundStyle(T.bl)
                                    Text((o.obra.isEmpty ? "—" : o.obra) + (o.proveedor.isEmpty ? "" : " · \(o.proveedor)"))
                                        .font(T.sans(12)).foregroundStyle(T.tx2).lineLimit(1)
                                    if let ya = facturaPrevia(o) {
                                        Text("Ya tiene la \(ya) · esta se SUMA").font(T.sans(11, .semibold)).foregroundStyle(T.am)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle").font(.system(size: 22)).foregroundStyle(T.bl)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 11)
                            .background(T.blL, in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(T.blM))
                        }
                        .buttonStyle(.plain)
                        .disabled(trabajando)
                    }
                }
                if trabajando { HStack { ProgressView(); Text("Guardando…").font(T.sans(13)).foregroundStyle(T.bl) } }
                Text("¿Va repartida en varias OC? Salteala y cargala en modo Normal.").font(T.sans(12)).foregroundStyle(T.tx3)
                Button("Saltear esta factura") { volverAEsperar() }.buttonStyle(BotonPWA(tipo: .blanco)).disabled(trabajando)
            }
            .padding(14)
            .tarjeta()
        }
    }

    private var manual: some View {
        VStack(alignment: .leading, spacing: 12) {
            if qrTrucho {
                Text("⚠️ El QR de esta factura no es válido (el sistema del proveedor imprime uno que no corresponde). Cargá el número y el total a mano.")
                    .font(T.sans(13)).foregroundStyle(Color(hex: 0x92400E))
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xFEF3C7), in: RoundedRectangle(cornerRadius: 10))
            }
            Text("✍️ Factura a mano").font(T.sans(14, .bold)).foregroundStyle(T.bl)
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
                Button("Cancelar") { volverAEsperar() }.buttonStyle(BotonPWA(tipo: .blanco))
            }
        }
        .padding(14)
        .tarjeta()
    }

    // MARK: Acciones

    private func recibir(_ leido: String) {
        guard estado == .esperando, !trabajando else { return }
        switch LectorQR.evaluar([leido], texto: "") {
        case .ok(let d, _):
            let cuit = LectorQR.cuitProveedor(texto: "", qrCuit: d.cuitQR, receptor: d.receptor)
            empezar(EnCurso(num: d.num, total: d.total, cuit: cuit, fuente: "camara"))
        case .qrInvalido:
            vibrar(.warning)
            abrirManual(trucho: true)
        default:
            mostrar("Ese QR no es el de AFIP. Apuntá al QR del pie de la factura.", ok: false)
        }
    }

    private func empezar(_ e: EnCurso) {
        // la misma hoja todavía delante de la cámara
        if cargadas.contains(where: { Facturas.mismoNum($0.facNum, e.num) && abs($0.total - e.total) < 0.05 }) {
            mostrar("✓ La \(e.num) ya la cargaste en esta tanda", ok: true)
            return
        }
        let dup = Facturas.yaCargada(e.num, cuit: e.cuit, total: e.total, en: store.ordenes)
        if !dup.isEmpty {
            vibrar(.error)
            mostrar("⚠ La factura \(e.num) ya estaba cargada en " + dup.map { "OC \($0.num)" }.joined(separator: ", "),
                    ok: false, segundos: 4)
            return
        }
        AudioServicesPlaySystemSound(1057)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        f = e
        busqueda = ""
        flash = nil
        estado = .factura
    }

    private func abrirManual(trucho: Bool) {
        qrTrucho = trucho
        mPv = ""; mCmp = ""; mTot = ""
        flash = nil
        estado = .manual
    }

    private func confirmarManual() {
        let pv = Facturas.soloDigitos(mPv), cmp = Facturas.soloDigitos(mCmp)
        if pv.isEmpty || cmp.isEmpty { error = "Completá las dos partes del número de factura."; return }
        guard let total = Facturas.importe(mTot), total > 0 else { error = "Cargá un importe total válido (ej: 131970,34)."; return }
        estado = .esperando
        empezar(EnCurso(num: LectorQR.formatoNumero(pv, cmp), total: total, cuit: "", fuente: "manual"))
    }

    private func volverAEsperar() {
        f = nil
        busqueda = ""
        estado = .esperando
    }

    /// Guarda la factura entera en esa OC (igual que el modo normal con 1 sola OC tildada).
    private func guardarEn(_ o: OC) {
        guard let f, !trabajando else { return }
        trabajando = true
        Task {
            let r = await store.guardarFacturaPistola(o, num: f.num, total: f.total, cuit: f.cuit)
            if let e = r.error {
                trabajando = false
                vibrar(.error)
                error = e
                return
            }
            // CUIT nuevo: se le anota al proveedor de la OC si no tenía (como "vincular" del modo normal)
            var extra = ""
            if !f.cuit.isEmpty, store.proveedorPorCuit(f.cuit) == nil,
               let fp = store.fichaProveedor(o), fp.cuit.isEmpty, !fp.id.isEmpty,
               await store.ejecutar(["provData/\(fp.id)/cuit": f.cuit]) == nil {
                extra = "\nCUIT anotado en \(fp.nombre)"
            }
            trabajando = false
            cargadas.append(CargadaPistola(facNum: f.num, total: f.total, ocId: o.id, ocNum: o.num,
                                           proveedor: o.proveedor, obra: o.obra))
            vibrar(.success)
            volverAEsperar()
            mostrar((r.cantidad > 1 ? "✓ \(f.num) SUMADA a OC \(o.num) (ahora tiene \(r.cantidad) facturas)"
                                    : "✓ \(f.num) → OC \(o.num)") + extra, ok: true)
        }
    }

    private func deshacer(_ c: CargadaPistola) {
        guard let o = store.ordenes.first(where: { $0.id == c.ocId }) else {
            cargadas.removeAll { $0.id == c.id }
            return
        }
        trabajando = true
        Task {
            let e = await store.quitarFacturaPistola(o, num: c.facNum)
            trabajando = false
            if let e { error = e; return }
            cargadas.removeAll { $0.id == c.id }
            mostrar("Factura \(c.facNum) sacada de la OC \(c.ocNum)", ok: true)
        }
    }

    /// OC sin factura del proveedor (o de la búsqueda) + las de esta tanda que coinciden, para poder sumarles otra.
    private func listaOC(_ prov: FichaProveedor?) -> [OC] {
        let enTanda = Set(cargadas.map(\.ocId))
        let q = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        let deTanda = store.ordenes.filter { o in
            guard enTanda.contains(o.id) else { return false }
            if !q.isEmpty {
                return o.num.lowercased().contains(q) || o.proveedor.lowercased().contains(q) || o.obra.lowercased().contains(q)
            }
            guard let p = prov else { return true }
            return o.provIdGuardado == p.id || (!o.proveedor.isEmpty && o.proveedor.lowercased() == p.nombre.lowercased())
        }
        let resto = store.ocsParaFactura(proveedor: prov, busqueda: busqueda, tildadas: []).filter { !enTanda.contains($0.id) }
        return deTanda.sorted { $0.numeroEntero > $1.numeroEntero } + resto
    }

    /// N° de la factura que ya tiene la OC (de esta tanda o de la base), si tiene.
    private func facturaPrevia(_ o: OC) -> String? {
        if let c = cargadas.last(where: { $0.ocId == o.id }) { return c.facNum }
        return o.tieneFactura ? (o.facturaPrincipal?.num ?? "factura") : nil
    }

    private func mostrar(_ t: String, ok: Bool, segundos: Double = 2.2) {
        flashId += 1
        let mio = flashId
        withAnimation { flash = t; flashOK = ok }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(segundos * 1_000_000_000))
            if flashId == mio { withAnimation { flash = nil } }
        }
    }

    private func vibrar(_ t: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(t)
    }
}

// MARK: Guardar / deshacer en modo pistola

extension Store {
    /// Facturas de una OC leídas del nodo crudo de la base (misma regla que `OC`).
    nonisolated static func facturasDe(_ d: [String: Any]) -> [FacturaOC] {
        func fac(_ v: Any) -> FacturaOC? {
            guard let f = v as? [String: Any] else { return nil }
            return FacturaOC(num: texto(f["num"]), importe: numero(f["importe"]), cuit: texto(f["cuit"]),
                             total: numero(f["total"]), ts: numero(f["ts"]))
        }
        guard verdadero(d["factura"]), let f = d["factura"].flatMap(fac) else { return [] }
        let varias = JSONTree.lista(d["facturas"]).compactMap(fac)
        return varias.isEmpty ? [f] : varias
    }

    /// Lee la OC de la base EN ESE MOMENTO (la copia en memoria puede venir atrasada unos segundos:
    /// así se pisó la 0028-00112426 de la OC 1572 el 26/10).
    private func facturasEnLaBase(_ o: OC) async throws -> [FacturaOC] {
        let (v, _) = try await Firebase.shared.leerConHuella(prefijo + "ordenes/\(o.id)")
        return (v as? [String: Any]).map { Store.facturasDe($0) } ?? []
    }

    /// Modo pistola: si la OC no tiene factura, la guarda (`guardarFacturaQR`); si ya tiene, la SUMA
    /// (como `sumarFactura`: lista `facturas` + resumen con N° combinado e importe sumado). Nunca pisa.
    func guardarFacturaPistola(_ o: OC, num: String, total: Double, cuit: String) async -> (error: String?, cantidad: Int) {
        let previas: [FacturaOC]
        do { previas = try await facturasEnLaBase(o) } catch {
            return ("No se pudo revisar la OC. Revisá la conexión e intentá de nuevo.", 0)
        }
        if previas.isEmpty {
            return (await guardarFacturaQR(num: num, total: total, cuit: cuit, importes: [o.id: total]), 1)
        }
        if previas.contains(where: { Facturas.mismoNum($0.num, num) }) {
            return ("La factura \(num) ya está cargada en la OC \(o.num).", 0)
        }
        let ahora = Store.ahoraMs()
        let lista = previas + [FacturaOC(num: num, importe: total, cuit: cuit, total: total, ts: Double(ahora))]
        let d = Facturas.datos(lista, ahora: ahora)
        var cambios: [String: Any] = [:]
        for (k, v) in d { cambios["ordenes/\(o.id)/\(k)"] = v }
        let totalNuevo = ((d["factura"] as? [String: Any])?["importe"] as? Double) ?? total
        let (h, e) = evento("🧾 Factura \(num) (\(Formato.pesos(total))) sumada a OC \(o.num) — total \(Formato.pesos(totalNuevo))",
                            tipo: "c", ocId: o.id, ts: ahora)
        cambios[h] = e
        return (await ejecutar(cambios), lista.count)
    }

    /// Deshacer en modo pistola: saca SOLO esa factura de la OC (las otras quedan).
    func quitarFacturaPistola(_ o: OC, num: String) async -> String? {
        let previas: [FacturaOC]
        do { previas = try await facturasEnLaBase(o) } catch {
            return "No se pudo revisar la OC. Revisá la conexión e intentá de nuevo."
        }
        guard let i = previas.firstIndex(where: { Facturas.mismoNum($0.num, num) }) else { return nil }
        var lista = previas
        lista.remove(at: i)
        var cambios: [String: Any] = [:]
        for (k, v) in Facturas.datos(lista, ahora: Store.ahoraMs()) { cambios["ordenes/\(o.id)/\(k)"] = v }
        let (h, e) = evento(lista.isEmpty ? "🧾 Factura quitada de OC \(o.num)" : "🧾 Factura \(num) sacada de OC \(o.num)",
                            tipo: "c", ocId: o.id)
        cambios[h] = e
        return await ejecutar(cambios)
    }
}

// MARK: Imprimir la tanda en un solo PDF

extension Store {
    /// Como "Generar OC" de cada una (`registrarPDF`), pero todas juntas en un solo guardado:
    /// las OC sin número de PDF reciben números seguidos (no se pisan entre sí).
    func registrarPDFsTanda(_ ocs: [OC]) async -> (nums: [String: Int], error: String?) {
        var nums: [String: Int] = [:]
        var cambios: [String: Any] = [:]
        var siguiente = nextOCNum
        var mayorNuevo = 0
        let ahora = Store.ahoraMs()
        for (i, o) in ocs.enumerated() {
            var n = o.numOCPDF ?? 0
            if o.numOCPDF == nil {
                n = siguiente
                siguiente += 1
                mayorNuevo = max(mayorNuevo, n)
                cambios["ordenes/\(o.id)/numOCPDF"] = n
            }
            nums[o.id] = n
            let (h, e) = evento("OC PDF No \(n) generada - \(o.proveedor.isEmpty ? "sin proveedor" : o.proveedor)",
                                tipo: "c", ocId: o.id, ts: ahora + Int64(i))
            cambios[h] = e
        }
        if let err = await ejecutar(cambios) { return ([:], err) }
        if mayorNuevo > 0 { try? await subirProximoNumero(String(mayorNuevo), prefijo) }
        return (nums, nil)
    }
}

extension PDFOC.Datos {
    init(oc: OC, num n: Int) {
        num = n
        proveedor = oc.proveedor
        obra = oc.obra
        responsable = oc.responsable
        notas = oc.notas
        fecha = oc.fecha.isEmpty ? Formato.hoy() : oc.fecha.split(separator: "-").reversed().joined(separator: "/")
        items = oc.items
    }
}

extension PDFOC {
    /// Todas las OC de la tanda, una por hoja, en el orden en que se escanearon las facturas.
    static func tanda(_ pares: [(OC, Int)], nombre: String) throws -> URL {
        let formato = UIGraphicsPDFRendererFormat()
        formato.documentInfo = [kCGPDFContextTitle as String: nombre, kCGPDFContextCreator as String: "CEO Compras"]
        let render = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 210 * mm, height: 297 * mm), format: formato)
        let data = render.pdfData { ctx in
            for (o, n) in pares {
                ctx.beginPage()
                dibujar(Datos(oc: o, num: n), ctx)
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nombre + ".pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}
