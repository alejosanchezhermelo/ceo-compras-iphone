import SwiftUI

/// Paneles "Obras registradas" y "Encargados de obra" que se abren arriba de la lista de órdenes
/// con los botones 🏗 Obras y 👷 Encargados (`cOP` / `cEP` de la PWA).
struct PanelObras: View {
    @Environment(Store.self) private var store
    @State private var agregando = false
    @State private var nueva = ""
    @State private var renombre: String?
    @State private var textoRenombre = ""
    @State private var pregunta: PreguntaPanel?
    @State private var error: String?
    @State private var trabajando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Obras registradas").font(T.syne(13, .semibold)).foregroundStyle(T.tx)
                Spacer()
                Button("+ Nueva obra") { agregando.toggle() }
                    .font(T.sans(12, .medium)).foregroundStyle(T.bl)
            }
            if store.obras.isEmpty {
                Text("Sin obras registradas").font(T.sans(13)).foregroundStyle(T.tx3)
            } else {
                Renglones(espacio: 6) {
                    ForEach(store.obras, id: \.self) { n in
                        HStack(spacing: 5) {
                            Text(capitalizarPalabras(n))
                            Text("\(store.ordenes.filter { $0.obra == n }.count)")
                                .font(T.mono(10)).padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.black.opacity(0.08), in: Capsule())
                            Button("✏️") { textoRenombre = n; renombre = n }.opacity(0.6)
                            Button("📦") { preguntarArchivar(n) }.opacity(0.6)
                        }
                        .font(T.sans(12)).foregroundStyle(T.bl)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(T.blL, in: Capsule())
                        .overlay(Capsule().stroke(T.blM, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }
            }
            if agregando {
                HStack(spacing: 6) {
                    TextField("Nombre de la obra...", text: $nueva).campoPWA().onSubmit { agregar() }
                    Button("Agregar") { agregar() }
                        .buttonStyle(BotonPWA(tipo: .color(T.bl), lleno: false))
                        .disabled(nueva.trimmingCharacters(in: .whitespaces).isEmpty || trabajando)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .tarjeta()
        .alert("Nuevo nombre para la obra \"\(renombre ?? "")\":",
               isPresented: Binding(get: { renombre != nil }, set: { if !$0 { renombre = nil } }),
               presenting: renombre) { viejo in
            TextField("Nuevo nombre", text: $textoRenombre)
            Button("Aceptar") { pedirConfirmarRenombre(viejo, textoRenombre) }
            Button("Cancelar", role: .cancel) {}
        }
        .modifier(AlertasPanel(pregunta: $pregunta, error: $error))
    }

    private func agregar() {
        let v = nueva.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        correr({ await store.agregarObra(v) }, ok: "✅ Obra agregada") { nueva = ""; agregando = false }
    }

    private func preguntarArchivar(_ n: String) {
        pregunta = PreguntaPanel(titulo: "¿Archivar la obra \"\(n)\"?", boton: "Archivar") {
            correr({ await store.archivarObra(n, archivar: true) }, ok: "📦 Obra archivada")
        }
    }

    private func pedirConfirmarRenombre(_ viejo: String, _ escrito: String) {
        let n = escrito.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != viejo else { return }
        let p = PreguntaPanel(titulo: "¿Renombrar \"\(viejo)\" a \"\(n)\"? Se actualizarán las órdenes y solicitudes vinculadas.",
                              boton: "Renombrar") {
            correr({ await store.renombrarObra(viejo, n) }, ok: "✅ Obra actualizada")
        }
        // esperar a que se cierre la ventana del nombre antes de abrir la pregunta
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pregunta = p }
    }

    private func correr(_ t: @escaping () async -> String?, ok: String, despues: (() -> Void)? = nil) {
        trabajando = true
        Task {
            let e = await t()
            trabajando = false
            if let e { error = e } else { store.aviso = ok; despues?() }
        }
    }
}

struct PanelEncargados: View {
    @Environment(Store.self) private var store
    @State private var agregando = false
    @State private var nuevo = ""
    @State private var pregunta: PreguntaPanel?
    @State private var error: String?
    @State private var trabajando = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Encargados de obra").font(T.syne(13, .semibold)).foregroundStyle(T.tx)
                Spacer()
                Button("+ Nuevo encargado") { agregando.toggle() }
                    .font(T.sans(12, .medium)).foregroundStyle(T.gn)
            }
            if store.encargados.isEmpty {
                Text("Sin encargados registrados").font(T.sans(13)).foregroundStyle(T.tx3)
            } else {
                Renglones(espacio: 6) {
                    ForEach(store.encargados, id: \.self) { e in
                        HStack(spacing: 5) {
                            Text(e)
                            Button("✕") { preguntarEliminar(e) }.opacity(0.6)
                        }
                        .font(T.sans(12)).foregroundStyle(T.gn)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(T.gnL, in: Capsule())
                        .overlay(Capsule().stroke(T.gnM, lineWidth: 1))
                        .buttonStyle(.plain)
                    }
                }
            }
            if agregando {
                HStack(spacing: 6) {
                    TextField("Nombre del encargado...", text: $nuevo).campoPWA().onSubmit { agregar() }
                    Button("Agregar") { agregar() }
                        .buttonStyle(BotonPWA(tipo: .color(T.gn), lleno: false))
                        .disabled(nuevo.trimmingCharacters(in: .whitespaces).isEmpty || trabajando)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 16)
        .background(T.sf)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.gnM, lineWidth: 1))
        .modifier(AlertasPanel(pregunta: $pregunta, error: $error))
    }

    private func agregar() {
        let v = nuevo.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        trabajando = true
        Task {
            let e = await store.agregarEncargado(v)
            trabajando = false
            if let e { error = e } else { store.aviso = "✅ Encargado agregado"; nuevo = ""; agregando = false }
        }
    }

    private func preguntarEliminar(_ e: String) {
        pregunta = PreguntaPanel(titulo: "¿Eliminar a \"\(e)\" de la lista?", boton: "Eliminar", destructiva: true) {
            trabajando = true
            Task {
                let err = await store.eliminarEncargado(e)
                trabajando = false
                if let err { error = err } else { store.aviso = "🗑 Encargado eliminado" }
            }
        }
    }
}

/// Pregunta de confirmación de los paneles (`showConfirm` de la web).
struct PreguntaPanel: Identifiable {
    let id = UUID()
    let titulo: String
    let boton: String
    var destructiva = false
    let accion: () -> Void
}

/// La pregunta de confirmación y el cartel de error de los paneles.
struct AlertasPanel: ViewModifier {
    @Binding var pregunta: PreguntaPanel?
    @Binding var error: String?

    func body(content: Content) -> some View {
        content
            .alert(pregunta?.titulo ?? "", isPresented: Binding(get: { pregunta != nil }, set: { if !$0 { pregunta = nil } }),
                   presenting: pregunta) { p in
                Button(p.boton, role: p.destructiva ? .destructive : nil) { p.accion() }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
    }
}

/// `capFirst` de la web: primera letra de cada palabra en mayúscula (el resto queda como está).
func capitalizarPalabras(_ s: String) -> String {
    s.split(separator: " ", omittingEmptySubsequences: false)
        .map { $0.isEmpty ? "" : $0.prefix(1).uppercased() + $0.dropFirst() }
        .joined(separator: " ")
}
