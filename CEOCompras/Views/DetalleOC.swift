import SwiftUI

/// Lo que se ve al abrir una OC en la lista (`.ocb` de `cardOC` en la PWA): se despliega ahí mismo,
/// debajo de la tarjeta, igual que en la web. Se actualiza solo si la cambian desde la PC.
struct CuerpoOC: View {
    @Environment(Store.self) private var store
    let oc: OC

    @State private var editar = false
    @State private var opcionesPDF: OC?
    @State private var notaNueva = ""
    @State private var facNum = ""
    @State private var facMonto = ""
    @State private var facCuit = ""
    @State private var trabajando = false
    @State private var error: String?
    @State private var pregunta: Pregunta?

    /// Una pregunta de confirmación (`showConfirm` de la web).
    struct Pregunta: Identifiable {
        let id = UUID()
        let titulo: String
        let boton: String
        var destructiva = false
        let accion: () -> Void
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !oc.solRef.isEmpty {
                Text("📋 Solicitud de \(oc.solRef)").font(T.mono(11)).foregroundStyle(T.pp)
            }
            if !oc.notas.isEmpty { CajaNotas(texto: oc.notas) }
            materiales
            if !oc.comentario.isEmpty {
                (Text("⚠ Faltantes: ").bold() + Text(oc.comentario))
                    .font(T.sans(13)).foregroundStyle(T.rd)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(T.rdL, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.rdM, lineWidth: 1))
            }
            if !oc.remito.isEmpty {
                (Text("🧾 Remito N° ") + Text(oc.remito).bold()
                 + Text(oc.fechaEntregaReal.isEmpty ? "" : " · Entregado el \(oc.fechaEntregaReal)"))
                    .font(T.sans(13)).foregroundStyle(T.gn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(T.gnL, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.gnM, lineWidth: 1))
            }
            notasInternas
            historial
            if store.puedeEditar { facturas }
            acciones
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $editar) { FormularioOC(editando: oc, numeroSugerido: store.nextOCNum) }
        .sheet(item: $opcionesPDF) { o in OpcionesOC(oc: o) }
        .alert(pregunta?.titulo ?? "", isPresented: Binding(get: { pregunta != nil }, set: { if !$0 { pregunta = nil } }),
               presenting: pregunta) { p in
            Button(p.boton, role: p.destructiva ? .destructive : nil) { p.accion() }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: Materiales (`.itbl` de la PWA)

    private var materiales: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rotulo(texto: "Materiales")
            VStack(spacing: 0) {
                HStack {
                    Text("Descripción").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Cant.").frame(width: 56)
                    Text("Unidad").frame(width: 56, alignment: .leading)
                }
                .font(T.mono(11)).foregroundStyle(T.tx3)
                .padding(.vertical, 5)
                .overlay(alignment: .bottom) { Rectangle().fill(T.bd).frame(height: 1) }
                if oc.items.isEmpty {
                    Text("Sin ítems").font(T.sans(13)).foregroundStyle(T.tx3)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
                }
                ForEach(oc.items) { it in
                    HStack(alignment: .firstTextBaseline) {
                        Text(it.desc).frame(maxWidth: .infinity, alignment: .leading)
                        Text(it.cant).frame(width: 56)
                        Text(it.unit).foregroundStyle(T.tx3).frame(width: 56, alignment: .leading)
                    }
                    .font(T.sans(13)).foregroundStyle(T.tx)
                    .padding(.vertical, 6)
                    .overlay(alignment: .bottom) {
                        if it.id != oc.items.last?.id { Rectangle().fill(T.bd).frame(height: 1) }
                    }
                }
            }
        }
    }

    // MARK: Notas internas

    private var notasInternas: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(T.bd)
            Text("🔒 NOTAS INTERNAS (SOLO COMPRAS)").font(T.mono(10, .medium)).kerning(0.7).foregroundStyle(T.am)
            ForEach(Array(oc.notasInternas.enumerated()), id: \.offset) { _, n in
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.txt).font(T.sans(13)).foregroundStyle(T.tx)
                    if let ts = n.ts { Text(Formato.fechaHora(ts)).font(T.mono(10)).foregroundStyle(T.tx3) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(T.amL, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.amM, lineWidth: 1))
            }
            if store.puedeEditar {
                HStack(spacing: 6) {
                    TextField("Agregar nota interna…", text: $notaNueva).campoPWA()
                    Button("Agregar") { agregarNota() }
                        .buttonStyle(BotonPWA(tipo: .color(T.am))).fixedSize()
                        .disabled(notaNueva.trimmingCharacters(in: .whitespaces).isEmpty || trabajando)
                }
            }
        }
    }

    // MARK: Historial

    private var historial: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(T.bd).padding(.bottom, 10)
            Text("📋 HISTORIAL DE ESTA OC").font(T.mono(10, .medium)).kerning(0.7).foregroundStyle(T.tx3)
                .padding(.bottom, 2)
            let evs = store.eventosPorOC[oc.id] ?? []
            if evs.isEmpty {
                Text("Sin eventos registrados").font(T.sans(12)).foregroundStyle(T.tx3).padding(.vertical, 6)
            }
            ForEach(evs) { FilaEvento(ev: $0) }
        }
    }

    // MARK: Facturas (`facQ` de la PWA)

    private var facturas: some View {
        let sinCuit = (store.fichaProveedor(oc).map { $0.cuit.isEmpty }) ?? false
        return VStack(alignment: .leading, spacing: 8) {
            Text(oc.tieneFactura ? "🧾 FACTURAS DE ESTA OC" : "🧾 FACTURA DE ESTA OC")
                .font(T.mono(11, .medium)).kerning(0.5).foregroundStyle(T.tx2)
            if oc.tieneFactura {
                ForEach(Array(oc.facturas.enumerated()), id: \.offset) { i, f in
                    HStack {
                        Text(f.num + (f.importe.map { " — " + Formato.pesos($0) } ?? "")).font(T.sans(13))
                        Spacer()
                        Button {
                            preguntarSacar(i, f)
                        } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(T.rd) }
                    }
                    .padding(.vertical, 3)
                    .overlay(alignment: .bottom) { Rectangle().fill(T.bd).frame(height: 1) }
                }
                if oc.totalFacturado > 0 {
                    Text("Total facturado: \(Formato.pesos(oc.totalFacturado))").font(T.sans(13, .bold)).padding(.vertical, 4)
                }
            }
            TextField(oc.tieneFactura ? "N° de otra factura" : "N° de factura (ej: 0003-00012345)", text: $facNum)
                .campoPWA()
            TextField(oc.tieneFactura ? "Monto" : "Monto (ej: 131.970,34)", text: $facMonto)
                .keyboardType(.decimalPad).campoPWA()
            if !oc.tieneFactura && sinCuit {
                TextField("CUIT del proveedor (opcional)", text: $facCuit).keyboardType(.numberPad).campoPWA()
            }
            Button(oc.tieneFactura ? "➕ Sumar factura" : "Guardar") { cargarFactura() }
                .buttonStyle(BotonPWA())
                .disabled(trabajando)
            Text(oc.tieneFactura
                 ? "Para una factura que llegó después sobre esta misma OC. En el Excel el N° queda con \"/\" (ej: 0003-00012345/98) y el importe sumado."
                 : "Al guardar se abre la OC para imprimir o compartir. Con esto cargado, ACTUALIZAR EXCEL completa solo el importe y el N° de factura en el maestro.")
                .font(T.sans(11)).foregroundStyle(T.tx3)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(T.sf2, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.bd, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    // MARK: Botones de abajo (`cActs` de la PWA): en una fila, mismo orden que la web

    private var acciones: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(T.bd)
            Renglones(espacio: 8) {
                Button("📄 Generar OC") { generar() }
                    .buttonStyle(BotonPWA(tipo: .suave(T.blL, T.bl, T.blM), lleno: false))
                if store.puedeEditar {
                    if oc.tieneFactura {
                        Button("🧾 Quitar factura") { preguntarQuitarTodas() }
                            .buttonStyle(BotonPWA(tipo: .suave(T.blL, T.bl, T.blM), lleno: false))
                    }
                    if oc.estado != "entregado" {
                        Button("✏️ Editar") { editar = true }
                            .buttonStyle(BotonPWA(tipo: .suave(T.blL, T.bl, T.blM), lleno: false))
                        if oc.urgente {
                            Button("✓ Quitar urgente") { urgente() }
                                .buttonStyle(BotonPWA(tipo: .suave(T.sf2, T.tx3, T.bd), lleno: false))
                        } else {
                            Button("🔴 Marcar urgente") { urgente() }
                                .buttonStyle(BotonPWA(tipo: .suave(T.urgenteFondo, T.urgente, Color(hex: 0xE8AAAA)), lleno: false))
                        }
                    }
                    Button("🗑 Eliminar") { preguntarEliminar() }
                        .buttonStyle(BotonPWA(tipo: .suave(T.rdL, T.rd, T.rdM), lleno: false))
                }
            }
        }
        .disabled(trabajando)
    }

    // MARK: Acciones

    private func correr(_ trabajo: @escaping () async -> String?, ok: String? = nil, despues: (() -> Void)? = nil) {
        trabajando = true
        Task {
            let e = await trabajo()
            trabajando = false
            if let e { error = e } else {
                if let ok { store.aviso = ok }
                despues?()
            }
        }
    }

    private func generar() {
        let o = oc
        if store.puedeEditar {
            correr({ await store.registrarPDF(o) }) { opcionesPDF = o }
        } else {
            opcionesPDF = o
        }
    }

    private func urgente() {
        let o = oc
        correr({ await store.cambiarUrgente(o) }, ok: o.urgente ? "Urgente desactivado" : "🔴 OC marcada como urgente")
    }

    private func agregarNota() {
        let o = oc, t = notaNueva
        correr({ await store.agregarNotaInterna(o, t) }, ok: "📝 Nota agregada") { notaNueva = "" }
    }

    private func preguntarEliminar() {
        let o = oc
        pregunta = Pregunta(titulo: "¿Eliminar la OC \(o.num)? Esta acción no se puede deshacer.", boton: "Eliminar",
                            destructiva: true) {
            correr({ await store.eliminarOC(o) }, ok: "🗑 OC \(o.num) eliminada")
        }
    }

    private func preguntarQuitarTodas() {
        let o = oc
        let n = o.facturas.count
        let t = (n > 1 ? "¿Quitar las \(n) facturas" : "¿Quitar la factura \(o.facturaPrincipal?.num ?? "")")
            + " de la OC \(o.num)? La OC vuelve a las pendientes y la podés volver a cargar."
        pregunta = Pregunta(titulo: t, boton: "Quitar") {
            correr({ await store.quitarFacturas(o) }, ok: "Factura desvinculada")
        }
    }

    private func preguntarSacar(_ i: Int, _ f: FacturaOC) {
        let o = oc
        if o.facturas.count < 2 { preguntarQuitarTodas(); return }
        pregunta = Pregunta(titulo: "¿Sacar la factura \(f.num) de la OC \(o.num)? Las demás facturas quedan.", boton: "Sacar") {
            correr({ await store.quitarFactura(o, indice: i) }, ok: "Factura sacada")
        }
    }

    /// Va haciendo las preguntas una por una y, si se acepta todo, ejecuta `final`.
    private func enCadena(_ preguntas: [(String, String)], final: @escaping () -> Void) {
        guard let primera = preguntas.first else { final(); return }
        let (t, b) = primera
        pregunta = Pregunta(titulo: t, boton: b) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { enCadena(Array(preguntas.dropFirst()), final: final) }
        }
    }

    private func cargarFactura() {
        let o = oc
        let sumando = o.tieneFactura
        if let e = store.validarFactura(o, num: facNum, monto: facMonto, sumando: sumando) { error = e; return }
        let num = facNum, monto = facMonto, cuit = facCuit
        var preguntas: [(String, String)] = []
        if !sumando { preguntas += store.avisosCuit(o, cuit).map { ($0, "Guardar igual") } }
        if let r = store.avisoFacturaRepetida(o, num: num, monto: monto, cuitEscrito: sumando ? "" : cuit) {
            preguntas.append((sumando ? r.replacingOccurrences(of: "¿La cargo igual", with: "¿La sumo igual") : r,
                              sumando ? "Sumar igual" : "Cargar igual"))
        }
        enCadena(preguntas) {
            if sumando {
                correr({ await store.sumarFactura(o, num: num, monto: monto) }, ok: "✅ Factura sumada") {
                    facNum = ""; facMonto = ""
                }
            } else {
                correr({ await store.guardarFactura(o, num: num, monto: monto, cuitEscrito: cuit) },
                       ok: "✅ Factura guardada — el Excel la toma en la próxima actualización") {
                    facNum = ""; facMonto = ""; facCuit = ""
                    // Como la web: al guardar la factura se abre la OC para imprimir o compartir
                    generar()
                }
            }
        }
    }
}

/// "OC No …" con Imprimir / WhatsApp / Mail (`mostrarOpcionesOC` de la PWA en el celular).
struct OpcionesOC: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let oc: OC
    @State private var pdfParaVer: ArchivoPDF?
    @State private var pdfParaCompartir: ArchivoPDF?
    @State private var error: String?

    var body: some View {
        let datos = PDFOC.Datos(oc)
        VStack(alignment: .leading, spacing: 12) {
            Text("OC No \(datos?.num ?? 0)").font(T.syne(16))
            Text(oc.proveedor + (oc.obra.isEmpty ? "" : " - \(oc.obra)")).font(T.sans(13)).foregroundStyle(T.tx2)
            VStack(spacing: 0) {
                HStack {
                    Text("#").frame(width: 22, alignment: .leading)
                    Text("Material").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Cant.").frame(width: 50)
                }
                .font(T.sans(11, .semibold)).padding(.vertical, 5).padding(.horizontal, 8).background(Color(hex: 0xF5F5F5))
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(oc.items.enumerated()), id: \.offset) { i, it in
                            HStack(alignment: .firstTextBaseline) {
                                Text("\(i + 1)").frame(width: 22, alignment: .leading)
                                Text(it.desc).frame(maxWidth: .infinity, alignment: .leading)
                                Text(it.cant).frame(width: 50)
                            }
                            .font(T.sans(12)).padding(.vertical, 4).padding(.horizontal, 8)
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: 0xEEEEEE), lineWidth: 1))
            if !oc.notas.isEmpty {
                Text(oc.notas).font(T.sans(12)).foregroundStyle(Color(hex: 0x666666))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(Color(hex: 0xFFFDF5), in: RoundedRectangle(cornerRadius: 6))
            }
            Group {
                Button("Imprimir / Ver PDF") { pdfParaVer = armar() }
                    .buttonStyle(BotonGrande(color: T.bl))
                Button("Compartir por WhatsApp") { pdfParaCompartir = armar() }
                    .buttonStyle(BotonGrande(color: Color(hex: 0x25D366)))
                Button("Enviar por Mail") { mail() }
                    .buttonStyle(BotonGrande(color: Color(hex: 0x6B4EFF)))
                Button("Cerrar") { dismiss() }
                    .buttonStyle(BotonGrande(color: Color(hex: 0xF0F0F0), texto: Color(hex: 0x333333)))
            }
            .disabled(datos == nil)
        }
        .padding(20)
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(item: $pdfParaVer) { VisorPDF(archivo: $0) }
        .sheet(item: $pdfParaCompartir) { a in HojaCompartir(items: [a.url]).presentationDetents([.medium, .large]) }
        .alert("No se pudo armar el PDF", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    private func armar() -> ArchivoPDF? {
        do {
            return ArchivoPDF(url: try PDFOC.archivo(oc), titulo: "OC \(oc.numOCPDF ?? 0)")
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Mismo mail que arma la web en el celular.
    private func mail() {
        guard let d = PDFOC.Datos(oc) else { return }
        let asunto = "OC No \(d.num) - CEO CONSTRUCCIONES SRL"
        var cuerpo = "Estimado proveedor,\n\nOC No \(d.num)\nFecha: \(d.fecha)\nProveedor: \(d.proveedor)\n\nMateriales:\n"
            + d.items.map { "- \($0.desc) (\($0.cant))" }.joined(separator: "\n")
        if !d.notas.isEmpty { cuerpo += "\n\nObservaciones: \(d.notas)" }
        cuerpo += "\n\nSaludos,\nCEO CONSTRUCCIONES SRL"
        let permitidos = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        func cod(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: permitidos) ?? "" }
        if let url = URL(string: "mailto:?subject=\(cod(asunto))&body=\(cod(cuerpo))") { openURL(url) }
    }
}

/// Botones grandes de la hoja "OC No …".
struct BotonGrande: ButtonStyle {
    let color: Color
    var texto: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(T.sans(15, .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(color.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(texto)
    }
}
