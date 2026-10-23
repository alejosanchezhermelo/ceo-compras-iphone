import SwiftUI

/// Tarjeta de solicitud de material (`cardSol` de la PWA, borde violeta).
struct TarjetaSolicitud: View {
    let sol: Solicitud

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Renglones(espacio: 5) {
                    Text("Solicitud").font(T.syne(14)).foregroundStyle(T.pp)
                    Etiqueta.solicitud()
                    if !sol.obra.isEmpty { Etiqueta.obra(sol.obra) }
                }
                (Text("De: ").foregroundStyle(T.tx2) + Text(sol.encargado).bold().foregroundStyle(T.tx))
                    .font(T.sans(13))
                Text(Formato.fechaHora(sol.ts)).font(T.mono(11)).foregroundStyle(T.tx3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.tx3)
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tarjeta(bordeIzq: T.pp)
    }
}

/// Solicitud abierta: material pedido, comentario de Compras, Generar OC y Archivar.
struct DetalleSolicitud: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let sol: Solicitud
    /// Se llama al tocar "Generar OC" (la lista abre el formulario cuando esta hoja se cierra).
    let generarOC: () -> Void

    @State private var comentario = ""
    @State private var preguntarArchivar = false
    @State private var trabajando = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TarjetaSolicitud(sol: sol)
                    VStack(alignment: .leading, spacing: 10) {
                        Rotulo(texto: "Material solicitado")
                        Text(sol.texto)
                            .font(T.sans(13)).foregroundStyle(T.pp).lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .background(T.ppL, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.ppM, lineWidth: 1))
                        if !sol.notas.isEmpty { CajaNotas(texto: sol.notas) }
                        if !sol.comentarioCompras.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("💬 Compras respondió").font(T.mono(10, .medium)).foregroundStyle(T.bl)
                                Text(sol.comentarioCompras).font(T.sans(13)).foregroundStyle(T.tx)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(T.blL, in: RoundedRectangle(cornerRadius: 8))
                        }
                        if store.puedeEditar {
                            HStack(spacing: 6) {
                                TextField("Agregar comentario a esta solicitud…", text: $comentario).campoPWA()
                                Button("Guardar") { guardarComentario() }
                                    .buttonStyle(BotonPWA()).fixedSize()
                                    .disabled(comentario.trimmingCharacters(in: .whitespaces).isEmpty || trabajando)
                            }
                            HStack(spacing: 8) {
                                Button {
                                    generarOC()
                                    dismiss()
                                } label: { Text("📦 Generar OC") }
                                    .buttonStyle(BotonPWA(tipo: .color(T.gn)))
                                Button { preguntarArchivar = true } label: { Text("Archivar") }
                                    .buttonStyle(BotonPWA(tipo: .blanco))
                            }
                        }
                    }
                    .padding(14)
                    .tarjeta()
                }
                .padding(14)
            }
            .background(T.bg)
            .navigationTitle("Solicitud")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear { comentario = sol.comentarioCompras }
            .alert("¿Archivar esta solicitud?", isPresented: $preguntarArchivar) {
                Button("Archivar") { archivar() }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func guardarComentario() {
        trabajando = true
        Task {
            if let e = await store.comentarioSolicitudGuardar(sol, comentario) { error = e } else { store.aviso = "✅ Comentario guardado" }
            trabajando = false
        }
    }

    private func archivar() {
        Task {
            if let e = await store.archivarSolicitud(sol) { error = e } else {
                store.aviso = "Solicitud archivada"
                dismiss()
            }
        }
    }
}

/// Recuadro beige de notas (`.nbox` de la PWA).
struct CajaNotas: View {
    let texto: String
    var body: some View {
        Text("📝 " + texto)
            .font(T.sans(13)).foregroundStyle(T.tx2).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(T.sf2, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension Store {
    func comentarioSolicitudGuardar(_ s: Solicitud, _ t: String) async -> String? { await comentarSolicitud(s, t) }
}
