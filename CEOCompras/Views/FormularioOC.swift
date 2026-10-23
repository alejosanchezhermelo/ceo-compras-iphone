import SwiftUI

/// Nueva OC / Editar OC. Mismos campos que el formulario de la web.
struct FormularioOC: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let editando: OC?
    var solicitud: Solicitud? = nil

    @State private var b: BorradorOC
    @State private var guardando = false
    @State private var error: String?
    @State private var preguntarRepetido = false
    @FocusState private var enProveedor: Bool

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

    /// Obras activas; si la OC que se edita tiene una obra archivada, se agrega para no perderla.
    private var opcionesObra: [String] {
        var l = store.obras
        if !b.obra.isEmpty && !l.contains(b.obra) { l.insert(b.obra, at: 0) }
        return l
    }

    private var opcionesEncargado: [String] {
        var l = store.encargados
        if !b.encargado.isEmpty && !l.contains(b.encargado) { l.insert(b.encargado, at: 0) }
        return l
    }

    private var sugerencias: [String] {
        let q = b.proveedor.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return Array(store.proveedores.filter { $0.lowercased().contains(q) && $0.lowercased() != q }.prefix(5))
    }

    var body: some View {
        NavigationStack {
            Form {
                if store.modoPrueba {
                    Section {
                        Label("MODO PRUEBA: se guarda en la base de prueba. Tus OC reales no se tocan y no se manda WhatsApp.",
                              systemImage: "testtube.2")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }

                if let s = solicitud {
                    Section("Solicitud de \(s.encargado)") {
                        Text(s.texto).font(T.sans(13)).foregroundStyle(T.pp)
                    }
                }

                Section("Orden") {
                    LabeledContent("N° de OC") {
                        TextField("858", text: $b.num)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                    }
                    Picker("Obra", selection: $b.obra) {
                        Text("Elegir…").tag("")
                        ForEach(opcionesObra, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Encargado", selection: $b.encargado) {
                        Text("Elegir…").tag("")
                        ForEach(opcionesEncargado, id: \.self) { Text($0).tag($0) }
                    }
                    Toggle("Fecha estimada de entrega", isOn: $b.tieneFecha.animation())
                    if b.tieneFecha {
                        DatePicker("Entrega", selection: $b.fecha, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "es_AR"))
                    }
                }

                Section {
                    TextField("Nombre del proveedor", text: $b.proveedor)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .focused($enProveedor)
                    if enProveedor {
                        ForEach(sugerencias, id: \.self) { s in
                            Button {
                                b.proveedor = s
                                enProveedor = false
                            } label: {
                                Label(s, systemImage: "arrow.up.left").foregroundStyle(Color.ceoAzul)
                            }
                        }
                    }
                } header: {
                    Text("Proveedor")
                } footer: {
                    if !b.proveedor.trimmingCharacters(in: .whitespaces).isEmpty
                        && !store.proveedores.contains(capitalizarProveedor(b.proveedor.trimmingCharacters(in: .whitespaces))) {
                        Text("Proveedor nuevo: se va a agregar a la lista como “\(capitalizarProveedor(b.proveedor.trimmingCharacters(in: .whitespaces)))”.")
                    }
                }

                Section {
                    ForEach($b.items) { $it in
                        VStack(spacing: 8) {
                            TextField("Descripción del material", text: $it.desc, axis: .vertical)
                            HStack {
                                TextField("Cantidad", text: $it.cant)
                                    .keyboardType(.decimalPad)
                                    .font(.body.monospacedDigit())
                                Divider()
                                TextField("Unidad (m³, kg…)", text: $it.unit)
                            }
                            .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { b.items.remove(atOffsets: $0) }
                    Button {
                        b.items.append(BorradorItem())
                    } label: {
                        Label("Agregar material", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Materiales")
                } footer: {
                    Text("Deslizá un material a la izquierda para borrarlo. Los renglones sin descripción no se guardan.")
                }

                Section("Notas") {
                    TextField("Notas para el proveedor", text: $b.notas, axis: .vertical)
                        .lineLimit(2...6)
                }

            }
            .scrollContentBackground(.hidden)
            .background(T.bg)
            .font(T.sans(15))
            .navigationTitle(editando.map { "Editar OC \($0.num)" } ?? "Nueva orden de compra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }.disabled(guardando)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if guardando {
                        ProgressView()
                    } else {
                        Button("Guardar") { intentar() }.bold()
                    }
                }
            }
            .interactiveDismissDisabled(guardando)
            // El error va en una ventana: abajo del formulario no se veía (pasó en la prueba de la v0.2).
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
            .confirmationDialog("Ya existe una OC con el número \(b.num.trimmingCharacters(in: .whitespaces)). ¿Guardás igual?",
                                isPresented: $preguntarRepetido, titleVisibility: .visible) {
                Button("Guardar igual") { guardarYa() }
                Button("Cancelar", role: .cancel) {}
            }
        }
    }

    private func intentar() {
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
