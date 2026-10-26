import SwiftUI

/// Pestaña Ajustes: lo del iPhone (Face ID, modo prueba, código) + lo de Ajustes de la web
/// (numeración, obras, encargados, proveedores guardados, contactos de WhatsApp).
struct PantallaAjustes: View {
    @Environment(Store.self) private var store
    @State private var verCodigo = false
    @State private var proximoNum = ""
    @State private var obraNueva = ""
    @State private var encNuevo = ""
    @State private var waEnc = ""
    @State private var waNumero = ""
    @State private var waKey = ""
    @State private var verArchivadas = false
    @State private var trabajando = false
    @State private var error: String?
    @State private var pregunta: Pregunta?
    @State private var renombre: Renombre?
    @State private var textoRenombre = ""
    @State private var contactoEditado: ContactoWA?
    @State private var editNumero = ""
    @State private var editKey = ""

    struct Pregunta: Identifiable {
        let id = UUID()
        let titulo: String
        let boton: String
        var destructiva = false
        let accion: () -> Void
    }

    struct Renombre: Identifiable {
        let id = UUID()
        let titulo: String
        let viejo: String
        let accion: (String) -> Void
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.modoPrueba {
                    Section { FranjaPrueba().listRowInsets(EdgeInsets()).listRowBackground(Color.clear) }
                }
                seccionesIPhone
                if store.puedeEditar {
                    seccionNumeracion
                    seccionObras
                    seccionEncargados
                    seccionProveedores
                    seccionWhatsApp
                }
                Section {
                    LabeledContent("Versión", value: version)
                }
            }
            .scrollContentBackground(.hidden)
            .background(T.bg)
            .font(T.sans(15))
            .disabled(trabajando)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos() } }
            .onAppear { proximoNum = String(store.nextOCNum) }
            .onChange(of: store.nextOCNum) { _, n in proximoNum = String(n) }
            .alert(pregunta?.titulo ?? "", isPresented: Binding(get: { pregunta != nil }, set: { if !$0 { pregunta = nil } }),
                   presenting: pregunta) { p in
                Button(p.boton, role: p.destructiva ? .destructive : nil) { p.accion() }
                Button("Cancelar", role: .cancel) {}
            }
            .alert(renombre?.titulo ?? "", isPresented: Binding(get: { renombre != nil }, set: { if !$0 { renombre = nil } }),
                   presenting: renombre) { r in
                TextField("Nuevo nombre", text: $textoRenombre)
                Button("Aceptar") { r.accion(textoRenombre) }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("Editar contacto: \(contactoEditado?.nombre ?? "")",
                   isPresented: Binding(get: { contactoEditado != nil }, set: { if !$0 { contactoEditado = nil } }),
                   presenting: contactoEditado) { c in
                TextField("Número (sin +)", text: $editNumero).keyboardType(.numberPad)
                TextField("API Key CallMeBot", text: $editKey)
                Button("Guardar") { correr({ await store.editarContacto(c, numero: editNumero, apikey: editKey) }, ok: "✅ Contacto actualizado") }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    // MARK: Del iPhone

    @ViewBuilder private var seccionesIPhone: some View {
        Section("Entrada") {
            if Biometria.disponible() {
                Toggle("Entrar con Face ID", isOn: Binding(
                    get: { store.faceIDActivado },
                    set: { activar in
                        Task { if activar { await store.activarFaceID() } else { store.desactivarFaceID() } }
                    }))
            } else {
                Text("Face ID no está disponible en este iPhone.").foregroundStyle(T.tx3)
            }
            Button("Bloquear ahora") { store.bloquear() }
        }
        Section("Conexión") {
            LabeledContent("Estado", value: store.conectado ? "En vivo" : "Sin conexión")
            LabeledContent("Órdenes", value: "\(store.ordenes.count)")
        }
        Section {
            if verCodigo {
                Text(Firebase.codigoDispositivo).font(T.mono(12)).textSelection(.enabled)
            } else {
                Button("Mostrar código") { verCodigo = true }
            }
        } header: {
            Text("Código de este iPhone")
        } footer: {
            Text("Es la llave que registra este iPhone en Firebase. No lo compartas.")
        }
    }

    // MARK: 🔢 Numeración de OC

    private var seccionNumeracion: some View {
        Section {
            HStack {
                Text("Próxima OC:").foregroundStyle(T.tx2)
                Spacer()
                Text("#\(store.nextOCNum)").font(T.syne(24)).foregroundStyle(T.bl)
            }
            HStack {
                TextField("Corregir número", text: $proximoNum).keyboardType(.numberPad)
                Button("Guardar") {
                    correr({ await store.guardarProximoNumero(proximoNum) }, ok: "✅ Numeración guardada. Próxima OC: \(proximoNum)")
                }
                .buttonStyle(.borderedProminent)
            }
        } header: {
            Text("🔢 Numeración de OC")
        } footer: {
            Text("Próximo número que se usará al generar el PDF. Corregilo si hace falta.")
        }
    }

    // MARK: 🏗 Obras

    private var seccionObras: some View {
        Section {
            ForEach(store.obrasTodas.filter { !$0.archivada }) { o in
                HStack {
                    Text(o.nombre)
                    Spacer()
                    Text("\(store.ordenes.filter { $0.obra == o.nombre }.count)").font(T.mono(12)).foregroundStyle(T.tx3)
                    Button { pedirNombre("Nuevo nombre para la obra \"\(o.nombre)\":", o.nombre) { nuevo in
                        let n = nuevo.trimmingCharacters(in: .whitespaces)
                        guard !n.isEmpty, n != o.nombre else { return }
                        confirmar("¿Renombrar \"\(o.nombre)\" a \"\(n)\"? Se actualizarán las órdenes y solicitudes vinculadas.", "Renombrar") {
                            correr({ await store.renombrarObra(o.nombre, n) }, ok: "✅ Obra actualizada")
                        }
                    } } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    Button {
                        confirmar("¿Archivar la obra \"\(o.nombre)\"?", "Archivar") {
                            correr({ await store.archivarObra(o.nombre, archivar: true) }, ok: "📦 Obra archivada")
                        }
                    } label: { Image(systemName: "archivebox") }.buttonStyle(.borderless).foregroundStyle(T.tx2)
                }
            }
            HStack {
                TextField("Nueva obra", text: $obraNueva)
                Button("Agregar") {
                    let v = obraNueva
                    correr({ await store.agregarObra(v) }, ok: "✅ Obra agregada") { obraNueva = "" }
                }
                .disabled(obraNueva.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            let archivadas = store.obrasTodas.filter { $0.archivada }
            if !archivadas.isEmpty {
                Button(verArchivadas ? "Ocultar archivadas" : "Ver archivadas (\(archivadas.count))") { verArchivadas.toggle() }
                if verArchivadas {
                    ForEach(archivadas) { o in
                        HStack {
                            Text(o.nombre).foregroundStyle(T.tx3)
                            Spacer()
                            Button("Reactivar") {
                                correr({ await store.archivarObra(o.nombre, archivar: false) }, ok: "✅ Obra reactivada")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        } header: {
            Text("🏗 Obras")
        }
    }

    // MARK: 👷 Encargados

    private var seccionEncargados: some View {
        Section("👷 Encargados") {
            ForEach(store.encargados, id: \.self) { e in
                HStack {
                    Text(e)
                    Spacer()
                    Button {
                        confirmar("¿Eliminar a \"\(e)\" de la lista?", "Eliminar", destructiva: true) {
                            correr({ await store.eliminarEncargado(e) }, ok: "🗑 Encargado eliminado")
                        }
                    } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).foregroundStyle(T.tx3)
                }
            }
            HStack {
                TextField("Nuevo encargado", text: $encNuevo)
                Button("Agregar") {
                    let v = encNuevo
                    correr({ await store.agregarEncargado(v) }, ok: "✅ Encargado agregado") { encNuevo = "" }
                }
                .disabled(encNuevo.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: 🏭 Proveedores guardados

    private var seccionProveedores: some View {
        Section {
            ForEach(store.proveedores, id: \.self) { p in
                HStack {
                    Text(p)
                    Spacer()
                    Button { pedirNombre("Nuevo nombre para \"\(p)\":", p) { nuevo in
                        let n = capitalizarProveedor(nuevo.trimmingCharacters(in: .whitespaces))
                        guard !n.isEmpty, n != p else { return }
                        confirmar("¿Renombrar \"\(p)\" a \"\(n)\"? Se actualizarán todas las órdenes vinculadas.", "Renombrar") {
                            correr({ await store.renombrarProveedor(p, n) }, ok: "✅ Proveedor actualizado")
                        }
                    } } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    Button {
                        confirmar("¿Eliminar el proveedor \"\(p)\"?", "Eliminar", destructiva: true) {
                            correr({ await store.sacarProveedorDeLista(p) }, ok: "🗑 Proveedor eliminado")
                        }
                    } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).foregroundStyle(T.tx3)
                }
            }
        } header: {
            Text("🏭 Proveedores guardados")
        } footer: {
            Text("Se guardan al crear una OC. Eliminar acá solo lo saca de las sugerencias.")
        }
    }

    // MARK: 📱 WhatsApp

    private var seccionWhatsApp: some View {
        Section {
            ForEach(store.contactosWA) { c in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(c.nombre + (c.rol == "compras" ? " · Compras" : " · Encargado"))
                        Text("+\(c.numero) · API: \(c.apikey)").font(T.mono(11)).foregroundStyle(T.tx3)
                    }
                    Spacer()
                    Button {
                        editNumero = c.numero
                        editKey = c.apikey
                        contactoEditado = c
                    } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                    Button {
                        confirmar("¿Eliminar este contacto de WhatsApp?", "Eliminar", destructiva: true) {
                            correr({ await store.eliminarContacto(c) }, ok: "🗑 Contacto eliminado")
                        }
                    } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).foregroundStyle(T.tx3)
                }
            }
            Picker("Agregar contacto para", selection: $waEnc) {
                Text("— Seleccionar —").tag("")
                ForEach(store.encargados, id: \.self) { Text($0).tag($0) }
                Text("Compras (yo)").tag("__comp__")
            }
            if !waEnc.isEmpty {
                TextField("Número (sin +), ej: 5493411234567", text: $waNumero).keyboardType(.numberPad)
                TextField("API Key CallMeBot", text: $waKey)
                Button("Guardar contacto") {
                    let e = waEnc, n = waNumero, k = waKey
                    correr({ await store.agregarContacto(encargado: e, numero: n, apikey: k) }, ok: "✅ Contacto agregado") {
                        waEnc = ""; waNumero = ""; waKey = ""
                    }
                }
            }
        } header: {
            Text("📱 Notificaciones WhatsApp")
        } footer: {
            Text("Contactos que reciben los avisos automáticos (OC nueva, editada, urgente).")
        }
    }

    // MARK: Ayudas

    private func correr(_ t: @escaping () async -> String?, ok: String? = nil, despues: (() -> Void)? = nil) {
        trabajando = true
        Task {
            let e = await t()
            trabajando = false
            if let e { error = e } else {
                if let ok { store.aviso = ok }
                despues?()
            }
        }
    }

    private func confirmar(_ titulo: String, _ boton: String, destructiva: Bool = false, _ accion: @escaping () -> Void) {
        let p = Pregunta(titulo: titulo, boton: boton, destructiva: destructiva) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { accion() }
        }
        // si venimos de otra ventana (renombrar), esperar a que se cierre
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { pregunta = p }
    }

    private func pedirNombre(_ titulo: String, _ viejo: String, _ accion: @escaping (String) -> Void) {
        textoRenombre = viejo
        renombre = Renombre(titulo: titulo, viejo: viejo, accion: accion)
    }

    private var version: String {
        let i = Bundle.main.infoDictionary
        return "\(i?["CFBundleShortVersionString"] as? String ?? "?") (\(i?["CFBundleVersion"] as? String ?? "?"))"
    }
}
