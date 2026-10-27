import SwiftUI

/// Pestaña Proveedores: ranking (`renderRanking`), proveedores sin CUIT y ficha de cada uno.
struct PantallaProveedores: View {
    @Environment(Store.self) private var store
    @State private var verSinCuit = false
    @State private var cuits: [String: String] = [:]
    @State private var fichaAbierta: String?
    @State private var error: String?
    @State private var pregunta: (titulo: String, accion: () -> Void)?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.modoPrueba { FranjaPrueba() }
                    ic("trophy", "Ranking de Proveedores").font(T.syne(16)).padding(.bottom, 4)
                    sinCuit
                    let filas = store.ranking()
                    if filas.isEmpty {
                        Text("Sin órdenes registradas aún").font(T.sans(13)).foregroundStyle(T.tx3).padding()
                    }
                    ForEach(Array(filas.enumerated()), id: \.element.id) { i, f in
                        Button { fichaAbierta = f.nombre } label: { filaRanking(i, f) }.buttonStyle(.plain)
                    }
                }
                .padding(14)
            }
            .background(T.bg)
            .navigationBarTitleDisplayMode(.inline)
            .conEncabezado()
            .sheet(item: Binding(get: { fichaAbierta.map { NombreID(nombre: $0) } }, set: { fichaAbierta = $0?.nombre })) { n in
                FichaProveedorVista(nombre: n.nombre)
            }
            .alert(pregunta?.titulo ?? "", isPresented: Binding(get: { pregunta != nil }, set: { if !$0 { pregunta = nil } })) {
                Button("Guardar igual") { let a = pregunta?.accion; pregunta = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { a?() } }
                Button("Cancelar", role: .cancel) {}
            }
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .vibrarAlError(error)
        }
    }

    struct NombreID: Identifiable { var id: String { nombre }; let nombre: String }

    private func filaRanking(_ i: Int, _ f: Store.FilaRanking) -> some View {
        let pct = f.porcentaje
        let color = pct >= 80 ? T.gn : pct >= 50 ? T.am : T.rd
        let medallas = ["🥇", "🥈", "🥉"]
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                Text(i < 3 ? medallas[i] : "#\(i + 1)").font(i < 3 ? Font.title3 : T.mono(13, .medium))
                    .foregroundStyle(T.tx3).frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(f.nombre).font(T.sans(14, .semibold)).foregroundStyle(T.tx)
                    (Text("\(f.total) OC · ").foregroundStyle(T.tx3)
                     + Text("\(f.entregadas) completas").foregroundStyle(T.gn)
                     + Text(f.parciales > 0 ? " · \(f.parciales) con faltantes" : "").foregroundStyle(T.rd)
                     + Text(f.pendientes > 0 ? " · \(f.pendientes) pendientes" : "").foregroundStyle(T.am))
                        .font(T.sans(12))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(pct)%").font(T.syne(16)).foregroundStyle(color)
                    Text("entrega OK").font(T.sans(10)).foregroundStyle(T.tx3)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(T.sf2)
                    Capsule().fill(color).frame(width: g.size.width * CGFloat(pct) / 100)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .tarjeta()
    }

    /// "📋 Ver proveedores sin CUIT (N)" con un casillero para cargar cada CUIT.
    @ViewBuilder private var sinCuit: some View {
        let lista = store.fichasProveedores.filter { !$0.nombre.isEmpty && $0.cuit.trimmingCharacters(in: .whitespaces).isEmpty }
        if !lista.isEmpty && store.puedeEditar {
            let cantOC: (FichaProveedor) -> Int = { p in store.ordenes.filter { $0.proveedor == p.nombre }.count }
            Button { withAnimation(.easeOut(duration: 0.2)) { verSinCuit.toggle() } } label: {
                verSinCuit ? ic("chevron.up", "Ocultar proveedores sin CUIT") : ic("list.clipboard", "Ver proveedores sin CUIT (\(lista.count))")
            }
                .buttonStyle(BotonPWA(tipo: .blanco))
            if verSinCuit {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PROVEEDORES SIN CUIT").font(T.mono(11, .medium)).foregroundStyle(T.tx2)
                    ForEach(lista.sorted { cantOC($0) != cantOC($1) ? cantOC($0) > cantOC($1) : $0.nombre < $1.nombre }) { p in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(p.nombre).font(T.sans(13))
                                Text("\(cantOC(p)) OC").font(T.mono(10)).foregroundStyle(T.tx3)
                            }
                            Spacer()
                            TextField("30-12345678-9", text: Binding(get: { cuits[p.id] ?? "" }, set: { cuits[p.id] = $0 }))
                                .keyboardType(.numbersAndPunctuation).font(T.sans(13)).frame(width: 125)
                                .padding(6).background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.bd))
                            Button("Guardar") { guardarCuit(p) }.font(T.sans(12, .semibold))
                        }
                        .padding(.vertical, 3)
                    }
                    Text("Escribí el CUIT tal cual está en la factura (con o sin guiones). Al guardarlo, el proveedor sale de esta lista.")
                        .font(T.sans(11)).foregroundStyle(T.tx3)
                }
                .padding(12)
                .background(T.sf2, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(T.bd, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            }
        }
    }

    private func guardarCuit(_ p: FichaProveedor) {
        let c = cuits[p.id] ?? ""
        let avisos = store.avisosCuit(paraId: p.id, nombre: p.nombre, c)
        func grabar() {
            Task {
                if let e = await store.guardarCuit(p, c) { error = e } else {
                    store.aviso = "✅ CUIT de \(p.nombre) guardado"
                    cuits[p.id] = nil
                }
            }
        }
        func preguntar(_ resto: [String]) {
            guard let primera = resto.first else { grabar(); return }
            pregunta = (primera, { preguntar(Array(resto.dropFirst())) })
        }
        preguntar(avisos)
    }
}

/// Ficha del proveedor (`verFichaProveedorNombre`): datos de contacto editables y sus OC.
struct FichaProveedorVista: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let nombre: String
    @State private var tel = ""
    @State private var mail = ""
    @State private var cuit = ""
    @State private var dir = ""
    @State private var nombreNuevo = ""
    @State private var cargado = false
    @State private var error: String?

    var body: some View {
        let ocs = store.ordenes.filter { $0.proveedor.lowercased() == nombre.lowercased() }.sorted { $0.ts > $1.ts }
        let entr = ocs.filter { $0.estado == "entregado" }.count
        let pct = ocs.isEmpty ? 0 : Int((Double(entr) / Double(ocs.count) * 100).rounded())
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nombre).font(T.syne(20))
                        Text("\(ocs.count) OC · \(pct)% entregas completas").font(T.sans(12)).foregroundStyle(T.tx3)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ic("person.crop.circle", "DATOS DE CONTACTO").font(T.mono(11, .medium)).foregroundStyle(T.bl)
                        campo("Teléfono", $tel, "Ej: 3413001234", teclado: .phonePad) {
                            if !Facturas.soloDigitos(tel).isEmpty {
                                Button("WA") { if let u = URL(string: "https://wa.me/549" + Facturas.soloDigitos(tel)) { openURL(u) } }
                                    .font(T.sans(12, .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color(hex: 0x25D366), in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        campo("Mail", $mail, "proveedor@mail.com", teclado: .emailAddress) {
                            if !mail.isEmpty {
                                Button { if let u = URL(string: "mailto:" + mail) { openURL(u) } } label: { Image(systemName: "envelope") }
                                    .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(T.pp, in: RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        campo("CUIT", $cuit, "30-12345678-9", teclado: .numbersAndPunctuation) { EmptyView() }
                        campo("Dirección", $dir, "Dirección", teclado: .default) { EmptyView() }
                        campo("Nombre", $nombreNuevo, "", teclado: .default) { EmptyView() }
                        ic("exclamationmark.triangle", "Cambiar el nombre acá lo cambia en la ficha y en la lista de proveedores. Para cambiarlo también en todas las OC, usá Ajustes → Proveedores guardados → el lápiz.")
                            .font(T.sans(10)).foregroundStyle(T.am)
                        if store.puedeEditar {
                            Button { guardar() } label: { ic("square.and.arrow.down", "Guardar datos de contacto") }.buttonStyle(BotonPWA())
                        }
                    }
                    .padding(14)
                    .background(T.sf2, in: RoundedRectangle(cornerRadius: 12))

                    ic("shippingbox", "ÓRDENES DE COMPRA").font(T.mono(11, .medium)).foregroundStyle(T.bl)
                    if ocs.isEmpty { Text("Sin órdenes registradas").font(T.sans(13)).foregroundStyle(T.tx3) }
                    ForEach(ocs) { o in
                        HStack(spacing: 10) {
                            Text("OC \(o.num)").font(T.syne(13)).foregroundStyle(T.bl)
                            Text(o.obra.isEmpty ? "—" : o.obra).font(T.sans(12)).foregroundStyle(T.tx3)
                            Spacer()
                            Etiqueta.estado(o)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(T.sf2, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(18)
            }
            .background(Color.white)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
            .onAppear(perform: cargar)
            .alert("No se guardó", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(error ?? "") }
            .vibrarAlError(error)
        }
    }

    private func campo<B: View>(_ t: String, _ v: Binding<String>, _ ph: String, teclado: UIKeyboardType,
                                @ViewBuilder boton: () -> B) -> some View {
        HStack(spacing: 8) {
            Text(t).font(T.sans(12)).foregroundStyle(T.tx3).frame(width: 70, alignment: .leading)
            TextField(ph, text: v).keyboardType(teclado).textInputAutocapitalization(teclado == .default ? .words : .never)
                .font(T.sans(13)).padding(7)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(T.bd))
            boton()
        }
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        let f = store.ficha(nombre: nombre)
        tel = f?.tel ?? ""; mail = f?.mail ?? ""; cuit = f?.cuit ?? ""; dir = f?.direccion ?? ""
        nombreNuevo = nombre
    }

    private func guardar() {
        let n = nombreNuevo.trimmingCharacters(in: .whitespaces)
        Task {
            if let e = await store.guardarFicha(nombreOriginal: nombre, tel: tel.trimmingCharacters(in: .whitespaces),
                                                mail: mail.trimmingCharacters(in: .whitespaces),
                                                cuit: cuit.trimmingCharacters(in: .whitespaces),
                                                direccion: dir.trimmingCharacters(in: .whitespaces),
                                                nombre: n.isEmpty ? nombre : n) {
                error = e
            } else {
                store.aviso = "✅ Datos del proveedor guardados"
                dismiss()
            }
        }
    }
}
