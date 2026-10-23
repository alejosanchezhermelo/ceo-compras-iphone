import SwiftUI

/// Pestaña Órdenes, con el mismo diseño que la PWA en el celular.
struct ListaOC: View {
    @Environment(Store.self) private var store
    @State private var busqueda = ""
    @State private var pestana: Pestana = .todos
    @State private var obra = ""
    @State private var encargado = ""
    @State private var orden: Orden = .reciente
    @State private var nuevaOC = false
    @State private var verSolicitud: Solicitud?
    @State private var solicitudParaOC: Solicitud?
    @State private var pendienteOC: Solicitud?

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
                    buscador
                    selectorPestanas
                    filtros
                    if store.puedeEditar {
                        Button { nuevaOC = true } label: { Text("+ Nueva OC").font(T.sans(14, .semibold)) }
                            .buttonStyle(BotonPWA())
                    }

                    if !store.solicitudes.isEmpty {
                        Divisor(texto: "📋 Solicitudes de material", n: store.solicitudes.count,
                                color: T.pp, claro: T.ppL, medio: T.ppM)
                        ForEach(store.solicitudes) { s in
                            Button { verSolicitud = s } label: { TarjetaSolicitud(sol: s) }.buttonStyle(.plain)
                        }
                        Divisor(texto: "📦 Órdenes de compra", n: visibles.count)
                    }

                    ForEach(visibles) { oc in
                        NavigationLink(value: oc.id) { FilaOC(oc: oc, busqueda: busqueda) }.buttonStyle(.plain)
                    }
                    if visibles.isEmpty {
                        Text(store.ordenes.isEmpty ? "Cargando órdenes…" : "No hay órdenes en esta categoría")
                            .font(T.sans(13)).foregroundStyle(T.tx3)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .background(T.bg)
            .scrollDismissesKeyboard(.immediately)
            .refreshable { await store.reconectar() }
            .navigationDestination(for: String.self) { id in DetalleOC(id: id) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos() }
            }
            .sheet(isPresented: $nuevaOC) { FormularioOC(editando: nil, numeroSugerido: store.nextOCNum) }
            .sheet(item: $verSolicitud, onDismiss: {
                if let s = pendienteOC { pendienteOC = nil; solicitudParaOC = s }
            }) { s in
                DetalleSolicitud(sol: s) { pendienteOC = s }
            }
            .sheet(item: $solicitudParaOC) { s in
                FormularioOC(editando: nil, numeroSugerido: store.nextOCNum, solicitud: s)
            }
        }
    }

    // MARK: Partes

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
            TextField("Buscar por OC, proveedor, encargado, obra…", text: $busqueda)
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

/// Tarjeta de OC de la lista (`cardOC` cerrada).
struct FilaOC: View {
    let oc: OC
    var busqueda: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Renglones(espacio: 5) {
                    Text(oc.num.isEmpty ? "—" : oc.num).font(T.syne(14)).foregroundStyle(T.bl)
                    if oc.urgente { Etiqueta.urgente() }
                    Etiqueta.estado(oc)
                    if !oc.obra.isEmpty { Etiqueta.obra(oc.obra) }
                    if !oc.remito.isEmpty { Etiqueta(texto: "🧾", fondo: T.gnL, color: T.gn, borde: T.gnM) }
                    if let f = oc.facturaPrincipal { Etiqueta.factura(f) }
                }
                Text((oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor)
                     + (oc.responsable.isEmpty ? "" : " · " + oc.responsable))
                    .font(T.sans(13)).foregroundStyle(T.tx2)
                Text("Entrega: \(oc.fecha.isEmpty ? "sin fecha" : oc.fecha)")
                    .font(T.mono(11)).foregroundStyle(T.tx3)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(T.tx3)
                .padding(.top, 3)
        }
        .padding(.vertical, 13).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .tarjeta(fondo: oc.urgente ? T.urgenteFondo : T.sf, bordeIzq: oc.urgente ? T.urgente : nil)
    }
}
