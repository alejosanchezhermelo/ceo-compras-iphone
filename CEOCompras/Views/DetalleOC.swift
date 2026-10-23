import SwiftUI

/// Ficha de una OC. Se actualiza sola si la cambian desde la PC.
struct DetalleOC: View {
    @Environment(Store.self) private var store
    @Environment(\.openURL) private var openURL
    let id: String

    @State private var pdfParaVer: ArchivoPDF?
    @State private var pdfParaCompartir: ArchivoPDF?
    @State private var error: String?

    var body: some View {
        if let oc = store.ordenes.first(where: { $0.id == id }) {
            ficha(oc)
        } else {
            ContentUnavailableView("La OC ya no está", systemImage: "doc.questionmark",
                                   description: Text("Puede haber sido eliminada desde la PC."))
        }
    }

    private func ficha(_ oc: OC) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Renglones {
                        if oc.urgente { Etiqueta.urgente() }
                        Etiqueta.estado(oc)
                        if !oc.remito.isEmpty { Etiqueta(texto: "🧾 Remito", fondo: Color(hex: 0xD1FAE5), color: Color(hex: 0x065F46)) }
                    }
                    Text(oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor)
                        .font(.title3.bold())
                }
                .padding(.vertical, 4)
                Dato("Obra", oc.obra)
                Dato("Encargado", oc.responsable)
                Dato("Entrega", oc.fechaEntregaTexto)
                if !oc.remito.isEmpty {
                    Dato("Remito", "N° \(oc.remito)" + (oc.fechaEntregaReal.isEmpty ? "" : " · Entregado el \(oc.fechaEntregaReal)"))
                }
                Dato("Solicitud de", oc.solRef)
            }

            if !oc.notas.isEmpty {
                Section("Notas") { Text(oc.notas) }
            }

            Section("Materiales (\(oc.items.count))") {
                if oc.items.isEmpty {
                    Text("Sin ítems").foregroundStyle(.secondary)
                }
                ForEach(oc.items) { it in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(it.desc).frame(maxWidth: .infinity, alignment: .leading)
                        Text(it.cant).monospacedDigit().fontWeight(.medium)
                        Text(it.unit).foregroundStyle(.secondary).frame(minWidth: 34, alignment: .leading)
                    }
                }
            }

            if !oc.comentario.isEmpty {
                Section("⚠ Faltantes") { Text(oc.comentario) }
            }

            if !oc.facturas.isEmpty {
                Section("Facturas") {
                    ForEach(Array(oc.facturas.enumerated()), id: \.offset) { _, f in
                        HStack {
                            Text(f.num)
                            Spacer()
                            if let i = f.importe { Text(Formato.pesos(i)).monospacedDigit() }
                        }
                    }
                    if oc.totalFacturado > 0 {
                        HStack {
                            Text("Total facturado").bold()
                            Spacer()
                            Text(Formato.pesos(oc.totalFacturado)).bold().monospacedDigit()
                        }
                    }
                }
            }

            if !oc.notasInternas.isEmpty {
                Section("🔒 Notas internas") {
                    ForEach(Array(oc.notasInternas.enumerated()), id: \.offset) { _, n in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(n.txt)
                            if let ts = n.ts {
                                Text(Formato.fechaHora(ts)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("Historial de esta OC") {
                let eventos = store.eventosPorOC[oc.id] ?? []
                if eventos.isEmpty {
                    Text("Sin eventos registrados").foregroundStyle(.secondary)
                }
                ForEach(eventos) { ev in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ev.texto).font(.subheadline)
                        Text(Formato.fechaHora(ev.ts)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("OC \(oc.num)")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { botones(oc) }
        .sheet(item: $pdfParaVer) { VisorPDF(archivo: $0) }
        .sheet(item: $pdfParaCompartir) { a in
            HojaCompartir(items: [a.url]).presentationDetents([.medium, .large])
        }
        .alert("No se pudo armar el PDF", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func botones(_ oc: OC) -> some View {
        VStack(spacing: 6) {
            if oc.numOCPDF == nil {
                Text("Esta OC todavía no tiene número de PDF. Generala una vez desde la PC.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                boton("Ver PDF", "doc.richtext", Color.ceoAzul) { pdfParaVer = armar(oc) }
                boton("WhatsApp", "square.and.arrow.up", Color(hex: 0x25A35A)) { pdfParaCompartir = armar(oc) }
                boton("Mail", "envelope", Color(hex: 0x6B4EFF)) { mail(oc) }
            }
            .disabled(oc.numOCPDF == nil)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func boton(_ titulo: String, _ icono: String, _ color: Color, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 3) {
                Image(systemName: icono).font(.body.weight(.semibold))
                Text(titulo).font(.caption.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(color)
    }

    private func armar(_ oc: OC) -> ArchivoPDF? {
        do {
            let url = try PDFOC.archivo(oc)
            return ArchivoPDF(url: url, titulo: "OC \(oc.numOCPDF ?? 0)")
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    /// Mismo mail que arma la web en el celular (botón "Enviar por Mail").
    private func mail(_ oc: OC) {
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
