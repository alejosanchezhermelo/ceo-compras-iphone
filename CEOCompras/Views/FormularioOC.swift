import SwiftUI

/// Nueva OC / Editar OC. Mismos campos, textos y orden que la ventana "Nueva orden de compra" de la web
/// (`#sModal` en index.html), con el mismo estilo.
struct FormularioOC: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editando: OC?
    var solicitud: Solicitud? = nil

    @State private var b: BorradorOC
    @State private var guardando = false
    @State private var error: String?
    @State private var preguntarRepetido = false
    @State private var nuevaObraAbierta = false
    @State private var nombreObraNueva = ""
    @State private var agregandoObra = false
    @FocusState private var foco: Campo?

    enum Campo { case num, obra, obraNueva, proveedor }

    init(editando: OC?, numeroSugerido: Int, solicitud: Solicitud? = nil) {
        self.editando = editando
        self.solicitud = solicitud
        var b = editando.map { BorradorOC(editando: $0) } ?? BorradorOC(numeroSugerido: numeroSugerido)
        if let s = solicitud, editando == nil {
            // modalDesdeSol de la web: obra, encargado y notas de la solicitud
            b.obra = s.obra
            b.encargado = s.encargado
            b.notas = s.notas
        }
        _b = State(initialValue: b)
    }

    // MARK: Listas

    /// `onObraInput` de la web: obras activas que contienen lo escrito (todas si está vacío), hasta 8.
    private var obrasSugeridas: [String] {
        let q = b.obra.trimmingCharacters(in: .whitespaces).lowercased()
        let l = q.isEmpty ? store.obras : store.obras.filter { $0.lowercased().contains(q) }
        return Array(l.prefix(8))
    }

    /// `onProvInput` de la web: proveedores que contienen lo escrito, hasta 8.
    private var proveedoresSugeridos: [String] {
        let q = b.proveedor.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return Array(store.proveedores.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(8))
    }

    private var opcionesEncargado: [String] {
        var l = store.encargados
        if !b.encargado.isEmpty && !l.contains(b.encargado) { l.insert(b.encargado, at: 0) }
        return l
    }

    /// Rubros de la web; si la OC que se edita tiene un rubro que ya no está, se agrega para no perderlo.
    private var opcionesRubro: [String] {
        var l = store.rubros.map(\.nombre)
        if !b.rubro.isEmpty && !l.contains(b.rubro) { l.insert(b.rubro, at: 0) }
        return l
    }

    // MARK: Pantalla

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if store.modoPrueba {
                        Label("MODO PRUEBA: se guarda en la base de prueba. Tus OC reales no se tocan y no se manda WhatsApp.",
                              systemImage: "testtube.2")
                            .font(T.sans(12, .bold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
                            .padding(.bottom, 14)
                    }

                    Text(editando.map { "Editar OC \($0.num)" } ?? "Nueva orden de compra")
                        .font(T.syne(18)).foregroundStyle(T.tx)
                        .padding(.bottom, 4)
                    Text("Completá los datos para registrar la OC")
                        .font(T.sans(13)).foregroundStyle(T.tx2)
                        .padding(.bottom, 20)

                    if let s = solicitud {
                        Text("📋 SOLICITUD DE REFERENCIA").font(T.mono(10, .medium)).kerning(0.7).foregroundStyle(T.pp)
                            .padding(.bottom, 5)
                        Text(s.texto)
                            .font(T.sans(13)).foregroundStyle(T.pp).lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .background(T.ppL, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.ppM, lineWidth: 1))
                            .padding(.bottom, 14)
                    }

                    campo("Número de OC *") {
                        TextField("OC-0001", text: $b.num)
                            .keyboardType(.numberPad)
                            .focused($foco, equals: .num)
                            .campoPWA()
                    }
                    campo("Fecha estimada entrega") { fecha }
                    campo("Obra *") { obra }
                    campo("Proveedor") { proveedor }
                    campo("Rubro") {
                        Menu {
                            Picker("Rubro", selection: $b.rubro) {
                                Text("— Sin rubro —").tag("")
                                ForEach(opcionesRubro, id: \.self) { Text($0).tag($0) }
                            }
                        } label: { selector(b.rubro.isEmpty ? "— Sin rubro —" : b.rubro) }
                    }
                    campo("Responsable de obra *") {
                        Menu {
                            Picker("Encargado", selection: $b.encargado) {
                                Text("— Seleccionar encargado —").tag("")
                                ForEach(opcionesEncargado, id: \.self) { Text($0).tag($0) }
                            }
                        } label: { selector(b.encargado.isEmpty ? "— Seleccionar encargado —" : b.encargado) }
                    }
                    materiales
                    campo("Notas adicionales") {
                        TextField("Aclaraciones, condiciones...", text: $b.notas, axis: .vertical)
                            .lineLimit(3...8)
                            .campoPWA()
                    }
                    pie
                }
                .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 30)
            }
            .background(T.sf)
            .scrollDismissesKeyboard(.interactively)
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Listo") { foco = nil; ocultarTeclado() }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(guardando)
        // El error va en una ventana: abajo del formulario no se veía (pasó en la prueba de la v0.2).
        .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .alert("Ya existe una OC con el número \(b.num.trimmingCharacters(in: .whitespaces)). ¿Guardás igual?",
               isPresented: $preguntarRepetido) {
            Button("Guardar igual") { guardarYa() }
            Button("Cancelar", role: .cancel) {}
        }
    }

    // MARK: Partes

    /// `.field` de la web: rótulo chico arriba y el campo abajo.
    private func campo<C: View>(_ titulo: String, @ViewBuilder _ contenido: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titulo).font(T.sans(12, .medium)).foregroundStyle(T.tx2)
            contenido()
        }
        .padding(.bottom, 10)
    }

    /// Un `<select>` de la web.
    private func selector(_ texto: String) -> some View {
        HStack {
            Text(texto).foregroundStyle(T.tx).lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(T.tx3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .campoPWA()
        .contentShape(Rectangle())
    }

    /// `<input type="date">`: vacío hasta que se elige una fecha; la ✕ la borra.
    private var fecha: some View {
        HStack {
            if b.tieneFecha {
                DatePicker("Entrega", selection: $b.fecha, displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "es_AR"))
                Spacer()
                Button { b.tieneFecha = false } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(T.tx3)
                }
                .buttonStyle(.plain)
            } else {
                Button { b.tieneFecha = true } label: {
                    HStack {
                        Text("dd/mm/aaaa").foregroundStyle(T.tx3)
                        Spacer()
                        Image(systemName: "calendar").foregroundStyle(T.tx3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 22)
        .campoPWA()
    }

    /// Obra: buscador con sugerencias + "+ Nueva" para crear una obra ahí mismo (`addObraModal`).
    private var obra: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Buscar obra...", text: $b.obra)
                    .autocorrectionDisabled()
                    .focused($foco, equals: .obra)
                    .submitLabel(.done)
                    .campoPWA()
                Button {
                    nuevaObraAbierta.toggle()
                    if nuevaObraAbierta { foco = .obraNueva }
                } label: {
                    Text("+ Nueva").font(T.sans(12)).foregroundStyle(T.tx3)
                        .padding(.horizontal, 10).padding(.vertical, 11)
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(T.bd2, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if foco == .obra && !obrasSugeridas.isEmpty {
                sugerencias(obrasSugeridas) { b.obra = $0; foco = nil }
            }
            if nuevaObraAbierta {
                HStack(spacing: 6) {
                    TextField("Nombre de la nueva obra...", text: $nombreObraNueva)
                        .focused($foco, equals: .obraNueva)
                        .submitLabel(.done)
                        .onSubmit { agregarObra() }
                        .campoPWA()
                    Button("Agregar") { agregarObra() }
                        .buttonStyle(BotonPWA(lleno: false))
                        .disabled(nombreObraNueva.trimmingCharacters(in: .whitespaces).isEmpty || agregandoObra)
                }
            }
        }
    }

    private var proveedor: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Nombre del proveedor", text: $b.proveedor)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($foco, equals: .proveedor)
                .submitLabel(.done)
                .campoPWA()
            if foco == .proveedor && !proveedoresSugeridos.isEmpty {
                sugerencias(proveedoresSugeridos) { b.proveedor = $0; foco = nil }
            }
        }
    }

    /// La lista que se despliega abajo del campo (`.prov-suggest` de la web).
    private func sugerencias(_ l: [String], elegir: @escaping (String) -> Void) -> some View {
        VStack(spacing: 0) {
            ForEach(l, id: \.self) { s in
                Button { elegir(s) } label: {
                    Text(s).font(T.sans(13)).foregroundStyle(T.tx)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if s != l.last { Rectangle().fill(T.bd).frame(height: 1) }
            }
        }
        .background(T.sf, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bd, lineWidth: 1))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    /// `.isec` de la web: Descripción / Cant. / Unidad / ✕ y "+ Agregar ítem".
    private var materiales: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Materiales").font(T.sans(12, .medium)).foregroundStyle(T.tx2)
            HStack(spacing: 6) {
                Text("Descripción").frame(maxWidth: .infinity, alignment: .leading)
                Text("Cant.").frame(width: 58, alignment: .leading)
                Text("Unidad").frame(width: 66, alignment: .leading)
                Color.clear.frame(width: 30, height: 1)
            }
            .font(T.sans(11)).foregroundStyle(T.tx3)
            ForEach($b.items) { $it in
                HStack(alignment: .top, spacing: 6) {
                    TextField("Descripción del material", text: $it.desc, axis: .vertical)
                        .lineLimit(1...3)
                        .campoItem()
                    TextField("0", text: $it.cant)
                        .keyboardType(.decimalPad)
                        .campoItem()
                        .frame(width: 58)
                    TextField("m³, kg...", text: $it.unit)
                        .autocorrectionDisabled()
                        .campoItem()
                        .frame(width: 66)
                    Button { quitarItem(it.id) } label: {
                        Text("✕").font(.system(size: 12)).foregroundStyle(T.tx3)
                            .frame(width: 30, height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.bd, lineWidth: 1))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Button { b.items.append(BorradorItem()) } label: {
                Text("+ Agregar ítem").font(T.sans(13)).foregroundStyle(T.tx3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(T.bd2, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 12)
        }
        .padding(.vertical, 12)
    }

    /// `.mfoot` de la web: Cancelar y Guardar orden, a la derecha.
    private var pie: some View {
        VStack(spacing: 0) {
            Rectangle().fill(T.bd).frame(height: 1).padding(.bottom, 12)
            HStack(spacing: 8) {
                Spacer()
                Button("Cancelar") { dismiss() }
                    .buttonStyle(BotonPWA(tipo: .suave(.clear, T.tx2, T.bd), lleno: false))
                    .disabled(guardando)
                Button { intentar() } label: {
                    if guardando { ProgressView().tint(.white) } else { Text("Guardar orden") }
                }
                .buttonStyle(BotonPWA(lleno: false))
                .disabled(guardando)
            }
        }
    }

    // MARK: Acciones

    private func quitarItem(_ id: UUID) {
        b.items.removeAll { $0.id == id }
    }

    private func ocultarTeclado() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    /// `addObraModal` de la web: suma la obra a la lista y la deja elegida.
    private func agregarObra() {
        let v = nombreObraNueva.trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        agregandoObra = true
        Task {
            let e = await store.agregarObra(v)
            agregandoObra = false
            if let e {
                error = e
            } else {
                b.obra = v
                nombreObraNueva = ""
                nuevaObraAbierta = false
                foco = nil
            }
        }
    }

    private func intentar() {
        foco = nil
        error = nil
        if let e = store.validar(b, editando: editando) {
            error = e
            return
        }
        if store.numeroRepetido(b.num, editandoId: editando?.id) {
            preguntarRepetido = true
        } else {
            guardarYa()
        }
    }

    private func guardarYa() {
        guardando = true
        Task {
            let r = await store.guardar(b, editando: editando, desdeSolicitud: solicitud)
            guardando = false
            if r.ok {
                store.aviso = r.mensaje
                dismiss()
            } else {
                error = r.mensaje
            }
        }
    }
}

/// Renglón de material (`.iline input` de la web): más chico que los otros campos.
private struct CampoItem: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(T.sans(14))
            .padding(.horizontal, 8).padding(.vertical, 8)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.bd, lineWidth: 1))
    }
}

private extension View {
    func campoItem() -> some View { modifier(CampoItem()) }
}
