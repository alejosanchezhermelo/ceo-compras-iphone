import SwiftUI

/// Pantalla de bloqueo: Face ID automático al abrir, o contraseña de Compras.
struct PantallaLogin: View {
    @Environment(Store.self) private var store
    @State private var password = ""
    @State private var entrando = false

    var body: some View {
        VStack {
            Spacer()
            // Tarjeta de la PWA (`.lc`): cuadrado azul, "Pedidos" y subtítulo
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(T.bl)
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "list.clipboard.fill").font(.system(size: 24)).foregroundStyle(.white))
                    .padding(.bottom, 18)
                Text("Pedidos").font(T.syne(22)).foregroundStyle(T.tx)
                Text("Sistema de seguimiento de órdenes de compra")
                    .font(T.sans(13)).foregroundStyle(T.tx2).multilineTextAlignment(.center)
                    .padding(.top, 4).padding(.bottom, 24)

                if store.faceIDActivado {
                    Button {
                        Task { await store.entrarConFaceID() }
                    } label: {
                        Label("Entrar con Face ID", systemImage: "faceid").font(T.sans(14, .semibold))
                    }
                    .buttonStyle(BotonGrande(color: T.bl))
                    HStack(spacing: 8) {
                        Rectangle().fill(T.bd).frame(height: 1)
                        Text("o").font(T.sans(11)).foregroundStyle(T.tx3)
                        Rectangle().fill(T.bd).frame(height: 1)
                    }
                    .padding(.vertical, 12)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text("Contraseña de Compras").font(T.sans(12, .medium)).foregroundStyle(T.tx2)
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit(entrar)
                        .campoPWA()
                }
                .padding(.bottom, 12)

                Button(action: entrar) {
                    Group {
                        if entrando { ProgressView().tint(.white) } else { Text("Entrar") }
                    }
                }
                .buttonStyle(BotonGrande(color: store.faceIDActivado ? T.gn : T.bl))
                .disabled(password.isEmpty || entrando)

                if let m = store.mensajeLogin {
                    Text(m).font(T.sans(12)).foregroundStyle(T.rd).multilineTextAlignment(.center).padding(.top, 10)
                }
                if let m = store.mensajeConexion {
                    Text(m).font(T.sans(12)).foregroundStyle(T.tx3).multilineTextAlignment(.center).padding(.top, 6)
                }
            }
            .padding(.horizontal, 26).padding(.vertical, 32)
            .background(T.sf, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.bd, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(T.bg)
    }

    private func entrar() {
        guard !password.isEmpty, !entrando else { return }
        entrando = true
        Task {
            await store.entrarConPassword(password)
            entrando = false
            if store.fase == .adentro { password = "" }
        }
    }
}

/// Primera vez: este iPhone todavía no está registrado en App Check.
struct PantallaCodigo: View {
    @Environment(Store.self) private var store
    @State private var copiado = false
    private let codigo = Firebase.codigoDispositivo

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Falta un paso (una sola vez)", systemImage: "lock.shield")
                    .font(.title2.bold())
                Text("La base de datos de CEO solo acepta aparatos registrados, y este iPhone todavía no lo está.")

                Text("Código de este iPhone").font(.headline)
                Text(codigo)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                HStack {
                    Button {
                        UIPasteboard.general.string = codigo
                        copiado = true
                    } label: {
                        Label(copiado ? "Copiado" : "Copiar", systemImage: copiado ? "checkmark" : "doc.on.doc")
                    }
                    ShareLink(item: codigo) { Label("Enviar", systemImage: "square.and.arrow.up") }
                }
                .buttonStyle(.bordered)

                Text("Mandá este código a la PC (por ejemplo, por WhatsApp Web) y pegalo en el chat con Claude: él lo registra en Firebase. Es una llave: no lo compartas con nadie más.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button {
                    store.reintentarCodigo()
                } label: {
                    Text("Ya está registrado, reintentar").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
        .background(Color(.systemBackground))
    }
}

struct PantallaAjustes: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var verCodigo = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Entrada") {
                    if Biometria.disponible() {
                        Toggle("Entrar con Face ID", isOn: Binding(
                            get: { store.faceIDActivado },
                            set: { activar in
                                Task {
                                    if activar { await store.activarFaceID() } else { store.desactivarFaceID() }
                                }
                            }))
                    } else {
                        Text("Face ID no está disponible en este iPhone.").foregroundStyle(.secondary)
                    }
                    Button("Bloquear ahora") { store.bloquear() }
                }

                Section {
                    Toggle("Modo prueba", isOn: Binding(
                        get: { store.modoPrueba },
                        set: { store.cambiarModoPrueba($0) }))
                        .tint(.red)
                } header: {
                    Text("Crear y editar OC")
                } footer: {
                    Text(store.modoPrueba
                         ? "Activado: ves y guardás en una COPIA aparte de la base (franja roja). Tus OC reales no se tocan y no se mandan WhatsApps."
                         : "Apagado: ves tus OC reales, solo para consultar. Para probar crear y editar OC, activalo.")
                }

                Section("Conexión") {
                    LabeledContent("Estado", value: store.conectado ? "En vivo" : "Sin conexión")
                    LabeledContent("Órdenes", value: "\(store.ordenes.count)")
                }

                Section {
                    if verCodigo {
                        Text(Firebase.codigoDispositivo)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    } else {
                        Button("Mostrar código") { verCodigo = true }
                    }
                } header: {
                    Text("Código de este iPhone")
                } footer: {
                    Text("Es la llave que registra este iPhone en Firebase. No lo compartas.")
                }

                Section {
                    LabeledContent("Versión", value: version)
                } footer: {
                    Text(Config.escrituraReal
                         ? "Crear y editar OC habilitado en los datos reales."
                         : "Con los datos reales la app es solo de consulta. Crear y editar OC se prueba en el modo prueba.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(T.bg)
            .font(T.sans(15))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos() } }
        }
    }

    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }
}
