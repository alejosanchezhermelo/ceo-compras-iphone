import SwiftUI

/// Pantalla de bloqueo: Face ID automático al abrir, o contraseña de Compras.
struct PantallaLogin: View {
    @Environment(Store.self) private var store
    @State private var password = ""
    @State private var entrando = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 28))
            Text("Compras").font(.title.bold())

            if store.faceIDActivado {
                Button {
                    Task { await store.entrarConFaceID() }
                } label: {
                    Label("Entrar con Face ID", systemImage: "faceid").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }

            SecureField("Contraseña de Compras", text: $password)
                .textContentType(.password)
                .submitLabel(.go)
                .onSubmit(entrar)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

            Button(action: entrar) {
                Group {
                    if entrando { ProgressView() } else { Text("Entrar") }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(password.isEmpty || entrando)

            if let m = store.mensajeLogin {
                Text(m).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            if let m = store.mensajeConexion {
                Text(m).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Spacer()
            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
                    Button("Bloquear ahora") {
                        dismiss()
                        store.bloquear()
                    }
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
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } }
            }
        }
    }

    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }
}
