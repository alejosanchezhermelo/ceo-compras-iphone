import SwiftUI
import UniformTypeIdentifiers

/// Pestaña Precios (`renderPrecios`): nueva lista, comparador de dos proveedores y listas guardadas.
struct PantallaPrecios: View {
    @Environment(Store.self) private var store
    @State private var prov = ""
    @State private var conFecha = false
    @State private var fecha = Date()
    @State private var modoArchivo = false
    @State private var filas: [FilaPrecio] = [FilaPrecio(), FilaPrecio()]
    @State private var archivo: (datos: Data, tipo: String, nombre: String)?
    @State private var elegirArchivo = false
    @State private var mensajeExtraer: String?
    @State private var cmp1 = ""
    @State private var cmp2 = ""
    @State private var abiertos: Set<String> = []
    @State private var elegida: [String: String] = [:]
    @State private var verArchivo: ArchivoPDF?
    @State private var verImagen: UIImage?
    @State private var borrar: ListaPrecios?
    @State private var error: String?
    @State private var trabajando = false

    struct FilaPrecio: Identifiable { let id = UUID(); var prod = ""; var precio = "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if store.modoPrueba { FranjaPrueba() }
                    if store.puedeEditar { nuevaLista }
                    comparador
                    Text("📋 Listas guardadas").font(T.syne(15)).padding(.top, 4)
                    guardadas
                }
                .padding(14)
            }
            .background(T.bg)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .conEncabezado()
            .fileImporter(isPresented: $elegirArchivo, allowedContentTypes: [.pdf, .jpeg, .png, .image]) { r in cargarArchivo(r) }
            .sheet(item: $verArchivo) { VisorPDF(archivo: $0) }
            .sheet(item: Binding(get: { verImagen.map { ImagenID(img: $0) } }, set: { verImagen = $0?.img })) { i in
                NavigationStack {
                    ScrollView { Image(uiImage: i.img).resizable().scaledToFit().padding() }
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { verImagen = nil } } }
                }
            }
            .alert("¿Eliminar esta lista de precios?", isPresented: Binding(get: { borrar != nil }, set: { if !$0 { borrar = nil } }),
                   presenting: borrar) { l in
                Button("Eliminar", role: .destructive) { correr({ await store.eliminarLista(l) }, ok: "Lista eliminada") }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
        }
    }

    struct ImagenID: Identifiable { let id = UUID(); let img: UIImage }

    // MARK: ➕ Nueva lista

    private var nuevaLista: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("➕ Nueva lista de precios").font(T.syne(15))
            TextField("Proveedor *", text: $prov).textInputAutocapitalization(.words).campoPWA()
            Toggle("Fecha de la lista", isOn: $conFecha.animation()).font(T.sans(14))
            if conFecha {
                DatePicker("Fecha", selection: $fecha, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "es_AR")).font(T.sans(14))
            }
            Picker("", selection: $modoArchivo) {
                Text("📝 Cargar manualmente").tag(false)
                Text("📎 Subir PDF / imagen").tag(true)
            }
            .pickerStyle(.segmented)

            if !modoArchivo {
                HStack {
                    Text("Producto").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Precio ($)").frame(width: 110, alignment: .leading)
                    Spacer().frame(width: 22)
                }
                .font(T.sans(11)).foregroundStyle(T.tx3)
                ForEach($filas) { $f in
                    HStack(spacing: 6) {
                        TextField("Producto / material", text: $f.prod).campoPWA()
                        TextField("Precio", text: $f.precio).keyboardType(.decimalPad).campoPWA().frame(width: 110)
                        Button { filas.removeAll { $0.id == f.id } } label: { Image(systemName: "xmark").foregroundStyle(T.tx3) }
                            .frame(width: 22)
                    }
                }
                Button("+ Agregar ítem") { filas.append(FilaPrecio()) }.font(T.sans(13, .medium))
            } else {
                Button { elegirArchivo = true } label: {
                    VStack(spacing: 6) {
                        Text("📎").font(.largeTitle)
                        Text(archivo?.nombre ?? "Tocá para elegir un PDF o una imagen").font(T.sans(13))
                            .foregroundStyle(archivo == nil ? T.tx3 : T.bl)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 22)
                    .background(T.sf, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(T.bd2, style: StrokeStyle(lineWidth: 2, dash: [6, 4])))
                }
                .buttonStyle(.plain)
                if let a = archivo, a.tipo == "application/pdf" {
                    Button("🔍 Extraer precios del PDF automáticamente") { extraer(a.datos) }.buttonStyle(BotonPWA())
                }
                if let m = mensajeExtraer { Text(m).font(T.sans(13)).foregroundStyle(m.hasPrefix("✅") ? T.gn : T.rd) }
            }
            Button("Guardar lista de precios") { guardar() }.buttonStyle(BotonPWA()).disabled(trabajando)
        }
        .padding(14)
        .tarjeta()
    }

    // MARK: ⚖️ Comparar dos proveedores

    @ViewBuilder private var comparador: some View {
        let manuales = store.listasPrecios.filter { $0.tipo == "manual" }.sorted { $0.ts > $1.ts }
        if manuales.count >= 2 {
            VStack(alignment: .leading, spacing: 10) {
                Text("⚖️ Comparar dos proveedores").font(T.syne(15))
                selectorLista("Proveedor 1", $cmp1, manuales)
                selectorLista("Proveedor 2", $cmp2, manuales)
                if let l1 = manuales.first(where: { $0.id == cmp1 }), let l2 = manuales.first(where: { $0.id == cmp2 }) {
                    tablaComparacion(l1, l2)
                }
            }
            .padding(14)
            .tarjeta()
        }
    }

    private func selectorLista(_ titulo: String, _ sel: Binding<String>, _ manuales: [ListaPrecios]) -> some View {
        Picker(titulo, selection: sel) {
            Text("— Seleccionar —").tag("")
            ForEach(manuales) { l in Text(l.proveedor + (l.fecha.isEmpty ? "" : " (\(l.fecha))")).tag(l.id) }
        }
        .font(T.sans(14))
    }

    /// `renderCmp`: une los productos (sin mirar mayúsculas) y muestra la diferencia en %.
    private func tablaComparacion(_ l1: ListaPrecios, _ l2: ListaPrecios) -> some View {
        var m1: [String: Double] = [:], m2: [String: Double] = [:]
        for i in l1.items { m1[i.prod.lowercased()] = Double(i.precio) ?? 0 }
        for i in l2.items { m2[i.prod.lowercased()] = Double(i.precio) ?? 0 }
        let todos = Array(Set(m1.keys).union(m2.keys)).sorted()
        return VStack(spacing: 0) {
            HStack {
                Text("Producto").frame(maxWidth: .infinity, alignment: .leading)
                Text(l1.proveedor).frame(width: 70, alignment: .trailing).lineLimit(1)
                Text(l2.proveedor).frame(width: 70, alignment: .trailing).lineLimit(1)
                Text("Dif.").frame(width: 50)
            }
            .font(T.sans(11, .semibold)).padding(6).background(T.sf2)
            ForEach(todos, id: \.self) { k in
                HStack {
                    Text(k).frame(maxWidth: .infinity, alignment: .leading)
                    Text(m1[k].map { "$" + Store.numeroAR($0) } ?? "-").frame(width: 70, alignment: .trailing)
                    Text(m2[k].map { "$" + Store.numeroAR($0) } ?? "-").frame(width: 70, alignment: .trailing)
                    Group {
                        if let p1 = m1[k], let p2 = m2[k] {
                            let pct = p1 != 0 ? Int(((p2 - p1) / p1 * 100).rounded()) : 0
                            if pct > 0 { Text("▲ +\(pct)%").foregroundStyle(T.rd) }
                            else if pct < 0 { Text("▼ \(pct)%").foregroundStyle(T.gn) }
                            else { Text("=") }
                        } else { Text("") }
                    }
                    .frame(width: 50)
                }
                .font(T.sans(12)).padding(.vertical, 5).padding(.horizontal, 6)
            }
        }
    }

    // MARK: 📋 Listas guardadas (agrupadas por proveedor)

    @ViewBuilder private var guardadas: some View {
        let porProv = Dictionary(grouping: store.listasPrecios, by: \.proveedor)
        if porProv.isEmpty {
            Text("No hay listas cargadas aún.").font(T.sans(13)).foregroundStyle(T.tx3)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
        ForEach(porProv.keys.sorted(), id: \.self) { p in
            let listas = (porProv[p] ?? []).sorted { $0.ts > $1.ts }
            let ultima = listas[0]
            let abierto = abiertos.contains(p)
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if abierto { abiertos.remove(p) } else { abiertos.insert(p) }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p).font(T.sans(14, .semibold)).foregroundStyle(T.tx)
                            Text((listas.count > 1 ? "\(listas.count) listas · " : "") + (ultima.fecha.isEmpty ? "" : "Última: \(ultima.fecha)")
                                 + " · " + (ultima.tipo == "archivo" ? "📎 Archivo" : "\(ultima.items.count) productos"))
                                .font(T.mono(11)).foregroundStyle(T.tx3)
                        }
                        Spacer()
                        Image(systemName: abierto ? "chevron.up" : "chevron.down").foregroundStyle(T.tx3)
                    }
                }
                .buttonStyle(.plain)
                if abierto {
                    let actual = listas.first { $0.id == elegida[p] } ?? ultima
                    if listas.count > 1 {
                        Picker("Ver lista", selection: Binding(get: { actual.id }, set: { elegida[p] = $0 })) {
                            ForEach(listas) { l in
                                Text(l.rotulo + (l.tipo == "archivo" ? " (PDF/img)" : " (\(l.items.count) prod.)")).tag(l.id)
                            }
                        }
                        .font(T.sans(13))
                    }
                    contenido(actual)
                    if store.puedeEditar {
                        Divider()
                        ForEach(listas) { l in
                            Button("🗑 Eliminar " + (l.tipo == "archivo" ? "PDF " : "lista ") + l.rotulo) { borrar = l }
                                .font(T.sans(12)).foregroundStyle(T.rd)
                        }
                    }
                }
            }
            .padding(14)
            .tarjeta()
        }
    }

    @ViewBuilder private func contenido(_ l: ListaPrecios) -> some View {
        if l.tipo == "archivo" {
            if l.fileType.hasPrefix("image"), let d = Store.datosDeDataURL(l.fileData), let img = UIImage(data: d) {
                Button { verImagen = img } label: {
                    Image(uiImage: img).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Button("📄 Ver PDF") { abrirPDF(l) }.buttonStyle(BotonPWA(tipo: .suave(T.blL, T.bl, T.blM)))
            }
        } else {
            VStack(spacing: 0) {
                HStack {
                    Text("Producto").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Precio ($)")
                }
                .font(T.mono(11)).foregroundStyle(T.tx3).padding(.vertical, 5)
                if l.items.isEmpty { Text("Sin ítems").font(T.sans(13)).foregroundStyle(T.tx3) }
                ForEach(Array(l.items.enumerated()), id: \.offset) { _, it in
                    HStack {
                        Text(it.prod).frame(maxWidth: .infinity, alignment: .leading)
                        Text("$" + Store.numeroAR(Double(it.precio) ?? 0)).font(T.mono(12))
                    }
                    .font(T.sans(13)).padding(.vertical, 5)
                    .overlay(alignment: .bottom) { Rectangle().fill(T.bd).frame(height: 1) }
                }
            }
        }
    }

    // MARK: Acciones

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

    private func guardar() {
        let p = prov, f = conFecha ? fecha : nil
        let limpiar = { prov = ""; conFecha = false; filas = [FilaPrecio(), FilaPrecio()]; archivo = nil; mensajeExtraer = nil }
        if modoArchivo {
            guard let a = archivo else { error = "Seleccioná el PDF o imagen primero"; return }
            correr({ await store.guardarListaArchivo(proveedor: p, fecha: f, datos: a.datos, tipo: a.tipo) }, ok: "✅ Lista guardada", despues: limpiar)
        } else {
            let items = filas.map { ($0.prod, $0.precio) }
            correr({ await store.guardarListaManual(proveedor: p, fecha: f, items: items) }, ok: "✅ Lista guardada", despues: limpiar)
        }
    }

    private func cargarArchivo(_ r: Result<URL, Error>) {
        guard case .success(let url) = r else { return }
        let acceso = url.startAccessingSecurityScopedResource()
        defer { if acceso { url.stopAccessingSecurityScopedResource() } }
        guard let d = try? Data(contentsOf: url) else { error = "No se pudo leer el archivo"; return }
        if d.count > 2 * 1024 * 1024 { error = "El archivo es muy grande (máx. 2 MB)"; return }
        let tipo = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/pdf"
        archivo = (d, tipo, "📎 " + url.lastPathComponent)
        mensajeExtraer = nil
    }

    private func extraer(_ d: Data) {
        let items = Store.extraerPrecios(de: d)
        if items.isEmpty {
            mensajeExtraer = "No se pudieron extraer precios. Cargalos manualmente."
            return
        }
        filas = items.map { FilaPrecio(prod: $0.0, precio: $0.1) }
        modoArchivo = false
        mensajeExtraer = nil
        store.aviso = "✅ \(items.count) productos encontrados. Revisá y guardá."
    }

    private func abrirPDF(_ l: ListaPrecios) {
        guard let d = Store.datosDeDataURL(l.fileData) else { error = "Sin datos de PDF"; return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Lista \(l.proveedor).pdf")
        do {
            try d.write(to: url, options: .atomic)
            verArchivo = ArchivoPDF(url: url, titulo: "Lista \(l.proveedor)")
        } catch { self.error = "No se pudo abrir el PDF" }
    }
}

extension Store {
    /// "data:application/pdf;base64,AAAA" → los bytes
    nonisolated static func datosDeDataURL(_ s: String) -> Data? {
        let b64 = s.components(separatedBy: ",").count > 1 ? s.components(separatedBy: ",")[1] : s
        return Data(base64Encoded: b64, options: .ignoreUnknownCharacters)
    }

    /// `toLocaleString('es-AR')` de un número (hasta 3 decimales, con punto de miles)
    nonisolated static func numeroAR(_ n: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 3
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}
