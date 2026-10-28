import SwiftUI
import Charts

/// Pestaña Gastos (v0.21): cuánto se facturó por obra. Arriba el total del mes con un gráfico redondo,
/// abajo el ranking de obras; al tocar una obra se abre su ficha. Solo lee datos.
struct PantallaGastos: View {
    @Environment(Store.self) private var store
    @State private var mes = Gastos.inicioMes(Date())
    /// Por mes / Acumulado / Fechas (desde-hasta, v0.22).
    @State private var modo: Modo = .mes
    @State private var desde = Gastos.inicioMes(Gastos.sumarMeses(Date(), -2))
    @State private var hasta = Date()

    enum Modo: Hashable { case mes, acumulado, fechas }
    /// Dispara las animaciones de entrada (el redondo gira y las barras crecen).
    @State private var aparecio = false
    /// Porción del redondo resaltada (al tocarla o tocar su nombre).
    @State private var resaltada: String?
    @State private var anguloElegido: Double?

    var body: some View {
        let datos = Gastos.lista(store.ordenes, store.conciliaciones)
        let todos = datos.gastos, sinImporte = datos.sinImporte
        let meses = Gastos.meses(todos)
        let periodo: Periodo = {
            switch modo {
            case .mes: return .mes(mes)
            case .acumulado: return .total
            case .fechas: return .rango(desde, hasta)
            }
        }()
        let titulo = Gastos.titulo(periodo, primerMes: meses.first)
        let del = Gastos.filtrar(todos, periodo)
        let obras = Gastos.porObra(del)
        let colores = Gastos.coloresFijos(todos)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if store.modoPrueba { FranjaPrueba() }
                    cabecera(todos: todos, del: del, meses: meses, titulo: titulo)
                    if obras.isEmpty {
                        Text(store.ordenes.isEmpty ? "Cargando…" : "No hay facturas cargadas en este período.")
                            .font(T.sans(13)).foregroundStyle(T.tx3)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                            .tarjeta()
                    } else {
                        dona(obras: obras, total: Gastos.suma(del), colores: colores, periodo: periodo)
                        ranking(obras: obras, total: Gastos.suma(del), periodo: periodo, titulo: titulo)
                        ShareLink(item: Gastos.resumenObras(del, titulo: titulo)) {
                            ic("square.and.arrow.up", "Compartir resumen de todas las obras")
                        }
                        .buttonStyle(BotonPWA(tipo: .blanco))
                    }
                    if sinImporte > 0 {
                        Text("Hay \(sinImporte) factura\(sinImporte == 1 ? "" : "s") cargada\(sinImporte == 1 ? "" : "s") sin importe: no se suman.")
                            .font(T.sans(11)).foregroundStyle(T.tx3)
                    }
                    Text("Cuenta cada factura en el día en que se cargó. Una factura repartida en varias OC suma en cada obra lo que le tocó en la conciliación.")
                        .font(T.sans(11)).foregroundStyle(T.tx3)
                }
                .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 24)
            }
            .background(T.bg)
            .refreshable {
                await store.reconectar()
                await store.cargarConciliaciones()
            }
            .navigationBarTitleDisplayMode(.inline)
            .conEncabezado()
            .navigationDestination(for: DestinoObra.self) { FichaObra(destino: $0) }
            .task { await store.cargarConciliaciones() }
            .onAppear {
                guard !aparecio else { return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.82).delay(0.15)) { aparecio = true }
            }
            .onChange(of: modo) { _, _ in Vibrar.seleccion(); resaltada = nil }
            .onChange(of: desde) { _, _ in resaltada = nil }
            .onChange(of: hasta) { _, _ in resaltada = nil }
        }
    }

    // MARK: Total del período

    private func cabecera(todos: [Gasto], del: [Gasto], meses: [Date], titulo: String) -> some View {
        let total = Gastos.suma(del)
        let n = del.count
        var detalle = "\(n) factura\(n == 1 ? "" : "s")"
        if modo == .mes, let c = Gastos.comparacion(todos, mes: mes) {
            detalle += " · \(c.pct >= 0 ? "+" : "")\(c.pct)% \(c.contra)"
        }
        let primero = meses.first ?? mes, ultimo = meses.last ?? mes
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                flecha("chevron.left", habilitada: modo == .mes && mes > primero) { cambiarMes(-1) }
                Spacer()
                Text(modo == .fechas ? "Por fechas" : titulo).font(T.syne(16)).foregroundStyle(T.tx)
                Spacer()
                flecha("chevron.right", habilitada: modo == .mes && mes < ultimo) { cambiarMes(1) }
            }
            if modo == .acumulado {
                Text(Gastos.aclaracionAcumulado(meses.first))
                    .font(T.sans(12)).foregroundStyle(T.tx3)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
            }
            if modo == .fechas {
                // Desde / hasta: cada uno no puede pasarse del otro.
                HStack(spacing: 10) {
                    selectorFecha("Desde", $desde, rango: Date.distantPast...hasta)
                    selectorFecha("Hasta", $hasta, rango: desde...Date.distantFuture)
                }
                .environment(\.locale, Locale(identifier: "es_AR"))
            }
            Text(Gastos.pesos(total))
                .font(T.syne(30)).foregroundStyle(T.tx)
                .lineLimit(1).minimumScaleFactor(0.6)
                .contentTransition(.numericText(value: aparecio ? total : 0))
                .animation(.smooth(duration: 0.6), value: total)
            Text(detalle).font(T.sans(13)).foregroundStyle(T.tx2)
            Picker("Período", selection: $modo.animation(.snappy)) {
                Text("Por mes").tag(Modo.mes)
                Text("Acumulado").tag(Modo.acumulado)
                Text("Fechas").tag(Modo.fechas)
            }
            .pickerStyle(.segmented)
        }
        .padding(14)
        .tarjeta()
    }

    private func flecha(_ simbolo: String, habilitada: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Image(systemName: simbolo).font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 32).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(habilitada ? T.bl : T.bd)
        .disabled(!habilitada)
        .opacity(modo == .mes ? 1 : 0)
    }

    private func selectorFecha(_ rotulo: String, _ valor: Binding<Date>, rango: ClosedRange<Date>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rotulo.uppercased()).font(T.mono(9, .medium)).kerning(0.6).foregroundStyle(T.tx3)
            DatePicker(rotulo, selection: valor.animation(.snappy), in: rango, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(T.bl)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cambiarMes(_ n: Int) {
        Vibrar.seleccion()
        resaltada = nil
        withAnimation(.snappy(duration: 0.35)) { mes = Gastos.sumarMeses(mes, n) }
    }

    // MARK: Gráfico redondo (las 5 obras con color fijo + "Otras")

    private struct Porcion: Identifiable {
        let id: String
        let nombre: String
        let total: Double
        let color: Color
    }

    private func porciones(_ obras: [TotalGasto], _ colores: [String: Color]) -> [Porcion] {
        var p = obras.compactMap { o in colores[o.id].map { Porcion(id: o.id, nombre: o.nombre, total: o.total, color: $0) } }
        let resto = obras.filter { colores[$0.id] == nil }
        let r = resto.reduce(0) { $0 + $1.total }
        if r > 0 {
            p.append(Porcion(id: "_otras", nombre: resto.count == 1 ? resto[0].nombre : "Otras (\(resto.count))",
                             total: r, color: Gastos.colorOtras))
        }
        return p
    }

    private func dona(obras: [TotalGasto], total: Double, colores: [String: Color], periodo: Periodo) -> some View {
        let partes = porciones(obras, colores)
        let subtitulo: String = {
            switch periodo {
            case .mes(let m): return "EN " + Gastos.nombreMes(m, conAnio: false).uppercased()
            case .total: return "ACUMULADO"
            case .rango: return "EN EL PERÍODO"
            }
        }()
        return VStack(alignment: .leading, spacing: 10) {
            Rotulo(texto: "Reparto entre las obras")
            HStack(alignment: .center, spacing: 14) {
                Chart(partes) { p in
                    SectorMark(angle: .value("Monto", p.total), innerRadius: .ratio(0.64), angularInset: 1.2)
                        .cornerRadius(3)
                        .foregroundStyle(p.color)
                        .opacity(resaltada == nil || resaltada == p.id ? 1 : 0.3)
                }
                .chartLegend(.hidden)
                .chartAngleSelection(value: $anguloElegido)
                .frame(width: 148, height: 148)
                .rotationEffect(.degrees(aparecio ? 0 : -110))
                .scaleEffect(aparecio ? 1 : 0.75)
                .opacity(aparecio ? 1 : 0)
                .overlay {
                    VStack(spacing: 1) {
                        let valor = partes.first { $0.id == resaltada }?.total ?? total
                        Text(Gastos.corto(valor)).font(T.syne(18)).foregroundStyle(T.tx)
                            .contentTransition(.numericText(value: valor))
                        Text(resaltada == nil ? subtitulo : Gastos.porcentaje(valor, total))
                            .font(T.mono(9, .medium)).kerning(0.5).foregroundStyle(T.tx3)
                    }
                    .animation(.snappy, value: resaltada)
                    .allowsHitTesting(false)
                }
                .onChange(of: anguloElegido) { _, v in elegir(v, partes) }

                VStack(alignment: .leading, spacing: 7) {
                    ForEach(partes) { p in
                        Button {
                            Vibrar.seleccion()
                            withAnimation(.snappy) { resaltada = resaltada == p.id ? nil : p.id }
                        } label: {
                            HStack(spacing: 7) {
                                RoundedRectangle(cornerRadius: 3).fill(p.color).frame(width: 10, height: 10)
                                Text(p.nombre).font(T.sans(12, resaltada == p.id ? .bold : .medium))
                                    .foregroundStyle(T.tx).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(Gastos.porcentaje(p.total, total)).font(T.mono(11)).foregroundStyle(T.tx2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .tarjeta()
    }

    /// El dedo tocó el redondo: se busca qué porción quedó debajo.
    private func elegir(_ v: Double?, _ partes: [Porcion]) {
        guard let v else { return }
        var acumulado = 0.0
        for p in partes {
            acumulado += p.total
            if v <= acumulado {
                if resaltada != p.id {
                    Vibrar.seleccion()
                    withAnimation(.snappy) { resaltada = p.id }
                }
                return
            }
        }
    }

    // MARK: Ranking de obras

    private func ranking(obras: [TotalGasto], total: Double, periodo: Periodo, titulo: String) -> some View {
        let maximo = max(obras.first?.total ?? 1, 1)
        return VStack(alignment: .leading, spacing: 4) {
            Rotulo(texto: "Por obra · \(titulo)")
            ForEach(Array(obras.enumerated()), id: \.element.id) { i, o in
                NavigationLink(value: DestinoObra(clave: o.id, periodo: periodo)) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(o.nombre).font(T.sans(14, .semibold)).foregroundStyle(T.tx).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(Gastos.pesos(o.total)).font(T.mono(12, .medium)).foregroundStyle(T.tx)
                                .contentTransition(.numericText(value: o.total))
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(T.tx3)
                        }
                        GeometryReader { g in
                            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 0, bottomLeading: 0,
                                                                      bottomTrailing: 4, topTrailing: 4))
                                .fill(T.bl)
                                .frame(width: max(4, g.size.width * CGFloat(aparecio ? o.total / maximo : 0)))
                        }
                        .frame(height: 8)
                        Text("\(o.cantidad) factura\(o.cantidad == 1 ? "" : "s") · \(Gastos.porcentaje(o.total, total)) del total")
                            .font(T.mono(10)).foregroundStyle(T.tx3)
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.6, dampingFraction: 0.85).delay(Double(i) * 0.035), value: aparecio)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: o.total)
                if i < obras.count - 1 { Rectangle().fill(T.bd).frame(height: 1) }
            }
        }
        .padding(14)
        .tarjeta()
    }
}

/// A qué obra y período se entra al tocar una fila del ranking.
struct DestinoObra: Hashable {
    let clave: String
    let periodo: Periodo
}

// MARK: Ficha de una obra

struct FichaObra: View {
    @Environment(Store.self) private var store
    let destino: DestinoObra
    @State private var aparecio = false
    @State private var verOC: IdOC?

    struct IdOC: Identifiable { let id: String }

    private struct PuntoMes: Identifiable {
        let id: Date
        let etiqueta: String
        let valor: Double
    }

    private struct ParteProveedor: Identifiable {
        let id: String
        let nombre: String
        let total: Double
        let color: Color
    }

    private static let diaMes: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "dd/MM"
        return f
    }()

    var body: some View {
        let todos = Gastos.lista(store.ordenes, store.conciliaciones).gastos
        let meses = Gastos.meses(todos)
        let deObra = todos.filter { $0.obraClave == destino.clave }
        let del = Gastos.filtrar(deObra, destino.periodo)
        let nombre = deObra.first?.obra ?? destino.clave
        let titulo = Gastos.titulo(destino.periodo, primerMes: meses.first)

        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                totales(del: del, deObra: deObra, titulo: titulo, meses: meses)
                mesAMes(deObra: deObra, meses: meses)
                proveedores(del)
                facturas(del)
                ShareLink(item: Gastos.resumenObra(nombre, delPeriodo: del, acumulado: Gastos.suma(deObra),
                                                    titulo: titulo, primerMes: meses.first)) {
                    ic("square.and.arrow.up", "Compartir resumen de \(nombre)")
                }
                .buttonStyle(BotonPWA())
            }
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 24)
        }
        .background(T.bg)
        .navigationTitle(nombre)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $verOC) { HojaOCGasto(ocId: $0.id) }
        .onAppear {
            guard !aparecio else { return }
            Vibrar.suave()
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85).delay(0.1)) { aparecio = true }
        }
    }

    private func totales(del: [Gasto], deObra: [Gasto], titulo: String, meses: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rotulo(texto: titulo)
            Text(Gastos.pesos(Gastos.suma(del)))
                .font(T.syne(28)).foregroundStyle(T.tx).lineLimit(1).minimumScaleFactor(0.6)
            Group {
                if destino.periodo != .total {
                    Text("\(del.count) factura\(del.count == 1 ? "" : "s") · Acumulado: \(Text(Gastos.pesos(Gastos.suma(deObra))).bold())")
                } else {
                    Text("\(del.count) factura\(del.count == 1 ? "" : "s") · \(Gastos.aclaracionAcumulado(meses.first))")
                }
            }
            .font(T.sans(13)).foregroundStyle(T.tx2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .tarjeta()
    }

    /// Barras por mes de esta obra (la C de la propuesta). El mes elegido va más oscuro.
    private func mesAMes(deObra: [Gasto], meses: [Date]) -> some View {
        let conAnio = meses.count > 12
        let puntos = meses.map { m in
            PuntoMes(id: m, etiqueta: Gastos.mesCorto(m) + (conAnio ? " " + String(Gastos.calendario.component(.year, from: m) % 100) : ""),
                     valor: Gastos.suma(Gastos.filtrar(deObra, .mes(m))))
        }
        let maximo = max(puntos.map(\.valor).max() ?? 1, 1)
        // Meses resaltados: el elegido, los del rango de fechas, o el último en "Acumulado".
        let resaltar: (Date) -> Bool = { m in
            switch destino.periodo {
            case .mes(let x): return m == x
            case .total: return m == meses.last
            case .rango(let d, let h): return m >= Gastos.inicioMes(min(d, h)) && m <= Gastos.inicioMes(max(d, h))
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Rotulo(texto: "Mes a mes")
            Chart(puntos) { p in
                BarMark(x: .value("Mes", p.etiqueta), y: .value("Monto", aparecio ? p.valor : 0), width: .ratio(0.55))
                    .cornerRadius(4)
                    .foregroundStyle(T.bl.opacity(resaltar(p.id) ? 1 : 0.4))
                    .annotation(position: .top, spacing: 3) {
                        if resaltar(p.id) && p.valor > 0 {
                            Text(Gastos.corto(p.valor)).font(T.mono(10, .medium)).foregroundStyle(T.tx2)
                        }
                    }
            }
            .chartYAxis(.hidden)
            .chartYScale(domain: 0...(maximo * 1.18))
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel().font(T.mono(10)).foregroundStyle(T.tx3)
                }
            }
            .frame(height: 140)
        }
        .padding(14)
        .tarjeta()
    }

    /// "A quién se le compró": una barra partida con los 4 proveedores principales + el resto.
    private func proveedores(_ del: [Gasto]) -> some View {
        let lista = Gastos.porProveedor(del)
        let total = Gastos.suma(del)
        var partes = lista.prefix(4).enumerated().map { i, p in
            ParteProveedor(id: p.id, nombre: p.nombre, total: p.total, color: Gastos.paleta[i])
        }
        let resto = lista.dropFirst(4)
        if !resto.isEmpty {
            partes.append(ParteProveedor(id: "_otros", nombre: resto.count == 1 ? resto[resto.startIndex].nombre : "Otros (\(resto.count))",
                                         total: resto.reduce(0) { $0 + $1.total }, color: Gastos.colorOtras))
        }
        return VStack(alignment: .leading, spacing: 10) {
            Rotulo(texto: "A quién se le compró")
            if total > 0 {
                GeometryReader { g in
                    let libre = max(0, g.size.width - CGFloat(max(0, partes.count - 1)) * 2)
                    HStack(spacing: 2) {
                        ForEach(partes) { p in
                            Rectangle().fill(p.color)
                                .frame(width: max(2, libre * CGFloat(aparecio ? p.total / total : 1 / Double(max(1, partes.count)))))
                        }
                    }
                }
                .frame(height: 14)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            VStack(spacing: 7) {
                ForEach(partes) { p in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 3).fill(p.color).frame(width: 10, height: 10)
                        Text(p.nombre).font(T.sans(13, .medium)).foregroundStyle(T.tx).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(Gastos.pesos(p.total)).font(T.mono(11)).foregroundStyle(T.tx2)
                        Text(Gastos.porcentaje(p.total, total)).font(T.mono(10)).foregroundStyle(T.tx3)
                            .frame(width: 34, alignment: .trailing)
                    }
                }
            }
        }
        .padding(14)
        .tarjeta()
    }

    /// Todas las facturas del período; al tocar una se abre su OC.
    private func facturas(_ del: [Gasto]) -> some View {
        let orden = del.sorted { $0.fecha > $1.fecha }
        return VStack(alignment: .leading, spacing: 0) {
            Rotulo(texto: "Facturas (\(orden.count))").padding(.bottom, 4)
            ForEach(orden) { g in
                Button {
                    Vibrar.suave()
                    verOC = IdOC(id: g.ocId)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(g.proveedor).font(T.sans(13, .semibold)).foregroundStyle(T.tx).lineLimit(1)
                            Spacer(minLength: 6)
                            Text(Gastos.pesos(g.importe)).font(T.mono(12)).foregroundStyle(T.tx)
                        }
                        Text("Fact. \(g.num) · OC \(g.ocNum) · \(FichaObra.diaMes.string(from: g.fecha))")
                            .font(T.mono(10)).foregroundStyle(T.tx3).lineLimit(1)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if g.id != orden.last?.id { Rectangle().fill(T.bd).frame(height: 1) }
            }
        }
        .padding(14)
        .tarjeta()
    }
}

/// La OC de una factura, abierta en una hoja (con todo lo que muestra la lista de Órdenes).
struct HojaOCGasto: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let ocId: String

    var body: some View {
        let oc = store.ordenes.first { $0.id == ocId }
        NavigationStack {
            ScrollView {
                if let oc {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Renglones(espacio: 6) {
                                Text(oc.num.isEmpty ? "—" : oc.num).font(T.syne(15)).foregroundStyle(T.bl)
                                Etiqueta.estado(oc)
                                if !oc.obra.isEmpty { Etiqueta.obra(oc.obra) }
                                if let f = oc.facturaPrincipal { Etiqueta.factura(f) }
                            }
                            Text((oc.proveedor.isEmpty ? "Sin proveedor" : oc.proveedor)
                                 + (oc.responsable.isEmpty ? "" : " · " + oc.responsable))
                                .font(T.sans(13)).foregroundStyle(T.tx2)
                        }
                        .padding(.vertical, 13).padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(T.bd).frame(height: 1)
                        CuerpoOC(oc: oc)
                    }
                    .tarjeta(fondo: oc.urgente ? T.urgenteFondo : T.sf, bordeIzq: oc.urgente ? T.urgente : nil)
                    .padding(14)
                } else {
                    Text("Esta OC ya no está en la lista.").font(T.sans(13)).foregroundStyle(T.tx3).padding(28)
                }
            }
            .background(T.bg)
            .navigationTitle("OC \(oc?.num ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}
