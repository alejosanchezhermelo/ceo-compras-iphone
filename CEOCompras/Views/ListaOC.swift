import SwiftUI

/// Pestaña Órdenes, igual que la PWA en el celular: las OC se abren ahí mismo en la lista (▼),
/// botón flotante "➕ Nueva OC" y los botones Proveedores / Obras / Encargados abajo de los filtros.
struct ListaOC: View {
    @Environment(Store.self) private var store
    /// Lo que hace el botón 🏆 Proveedores (pasa a la pestaña Proveedores).
    var abrirProveedores: () -> Void = {}

    @State private var busqueda = ""
    @State private var pestana: Pestana = .todos
    @State private var obra = ""
    @State private var encargado = ""
    @State private var orden: Orden = .reciente
    @State private var nuevaOC = false
    @State private var verSolicitud: Solicitud?
    @State private var solicitudParaOC: Solicitud?
    @State private var pendienteOC: Solicitud?
    @State private var asignar: OC?
    /// OC abiertas en la lista (`expanded` de la web).
    @State private var abiertas: Set<String> = []
    @State private var verObras = false
    @State private var verEncargados = false

    var body: some View {
        let visibles = Filtro.aplicar(store.ordenes, pestana: pestana, obra: obra, encargado: encargado,
                                      busqueda: busqueda, orden: orden)
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if store.modoPrueba { FranjaPrueba() }
                    if let m = store.mensajeConexion {
                        Label(m, systemImage: "wifi.slash").font(T.sans(12)).foregroundStyle(T.tx2)
                    }
                    estadisticas
                    if verObras { PanelObras() }
                    if verEncargados { PanelEncargados() }
                    buscador
                    selectorPestanas
                    filtros
                    botones

                    let importadas = store.importadasSinAsignar
                    if !importadas.isEmpty {
                        Divisor(texto: "📥 OC importadas — pendientes de asignar", n: importadas.count,
                                color: T.am, claro: T.amL, medio: T.amM)
                        ForEach(importadas) { o in
                            Button { asignar = o } label: { TarjetaImportada(oc: o) }.buttonStyle(.plain)
                        }
                    }
                    if !store.solicitudes.isEmpty {
                        Divisor(texto: "📋 Solicitudes de material", n: store.solicitudes.count,
                                color: T.pp, claro: T.ppL, medio: T.ppM)
                        ForEach(store.solicitudes) { s in
                            Button { verSolicitud = s } label: { TarjetaSolicitud(sol: s) }.buttonStyle(.plain)
                        }
                    }
                    if !importadas.isEmpty || !store.solicitudes.isEmpty {
                        Divisor(texto: "📦 Órdenes de compra", n: store.ordenes.count - importadas.count)
                    }

                    ForEach(visibles) { oc in
                        TarjetaOC(oc: oc, rubro: store.rubros.first { $0.nombre == oc.rubro },
                                  abierta: abiertas.contains(oc.id)) {
                            if abiertas.contains(oc.id) { abiertas.remove(oc.id) } else { abiertas.insert(oc.id) }
                        }
                    }
                    if visibles.isEmpty {
                        Text(store.ordenes.isEmpty ? "Cargando órdenes…" : "No hay órdenes en esta categoría")
                            .font(T.sans(13)).foregroundStyle(T.tx3)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                // lugar para que el botón flotante no tape la última OC
                .padding(.bottom, 84)
            }
            .background(T.bg)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.reconectar() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos() }
            }
            .overlay { botonFlotante }
            .sheet(isPresented: $nuevaOC) { FormularioOC(editando: nil, numeroSugerido: store.nextOCNum) }
            .sheet(item: $verSolicitud, onDismiss: {
                if let s = pendienteOC { pendienteOC = nil; solicitudParaOC = s }
            }) { s in
                DetalleSolicitud(sol: s) { pendienteOC = s }
            }
            .sheet(item: $asignar) { o in AsignarImportada(oc: o) }
            .sheet(item: $solicitudParaOC) { s in
                FormularioOC(editando: nil, numeroSugerido: store.nextOCNum, solicitud: s)
            }
        }
    }

    // MARK: Partes

    /// `#fabNuevaOC` de la PWA: abajo a la derecha, arriba de la barra. Con el teclado abierto se esconde.
    private var botonFlotante: some View {
        GeometryReader { g in
            if store.puedeEditar && g.safeAreaInsets.bottom <= 120 {
                // Con Spacer (y no con un frame grande) para que el resto de la pantalla se siga pudiendo tocar
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button { nuevaOC = true } label: {
                            Text("➕ Nueva OC")
                                .font(T.sans(14, .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 22).padding(.vertical, 14)
                                .background(T.bl, in: Capsule())
                                .shadow(color: T.bl.opacity(0.4), radius: 8, y: 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.trailing, 20).padding(.bottom, 14)
            }
        }
    }

    /// Los 3 recuadros de arriba (Total OC / Entregadas / Pendientes).
    private var estadisticas: some View {
        let ocs = store.ordenes
        let entr = ocs.filter { $0.estado == "entregado" }.count
        let pend = ocs.filter { $0.estado == "pendiente" || $0.estado == "parcial" }.count
        return HStack(spacing: 8) {
            recuadro("\(ocs.count)", "Total OC", T.tx)
            recuadro("\(entr)", "Entregadas", T.gn)
            recuadro("\(pend)", "Pendientes", T.am)
        }
    }

    private func recuadro(_ n: String, _ titulo: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(n).font(T.syne(22)).foregroundStyle(color)
            Text(titulo.uppercased()).font(T.mono(9, .medium)).kerning(0.6).foregroundStyle(T.tx3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(T.sf, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bd, lineWidth: 1))
    }

    private var buscador: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(T.tx3)
            TextField(pestana == .facturadas ? "Buscar por N° de factura, OC, proveedor…"
                                             : "Buscar por OC, proveedor, encargado, obra…", text: $busqueda)
                .font(T.sans(14))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !busqueda.isEmpty {
                Button { busqueda = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(T.tx3) }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(T.sf, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bd, lineWidth: 1))
    }

    /// Pestañas con contador (`.tabs` / `.tab.on` de la PWA).
    private var selectorPestanas: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Pestana.allCases) { p in
                    let elegida = pestana == p
                    Button { pestana = p } label: {
                        HStack(spacing: 5) {
                            Text(p.titulo).font(T.sans(12, .medium))
                            Text("\(Filtro.cuenta(store.ordenes, p))")
                                .font(T.mono(10))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(elegida ? T.bd : T.sf2.opacity(0.0), in: Capsule())
                        }
                        .foregroundStyle(elegida ? T.tx : T.tx2)
                        .padding(.horizontal, 11).padding(.vertical, 6)
                        .background(elegida ? T.sf : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                        .shadow(color: elegida ? .black.opacity(0.1) : .clear, radius: 2, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(T.sf2, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var filtros: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Ordenar por", selection: $orden) {
                        ForEach(Orden.allCases) { Text($0.titulo).tag($0) }
                    }
                } label: { chipFiltro(orden.titulo, activo: false) }
                Menu {
                    Picker("Obra", selection: $obra) {
                        Text("Todas las obras").tag("")
                        ForEach(store.obras, id: \.self) { Text($0).tag($0) }
                    }
                } label: { chipFiltro(obra.isEmpty ? "Todas las obras" : obra, activo: !obra.isEmpty) }
            }
            Menu {
                Picker("Encargado", selection: $encargado) {
                    Text("Todos los encargados").tag("")
                    ForEach(store.encargados, id: \.self) { Text($0).tag($0) }
                }
            } label: { chipFiltro(encargado.isEmpty ? "Todos los encargados" : encargado, activo: !encargado.isEmpty) }
        }
    }

    /// Botones de la barra de herramientas de la web (`.toolbar`): 🏆 Proveedores, 🏗 Obras, 👷 Encargados
    /// y + Nueva OC. (El 📊 Excel de la web no se trae: Alejo no lo usa.)
    private var botones: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Button("🏆 Proveedores") { abrirProveedores() }
                    .buttonStyle(BotonPWA(tipo: .blanco))
                Button("🏗 Obras") { withAnimation(.easeOut(duration: 0.15)) { verObras.toggle() } }
                    .buttonStyle(BotonPWA(tipo: verObras ? .suave(T.blL, T.bl, T.blM) : .blanco))
                Button("👷 Encargados") { withAnimation(.easeOut(duration: 0.15)) { verEncargados.toggle() } }
                    .buttonStyle(BotonPWA(tipo: verEncargados ? .suave(T.gnL, T.gn, T.gnM) : .blanco))
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            if store.puedeEditar {
                Button("+ Nueva OC") { nuevaOC = true }
                    .buttonStyle(BotonPWA())
            }
        }
    }

    private func chipFiltro(_ texto: String, activo: Bool) -> some View {
        HStack(spacing: 4) {
            Text(texto).font(T.sans(13, .medium)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(activo ? T.bl : T.tx2)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(activo ? T.blL : T.sf, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(activo ? T.blM : T.bd, lineWidth: 1))
    }
}

/// "Pedidos · COMPRAS" con el cuadradito azul, como arriba a la izquierda en la PWA.
struct EncabezadoPedidos: View {
    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 7)
                .fill(T.bl)
                .frame(width: 28, height: 28)
                .overlay(Image(systemName: "list.clipboard.fill").font(.system(size: 13)).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 0) {
                Text("Pedidos").font(T.syne(16)).foregroundStyle(T.tx)
                Text("COMPRAS").font(T.mono(9)).kerning(0.8).foregroundStyle(T.tx3)
            }
        }
    }
}

struct FranjaPrueba: View {
    var body: some View {
        Label("MODO PRUEBA · base de prueba, no son tus OC reales", systemImage: "testtube.2")
            .font(T.sans(12, .bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.red, in: RoundedRectangle(cornerRadius: 8))
    }
}


/// Tarjeta de OC de la lista (`cardOC` de la PWA). Al tocarla se abre ahí mismo (▼) y muestra todo.
struct TarjetaOC: View {
    let oc: OC
    let rubro: Rubro?
    let abierta: Bool
    let alTocar: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: alTocar) { encabezado }.buttonStyle(.plain)
            if abierta {
                Rectangle().fill(T.bd).frame(height: 1)
                CuerpoOC(oc: oc)
            }
        }
        .tarjeta(fondo: oc.urgente ? T.urgenteFondo : T.sf, bordeIzq: oc.urgente ? T.urgente : nil)
    }

    private var encabezado: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Renglones(espacio: 6) {
                    Text(oc.num.isEmpty ? "—" : oc.num).font(T.syne(14)).foregroundStyle(T.bl)
                    if oc.urgente { Etiqueta.urgente() }
                    Etiqueta.estado(oc)
                    if !oc.obra.isEmpty { Etiqueta.obra(oc.obra) }
                    if let rubro { Etiqueta.rubro(rubro) }
                    if !oc.remito.isEmpty { Etiqueta(texto: "🧾", fondo: T.gnL, color: T.gn, borde: T.gnM) }
                    if let f = oc.facturaPrincipal { Etiqueta.factura(f) }
                }
                Text((oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor)
                     + (oc.responsable.isEmpty ? "" : " · " + oc.responsable))
                    .font(T.sans(13)).foregroundStyle(T.tx2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Entrega: \(oc.fecha.isEmpty ? "sin fecha" : oc.fecha)")
                    .font(T.mono(11)).foregroundStyle(T.tx3)
            }
            Text("▼")
                .font(.system(size: 10))
                .foregroundStyle(T.tx3)
                .rotationEffect(.degrees(abierta ? 180 : 0))
                .animation(.easeOut(duration: 0.2), value: abierta)
                .padding(.top, 3)
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// OC importada de PDF sin obra o encargado (`cardOCPdf`, borde ámbar).
struct TarjetaImportada: View {
    let oc: OC
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Renglones(espacio: 5) {
                Text(oc.num.isEmpty ? "—" : oc.num).font(T.syne(14)).foregroundStyle(T.bl)
                Etiqueta(texto: "📥 Importada de PDF", fondo: T.sf, color: T.am, borde: T.amM)
                Etiqueta(texto: "Sin asignar", fondo: T.amL, color: T.am, borde: T.amM)
            }
            Text(oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor).font(T.sans(13)).foregroundStyle(T.tx2)
            Text("Archivo: \(oc.archivoOrigen)" + (oc.fecha.isEmpty ? "" : " · Fecha: \(oc.fecha)"))
                .font(T.mono(11)).foregroundStyle(T.tx3)
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tarjeta(fondo: T.amL, bordeIzq: T.am)
    }
}

/// Asignar obra y encargado a una OC importada (`asignarOC`) o eliminarla.
struct AsignarImportada: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let oc: OC
    @State private var obra = ""
    @State private var enc = ""
    @State private var prov = ""
    @State private var error: String?
    @State private var preguntarBorrar = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Materiales") {
                    if oc.items.isEmpty { Text("Sin ítems").foregroundStyle(T.tx3) }
                    ForEach(oc.items) { it in
                        HStack { Text(it.desc); Spacer(); Text(it.cant); Text(it.unit).foregroundStyle(T.tx3) }
                    }
                }
                if !oc.notas.isEmpty { Section("Notas") { Text(oc.notas) } }
                Section("⚙ Asignar obra y encargado") {
                    Picker("Obra *", selection: $obra) {
                        Text("— Seleccionar —").tag("")
                        ForEach(store.obras, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Encargado *", selection: $enc) {
                        Text("— Seleccionar —").tag("")
                        ForEach(store.encargados, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Proveedor", text: $prov)
                    Button("✓ Guardar asignación y activar OC") { guardar() }
                }
                Section { Button("🗑 Eliminar", role: .destructive) { preguntarBorrar = true } }
            }
            .scrollContentBackground(.hidden).background(T.bg).font(T.sans(15))
            .navigationTitle("OC \(oc.num)").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear { prov = oc.proveedor }
            .alert("¿Eliminar la OC \(oc.num)? Esta acción no se puede deshacer.", isPresented: $preguntarBorrar) {
                Button("Eliminar", role: .destructive) {
                    Task { if let e = await store.eliminarOC(oc) { error = e } else { store.aviso = "🗑 OC eliminada"; dismiss() } }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    private func guardar() {
        Task {
            if let e = await store.asignarImportada(oc, obra: obra, encargado: enc, proveedor: prov) { error = e } else {
                store.aviso = "✅ OC activada"
                dismiss()
            }
        }
    }
}
