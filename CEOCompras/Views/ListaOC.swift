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
    /// La OC abierta en la lista. Una sola a la vez: al abrir otra, la anterior se cierra (v0.19, pedido de Alejo).
    @State private var abierta: String?
    @State private var verObras = false
    @State private var verEncargados = false
    /// Los números de arriba arrancan en 0 y "ruedan" hasta el valor real al abrir la app.
    @State private var contadoresListos = false
    /// Las tarjetas "fantasma" se muestran hasta 10 segundos; si para entonces no llegó nada, se avisa con texto.
    @State private var esperandoDatos = true
    // Lo que se elige en el menú de mantener apretada una OC
    @State private var opcionesPDF: OC?
    @State private var editarOC: OC?
    @State private var compartir: ArchivoPDF?
    @State private var borrar: OC?
    @State private var errorMenu: String?

    var body: some View {
        let visibles = Filtro.aplicar(store.ordenes, pestana: pestana, obra: obra, encargado: encargado,
                                      busqueda: busqueda, orden: orden)
        NavigationStack {
          ScrollViewReader { proxy in
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
                        Divisor(texto: "OC importadas — pendientes de asignar", n: importadas.count,
                                color: T.am, claro: T.amL, medio: T.amM, icono: "tray.and.arrow.down")
                        ForEach(importadas) { o in
                            Button { asignar = o } label: { TarjetaImportada(oc: o) }.buttonStyle(.plain)
                        }
                    }
                    if !store.solicitudes.isEmpty {
                        Divisor(texto: "Solicitudes de material", n: store.solicitudes.count,
                                color: T.pp, claro: T.ppL, medio: T.ppM, icono: "list.clipboard")
                        ForEach(store.solicitudes) { s in
                            Button { verSolicitud = s } label: { TarjetaSolicitud(sol: s) }.buttonStyle(.plain)
                        }
                    }
                    if !importadas.isEmpty || !store.solicitudes.isEmpty {
                        Divisor(texto: "Órdenes de compra", n: store.ordenes.count - importadas.count, icono: "shippingbox")
                    }

                    let cargando = store.ordenes.isEmpty && esperandoDatos && store.mensajeConexion == nil
                    if cargando {
                        // Mientras llegan los datos: tarjetas grises con forma de OC y un brillo que pasa.
                        ForEach(0..<5, id: \.self) { _ in TarjetaFantasma() }
                            .transition(.opacity)
                    }
                    ForEach(visibles) { oc in
                        TarjetaOC(oc: oc, rubro: store.rubros.first { $0.nombre == oc.rubro },
                                  abierta: abierta == oc.id,
                                  alTocar: { tocar(oc.id, proxy) },
                                  alMenu: { elegirDelMenu($0, oc) })
                        .id(oc.id)
                        .transition(.opacity)
                    }
                    if visibles.isEmpty && !cargando {
                        Text(store.ordenes.isEmpty ? "Todavía no llegaron las órdenes. Deslizá hacia abajo para reintentar."
                                                   : "No hay órdenes en esta categoría")
                            .font(T.sans(13)).foregroundStyle(T.tx3)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .animation(.easeOut(duration: 0.35), value: store.ordenes.isEmpty)
            }
          }
            .task {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                esperandoDatos = false
            }
            .background(T.bg)
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await store.reconectar() }
            .navigationBarTitleDisplayMode(.inline)
            .conEncabezado()
            .sheet(item: $opcionesPDF) { o in OpcionesOC(oc: o) }
            .sheet(item: $editarOC) { o in FormularioOC(editando: o, numeroSugerido: store.nextOCNum) }
            .sheet(item: $compartir) { a in HojaCompartir(items: [a.url]).presentationDetents([.medium, .large]) }
            .alert("¿Eliminar la OC \(borrar?.num ?? "")? Esta acción no se puede deshacer.",
                   isPresented: Binding(get: { borrar != nil }, set: { if !$0 { borrar = nil } }), presenting: borrar) { o in
                Button("Eliminar", role: .destructive) {
                    Task {
                        if let e = await store.eliminarOC(o) { errorMenu = e } else { store.aviso = "🗑 OC \(o.num) eliminada" }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { errorMenu != nil }, set: { if !$0 { errorMenu = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMenu ?? "") }
            .vibrarAlError(errorMenu)
            .onChange(of: store.pedirNuevaOC) { _, pedido in
                // El botón flotante "➕ Nueva OC" vive pegado a la barra de abajo (ContenidoPestanas)
                if pedido { store.pedirNuevaOC = false; nuevaOC = true }
            }
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

    // MARK: Abrir / cerrar y menú de mantener apretado (v0.19)

    /// Abre la OC tocada (cerrando la que estaba abierta) o la cierra si ya estaba abierta.
    /// Al abrir, la pantalla se acomoda para que la OC quede arriba, a la vista.
    private func tocar(_ id: String, _ proxy: ScrollViewProxy) {
        Vibrar.suave()
        let abrir = abierta != id
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { abierta = abrir ? id : nil }
        if abrir {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    private func elegirDelMenu(_ accion: AccionOC, _ oc: OC) {
        // Se espera a que termine de cerrarse el menú antes de abrir otra ventana.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            switch accion {
            case .pdf:
                generar(oc) { opcionesPDF = $0 }
            case .whatsapp:
                generar(oc) { o in
                    // Sin número de PDF todavía (OC muy vieja): se abre la hoja de siempre.
                    guard o.numOCPDF != nil else { opcionesPDF = o; return }
                    do {
                        compartir = ArchivoPDF(url: try PDFOC.archivo(o), titulo: "OC \(o.numOCPDF ?? 0)")
                    } catch {
                        errorMenu = error.localizedDescription
                    }
                }
            case .copiar:
                UIPasteboard.general.string = oc.num
                store.aviso = "✅ N° de OC \(oc.num) copiado"
            case .copiarMateriales:
                UIPasteboard.general.string = ListaOC.textoMateriales(oc)
                store.aviso = "✅ Materiales copiados"
            case .editar:
                editarOC = oc
            case .urgente:
                Task {
                    if let e = await store.cambiarUrgente(oc) { errorMenu = e } else {
                        store.aviso = oc.urgente ? "Urgente desactivado" : "🔴 OC marcada como urgente"
                    }
                }
            case .eliminar:
                Vibrar.aviso()
                borrar = oc
            }
        }
    }

    /// "Copiar materiales" (v0.20): para pegar en WhatsApp y pedir cotización a otro proveedor.
    /// A propósito NO lleva N° de OC, obra ni proveedor actual.
    static func textoMateriales(_ oc: OC) -> String {
        let renglones = oc.items.map { it -> String in
            let desc = it.desc.trimmingCharacters(in: .whitespaces)
            let cant = [it.cant, it.unit.isEmpty ? it.unidad : it.unit].map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ")
            return "• " + desc + (cant.isEmpty ? "" : " — " + cant)
        }
        return "Buenas, me pasas cotizacion de estos materiales:\n" + renglones.joined(separator: "\n")
    }

    /// Igual que el botón "Generar OC": anota "OC PDF No … generada" y después sigue.
    private func generar(_ oc: OC, despues: @escaping (OC) -> Void) {
        guard store.puedeEditar else { despues(oc); return }
        Task {
            if let e = await store.registrarPDF(oc) { errorMenu = e } else { despues(oc) }
        }
    }

    // MARK: Partes

    /// Los 3 recuadros de arriba (Total OC / Entregadas / Pendientes).
    /// Los números ruedan como un cuentakilómetros: al abrir suben desde 0 y después cambian girando.
    private var estadisticas: some View {
        let ocs = store.ordenes
        let entr = ocs.filter { $0.estado == "entregado" }.count
        let pend = ocs.filter { $0.estado == "pendiente" || $0.estado == "parcial" }.count
        return HStack(spacing: 8) {
            recuadro(contadoresListos ? ocs.count : 0, "Total OC", T.tx)
            recuadro(contadoresListos ? entr : 0, "Entregadas", T.gn)
            recuadro(contadoresListos ? pend : 0, "Pendientes", T.am)
        }
        .task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            contadoresListos = true
        }
    }

    private func recuadro(_ n: Int, _ titulo: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(n)").font(T.syne(22)).foregroundStyle(color)
                .contentTransition(.numericText(value: Double(n)))
                .animation(.smooth(duration: 0.9), value: n)
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
                Button { abrirProveedores() } label: { ic("trophy", "Proveedores") }
                    .buttonStyle(BotonPWA(tipo: .blanco))
                Button { withAnimation(.easeOut(duration: 0.15)) { verObras.toggle() } } label: { ic("building.2", "Obras") }
                    .buttonStyle(BotonPWA(tipo: verObras ? .suave(T.blL, T.bl, T.blM) : .blanco))
                Button { withAnimation(.easeOut(duration: 0.15)) { verEncargados.toggle() } } label: { ic("person.2", "Encargados") }
                    .buttonStyle(BotonPWA(tipo: verEncargados ? .suave(T.gnL, T.gn, T.gnM) : .blanco))
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            if store.puedeEditar {
                Button { nuevaOC = true } label: { ic("plus", "Nueva OC") }
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

/// `#fabNuevaOC` de la PWA. En iOS 26: botón azul de vidrio del sistema; antes, azul lleno con sombra.
struct BotonNuevaOC: View {
    let accion: () -> Void
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: accion) {
                ic("plus", "Nueva OC").font(T.sans(15, .bold)).padding(.horizontal, 8).padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(T.bl)
        } else {
            Button(action: accion) {
                ic("plus", "Nueva OC")
                    .font(T.sans(14, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22).padding(.vertical, 14)
                    .background(T.bl, in: Capsule())
                    .shadow(color: T.bl.opacity(0.4), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
        }
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


/// Lo que se puede elegir al mantener apretada una OC.
enum AccionOC { case pdf, whatsapp, copiar, copiarMateriales, editar, urgente, eliminar }

/// Tarjeta de OC de la lista (`cardOC` de la PWA). Al tocarla se abre ahí mismo (▼) y muestra todo.
/// Al mantenerla apretada: vista previa de la OC + menú de acciones rápidas (v0.19).
struct TarjetaOC: View {
    @Environment(Store.self) private var store
    let oc: OC
    let rubro: Rubro?
    let abierta: Bool
    let alTocar: () -> Void
    var alMenu: (AccionOC) -> Void = { _ in }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: alTocar) { encabezado }
                .buttonStyle(.plain)
                // El menú va solo en la parte de arriba: así no se mezcla con los campos de texto de la OC abierta.
                .contextMenu { menu } preview: { VistaPreviaOC(oc: oc, rubro: rubro) }
            if abierta {
                Rectangle().fill(T.bd).frame(height: 1)
                CuerpoOC(oc: oc)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: -10)),
                                            removal: .opacity))
            }
        }
        .tarjeta(fondo: oc.urgente ? T.urgenteFondo : T.sf, bordeIzq: oc.urgente ? T.urgente : nil)
    }

    @ViewBuilder private var menu: some View {
        Section {
            Button { alMenu(.pdf) } label: { Label("Ver / imprimir PDF", systemImage: "doc.text") }
            Button { alMenu(.whatsapp) } label: { Label("Mandar por WhatsApp", systemImage: "paperplane") }
            Button { alMenu(.copiar) } label: { Label("Copiar N° de OC", systemImage: "doc.on.doc") }
            if !oc.items.isEmpty {
                Button { alMenu(.copiarMateriales) } label: { Label("Copiar materiales", systemImage: "list.bullet.clipboard") }
            }
        }
        if store.puedeEditar {
            if oc.estado != "entregado" {
                Section {
                    Button { alMenu(.editar) } label: { Label("Editar", systemImage: "pencil") }
                    Button { alMenu(.urgente) } label: {
                        Label(oc.urgente ? "Quitar urgente" : "Marcar urgente",
                              systemImage: oc.urgente ? "checkmark.circle" : "exclamationmark.circle")
                    }
                }
            }
            Section {
                Button(role: .destructive) { alMenu(.eliminar) } label: { Label("Eliminar", systemImage: "trash") }
            }
        }
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
                    if !oc.remito.isEmpty { Etiqueta(texto: "", fondo: T.gnL, color: T.gn, borde: T.gnM, icono: "doc.plaintext") }
                    if let f = oc.facturaPrincipal { Etiqueta.factura(f) }
                }
                Text((oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor)
                     + (oc.responsable.isEmpty ? "" : " · " + oc.responsable))
                    .font(T.sans(13)).foregroundStyle(T.tx2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Entrega: \(oc.fecha.isEmpty ? "sin fecha" : oc.fecha)")
                    .font(T.mono(11)).foregroundStyle(T.tx3)
            }
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
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
                Etiqueta(texto: "Importada de PDF", fondo: T.sf, color: T.am, borde: T.amM, icono: "tray.and.arrow.down")
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
                Section {
                    Picker("Obra *", selection: $obra) {
                        Text("— Seleccionar —").tag("")
                        ForEach(store.obras, id: \.self) { Text($0).tag($0) }
                    }
                    Picker("Encargado *", selection: $enc) {
                        Text("— Seleccionar —").tag("")
                        ForEach(store.encargados, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Proveedor", text: $prov)
                    Button { guardar() } label: { ic("checkmark.circle", "Guardar asignación y activar OC") }
                } header: { ic("gearshape", "Asignar obra y encargado") }
                Section { Button(role: .destructive) { Vibrar.aviso(); preguntarBorrar = true } label: { ic("trash", "Eliminar") } }
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
            .vibrarAlError(error)
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

/// Lo que aparece arriba del menú al mantener apretada una OC: los datos principales y los materiales.
struct VistaPreviaOC: View {
    let oc: OC
    let rubro: Rubro?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Renglones(espacio: 6) {
                Text(oc.num.isEmpty ? "—" : oc.num).font(T.syne(17)).foregroundStyle(T.bl)
                if oc.urgente { Etiqueta.urgente() }
                Etiqueta.estado(oc)
                if let rubro { Etiqueta.rubro(rubro) }
            }
            VStack(alignment: .leading, spacing: 3) {
                ic("storefront", oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor)
                    .font(T.sans(14, .semibold)).foregroundStyle(T.tx)
                if !oc.obra.isEmpty { ic("building.2", oc.obra).font(T.sans(13)).foregroundStyle(T.tx2) }
                if !oc.responsable.isEmpty { ic("person", oc.responsable).font(T.sans(13)).foregroundStyle(T.tx2) }
                ic("calendar", "Entrega: \(oc.fecha.isEmpty ? "sin fecha" : oc.fecha)").font(T.mono(11)).foregroundStyle(T.tx3)
            }
            Rectangle().fill(T.bd).frame(height: 1)
            Rotulo(texto: "Materiales")
            if oc.items.isEmpty {
                Text("Sin ítems").font(T.sans(13)).foregroundStyle(T.tx3)
            }
            ForEach(oc.items.prefix(8)) { it in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(it.desc).frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
                    Text(it.cant + (it.unit.isEmpty ? "" : " " + it.unit)).foregroundStyle(T.tx2)
                }
                .font(T.sans(13)).foregroundStyle(T.tx)
            }
            if oc.items.count > 8 {
                Text("y \(oc.items.count - 8) más…").font(T.sans(12)).foregroundStyle(T.tx3)
            }
            if !oc.notas.isEmpty {
                Text(oc.notas).font(T.sans(12)).foregroundStyle(T.tx2).lineLimit(3)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(oc.urgente ? T.urgenteFondo : T.sf)
    }
}
