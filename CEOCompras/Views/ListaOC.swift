import SwiftUI

struct ListaOC: View {
    @Environment(Store.self) private var store
    @State private var busqueda = ""
    @State private var pestana: Pestana = .todos
    @State private var obra = ""
    @State private var encargado = ""
    @State private var orden: Orden = .reciente
    @State private var verAjustes = false
    @State private var nuevaOC = false

    private var hayFiltro: Bool { !obra.isEmpty || !encargado.isEmpty }

    var body: some View {
        let visibles = Filtro.aplicar(store.ordenes, pestana: pestana, obra: obra, encargado: encargado,
                                      busqueda: busqueda, orden: orden)
        NavigationStack {
            List {
                if store.modoPrueba {
                    Label("MODO PRUEBA · base de prueba, no son tus OC reales", systemImage: "testtube.2")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .listRowBackground(Color.red)
                }
                if let m = store.mensajeConexion {
                    Label(m, systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if hayFiltro {
                    Button {
                        obra = ""
                        encargado = ""
                    } label: {
                        Label([obra, encargado].filter { !$0.isEmpty }.joined(separator: " · ") + "  ✕",
                              systemImage: "line.3.horizontal.decrease.circle.fill")
                            .font(.footnote.weight(.medium))
                    }
                }
                Section {
                    ForEach(visibles) { oc in
                        NavigationLink(value: oc.id) { FilaOC(oc: oc) }
                    }
                    if visibles.isEmpty {
                        Text(store.ordenes.isEmpty ? "Cargando órdenes…" : "No hay órdenes en esta categoría")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    }
                } header: {
                    selectorPestanas
                }
            }
            .listStyle(.plain)
            .navigationTitle(store.modoPrueba ? "Órdenes (prueba)" : "Órdenes")
            .navigationDestination(for: String.self) { id in DetalleOC(id: id) }
            .searchable(text: $busqueda, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "N°, proveedor, obra, encargado, factura")
            .refreshable { await store.reconectar() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { verAjustes = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) { menuFiltros }
                if store.puedeEditar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { nuevaOC = true } label: { Image(systemName: "plus.circle.fill") }
                    }
                }
            }
            .sheet(isPresented: $verAjustes) { PantallaAjustes() }
            .sheet(isPresented: $nuevaOC) { FormularioOC(editando: nil, numeroSugerido: store.nextOCNum) }
        }
    }

    private var selectorPestanas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Pestana.allCases) { p in
                    let elegida = pestana == p
                    Button {
                        pestana = p
                    } label: {
                        Text("\(p.titulo) \(Filtro.cuenta(store.ordenes, p))")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(elegida ? Color.ceoAzul : Color(.secondarySystemFill), in: Capsule())
                            .foregroundStyle(elegida ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .listRowInsets(EdgeInsets())
        .textCase(nil)
        .background(Color(.systemBackground))
    }

    private var menuFiltros: some View {
        Menu {
            Picker("Obra", selection: $obra) {
                Text("Todas las obras").tag("")
                ForEach(store.obras, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Encargado", selection: $encargado) {
                Text("Todos los encargados").tag("")
                ForEach(store.encargados, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
            Picker("Ordenar por", selection: $orden) {
                ForEach(Orden.allCases) { Text($0.titulo).tag($0) }
            }
            .pickerStyle(.menu)
        } label: {
            Image(systemName: hayFiltro ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
    }
}

struct FilaOC: View {
    let oc: OC

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Renglones {
                Text(oc.num.isEmpty ? "—" : oc.num)
                    .font(.headline.monospacedDigit())
                if oc.urgente { Etiqueta.urgente() }
                Etiqueta.estado(oc)
                if !oc.obra.isEmpty { Etiqueta.obra(oc.obra) }
                if let f = oc.facturaPrincipal { Etiqueta.factura(f) }
            }
            Text((oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor)
                 + (oc.responsable.isEmpty ? "" : " · " + oc.responsable))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Entrega: \(oc.fechaEntregaTexto)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 3)
    }
}
