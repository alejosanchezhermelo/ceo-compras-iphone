import SwiftUI

// MARK: Gastos por obra (v0.21)
// Suma lo facturado (las facturas cargadas en las OC) por obra, por proveedor y por mes.
// Solo lee: no escribe nada en la base.

/// Una factura (o la parte de una factura que le tocó a una OC), lista para sumar.
struct Gasto: Identifiable, Hashable {
    let id: String
    let ocId: String
    let ocNum: String
    let num: String
    /// Nombre de la obra como se muestra, y la clave para agrupar (sin mayúsculas ni espacios de más).
    let obra: String
    let obraClave: String
    let proveedor: String
    let importe: Double
    let fecha: Date
}

/// Total de una obra (o de un proveedor) en un período.
struct TotalGasto: Identifiable, Hashable {
    let id: String
    let nombre: String
    let total: Double
    let cantidad: Int
}

/// Qué se está mirando: un mes (su primer día), todo lo cargado (acumulado) o entre dos fechas (v0.22).
enum Periodo: Hashable {
    case mes(Date)
    case total
    /// Desde / hasta, los dos días incluidos.
    case rango(Date, Date)
}

enum Gastos {
    static let calendario: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "es_AR")
        c.timeZone = .current
        return c
    }()

    /// Todas las facturas con importe y fecha. Las que no tienen importe propio lo buscan en la conciliación
    /// (facturas repartidas en varias OC y conciliadas en la PC). Devuelve también cuántas quedaron afuera por no tener importe.
    static func lista(_ ordenes: [OC], _ conciliaciones: [String: [String: Double]]) -> (gastos: [Gasto], sinImporte: Int) {
        var nombres: [String: [String: Int]] = [:]   // clave → (forma de escribirla → veces)
        var crudos: [(OC, Int, FacturaOC, Double, Double)] = []
        var sinImporte = 0
        for oc in ordenes where oc.tieneFactura {
            let tsBase = oc.facturaPrincipal?.ts
            for (i, f) in oc.facturas.enumerated() {
                guard let imp = f.importe ?? conciliaciones[f.num]?[oc.id] else { sinImporte += 1; continue }
                guard let ts = f.ts ?? tsBase, ts > 0 else { continue }
                crudos.append((oc, i, f, imp, ts))
                let n = nombreObra(oc.obra)
                nombres[claveObra(n), default: [:]][n, default: 0] += 1
            }
        }
        // Si la misma obra está escrita de varias formas ("obra x" / "Obra X"), se muestra la más usada.
        let mostrar = nombres.mapValues { formas in formas.max { a, b in a.value < b.value }?.key ?? "" }
        let gastos = crudos.map { c -> Gasto in
            let (oc, i, f, imp, ts) = c
            let clave = claveObra(nombreObra(oc.obra))
            return Gasto(id: oc.id + "-" + String(i), ocId: oc.id, ocNum: oc.num, num: f.num,
                         obra: mostrar[clave] ?? nombreObra(oc.obra), obraClave: clave,
                         proveedor: oc.proveedor.trimmingCharacters(in: .whitespaces).isEmpty ? "Sin proveedor"
                                                                                             : oc.proveedor.trimmingCharacters(in: .whitespaces),
                         importe: imp, fecha: Date(timeIntervalSince1970: ts / 1000))
        }
        return (gastos, sinImporte)
    }

    static func nombreObra(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? "Sin obra" : t
    }

    static func claveObra(_ s: String) -> String { s.lowercased() }

    static func inicioMes(_ d: Date) -> Date {
        calendario.date(from: calendario.dateComponents([.year, .month], from: d)) ?? d
    }

    static func sumarMeses(_ d: Date, _ n: Int) -> Date {
        calendario.date(byAdding: .month, value: n, to: d) ?? d
    }

    static func filtrar(_ g: [Gasto], _ p: Periodo) -> [Gasto] {
        switch p {
        case .total: return g
        case .mes(let m): return g.filter { calendario.isDate($0.fecha, equalTo: m, toGranularity: .month) }
        case .rango(let d, let h):
            let desde = calendario.startOfDay(for: min(d, h))
            let hasta = calendario.date(byAdding: .day, value: 1, to: calendario.startOfDay(for: max(d, h))) ?? h
            return g.filter { $0.fecha >= desde && $0.fecha < hasta }
        }
    }

    static func suma(_ g: [Gasto]) -> Double { g.reduce(0) { $0 + $1.importe } }

    /// Por obra, de mayor a menor.
    static func porObra(_ g: [Gasto]) -> [TotalGasto] {
        Dictionary(grouping: g, by: \.obraClave).map { clave, l in
            TotalGasto(id: clave, nombre: l[0].obra, total: suma(l), cantidad: l.count)
        }.sorted { $0.total > $1.total }
    }

    /// Por proveedor, de mayor a menor.
    static func porProveedor(_ g: [Gasto]) -> [TotalGasto] {
        Dictionary(grouping: g, by: { $0.proveedor.lowercased() }).map { clave, l in
            TotalGasto(id: clave, nombre: l[0].proveedor, total: suma(l), cantidad: l.count)
        }.sorted { $0.total > $1.total }
    }

    /// Los meses desde la primera factura hasta el mes actual (o el de la última factura, si es posterior).
    static func meses(_ g: [Gasto], hoy: Date = Date()) -> [Date] {
        guard let primera = g.map(\.fecha).min() else { return [inicioMes(hoy)] }
        let ultimo = inicioMes(max(hoy, g.map(\.fecha).max() ?? hoy))
        var m = inicioMes(primera), lista: [Date] = []
        while m <= ultimo && lista.count < 240 { lista.append(m); m = sumarMeses(m, 1) }
        return lista
    }

    /// Comparación con el mes anterior. Si el mes está en curso, contra el mes anterior "a esta altura"
    /// (los mismos días), para no comparar medio mes contra un mes entero.
    static func comparacion(_ g: [Gasto], mes: Date, hoy: Date = Date()) -> (pct: Int, contra: String)? {
        let anterior = sumarMeses(mes, -1)
        let enCurso = calendario.isDate(mes, equalTo: hoy, toGranularity: .month)
        var previo = filtrar(g, .mes(anterior))
        if enCurso {
            let dia = calendario.component(.day, from: hoy)
            previo = previo.filter { calendario.component(.day, from: $0.fecha) <= dia }
        }
        let p = suma(previo)
        guard p > 0 else { return nil }
        let pct = Int(((suma(filtrar(g, .mes(mes))) / p - 1) * 100).rounded())
        let nombre = nombreMes(anterior, conAnio: false).lowercased()
        return (pct, enCurso ? "que a esta altura de \(nombre)" : "que \(nombre)")
    }

    // MARK: Textos

    private static let nombresMes = ["Enero", "Febrero", "Marzo", "Abril", "Mayo", "Junio", "Julio", "Agosto",
                                     "Septiembre", "Octubre", "Noviembre", "Diciembre"]

    static func nombreMes(_ d: Date, conAnio: Bool = true) -> String {
        let c = calendario.dateComponents([.year, .month], from: d)
        let n = nombresMes[max(0, min(11, (c.month ?? 1) - 1))]
        return conAnio ? "\(n) \(c.year ?? 0)" : n
    }

    static func mesCorto(_ d: Date) -> String { String(nombreMes(d, conAnio: false).prefix(3)) }

    static func titulo(_ p: Periodo, primerMes: Date?) -> String {
        switch p {
        case .mes(let m): return nombreMes(m)
        case .total: return "Acumulado"
        case .rango(let d, let h): return "Del \(fecha(min(d, h))) al \(fecha(max(d, h)))"
        }
    }

    /// "Desde agosto 2026, cuando se empezaron a cargar las facturas."
    static func aclaracionAcumulado(_ primerMes: Date?) -> String {
        guard let m = primerMes else { return "Todo lo cargado hasta hoy." }
        return "Desde \(nombreMes(m).lowercased()), cuando se empezaron a cargar las facturas."
    }

    private static let formatoFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()

    static func fecha(_ d: Date) -> String { formatoFecha.string(from: d) }

    private static let enteros: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    /// "$ 19.656.805" (sin centavos).
    static func pesos(_ n: Double) -> String { "$ " + (enteros.string(from: NSNumber(value: n.rounded())) ?? "0") }

    /// "19,7 M" para los gráficos; "850 mil" si es menos de un millón.
    static func corto(_ n: Double) -> String {
        if abs(n) >= 1_000_000 {
            return String(format: "%.1f M", n / 1_000_000).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int((n / 1000).rounded())) mil"
    }

    static func porcentaje(_ parte: Double, _ total: Double) -> String {
        total > 0 ? "\(Int((parte / total * 100).rounded()))%" : "–"
    }

    /// Texto para mandar por WhatsApp o mail con todas las obras del período.
    static func resumenObras(_ g: [Gasto], titulo: String) -> String {
        var t = "Gastos por obra — \(titulo)\nTotal: \(pesos(suma(g))) (\(g.count) facturas)\n"
        for o in porObra(g) { t += "\n• \(o.nombre): \(pesos(o.total))" }
        return t
    }

    /// Texto con una obra: total del período, total acumulado y los proveedores.
    static func resumenObra(_ nombre: String, delPeriodo g: [Gasto], acumulado: Double, titulo: String, primerMes: Date?) -> String {
        var t = "Obra \(nombre) — \(titulo)\nTotal: \(pesos(suma(g))) (\(g.count) facturas)\n"
        if titulo != Gastos.titulo(.total, primerMes: primerMes) {
            let desde = primerMes.map { " (desde " + nombreMes($0).lowercased() + ")" } ?? ""
            t += "Acumulado\(desde): \(pesos(acumulado))\n"
        }
        t += "\nPor proveedor:"
        for p in porProveedor(g) { t += "\n• \(p.nombre): \(pesos(p.total))" }
        return t
    }

    // MARK: Colores del gráfico redondo
    // Validados para daltonismo (orden fijo). Cada obra tiene SIEMPRE el mismo color: se reparten
    // entre las 5 obras con más gasto acumulado, así no cambian al pasar de un mes a otro.
    static let paleta: [Color] = [Color(hex: 0x2A78D6), Color(hex: 0xEB6834), Color(hex: 0x1BAF7A),
                                  Color(hex: 0xEDA100), Color(hex: 0xE87BA4)]
    static let colorOtras = Color(hex: 0xB9B3AA)

    static func coloresFijos(_ todos: [Gasto]) -> [String: Color] {
        var c: [String: Color] = [:]
        for (i, o) in porObra(todos).prefix(paleta.count).enumerated() { c[o.id] = paleta[i] }
        return c
    }
}
