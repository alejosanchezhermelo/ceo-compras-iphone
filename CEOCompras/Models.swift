import Foundation

struct ItemOC: Identifiable, Hashable {
    let id: Int
    let desc: String
    let cant: String
    let unit: String
    /// Las OC guardan la unidad en `unit`; `unidad` queda solo como respaldo. El PDF (web e iPhone,
    /// desde 2026-10-26) usa `unit || unidad`.
    let unidad: String
}

struct FacturaOC: Hashable {
    let num: String
    let importe: Double?
    var cuit: String = ""
    var total: Double? = nil
    var ts: Double? = nil

    /// Como se guarda en Firebase (`{num, importe, cuit, total, ts}`); sin importe si no lo tenía.
    var diccionario: [String: Any] {
        var d: [String: Any] = ["num": num, "cuit": cuit]
        if let importe { d["importe"] = importe }
        if let total { d["total"] = total }
        if let ts { d["ts"] = Int64(ts) }
        return d
    }
}

/// Solicitud de material que manda un encargado (`solicitudes/<id>`).
struct Solicitud: Identifiable, Hashable {
    let id: String
    let encargado: String
    let obra: String
    let texto: String
    let notas: String
    let estado: String
    let comentarioCompras: String
    let ts: Double

    init?(clave: String, _ valor: Any) {
        guard let d = valor as? [String: Any] else { return nil }
        let i = texto_(d["id"])
        id = i.isEmpty ? clave : i
        encargado = texto_(d["encargado"])
        obra = texto_(d["obra"])
        texto = texto_(d["texto"])
        notas = texto_(d["notas"])
        estado = texto_(d["estado"])
        comentarioCompras = texto_(d["comentarioCompras"])
        ts = numero(d["ts"]) ?? 0
    }
}

/// Alias de `texto()` para usar dentro de structs que tienen un campo llamado `texto`.
func texto_(_ v: Any?) -> String { texto(v) }

struct NotaInterna: Hashable {
    let txt: String
    let ts: Double?
}

struct EventoOC: Identifiable, Hashable {
    let id: String
    let ocId: String
    let tipo: String
    let texto: String
    let ts: Double
}

/// Una orden de compra, leída de `ordenes/<id>` tal como la guarda la web.
struct OC: Identifiable, Hashable {
    let id: String
    let num: String
    let numOCPDF: Int?
    let estado: String
    let obra: String
    let proveedor: String
    /// `provId` guardado (formato nuevo); nil en OC de formato viejo.
    let provIdGuardado: String?
    let responsable: String
    let rubro: String
    let fecha: String
    let notas: String
    let comentario: String
    let remito: String
    let fechaEntregaReal: String
    let solRef: String
    let archivoOrigen: String
    let urgente: Bool
    let importadoPDF: Bool
    let ts: Double
    let items: [ItemOC]
    let tieneFactura: Bool
    /// `o.factura` (la que muestra la etiqueta de la tarjeta).
    let facturaPrincipal: FacturaOC?
    /// Igual que `_facLista(o)` de la web.
    let facturas: [FacturaOC]
    let notasInternas: [NotaInterna]

    init?(clave: String, _ valor: Any) {
        guard let d = valor as? [String: Any] else { return nil }
        let idGuardado = texto(d["id"])
        id = idGuardado.isEmpty ? clave : idGuardado
        num = texto(d["num"])
        if let n = numero(d["numOCPDF"]), n > 0 { numOCPDF = Int(n) } else { numOCPDF = nil }
        estado = texto(d["estado"])
        obra = texto(d["obra"])
        proveedor = texto(d["proveedor"])
        let pid = texto(d["provId"])
        provIdGuardado = pid.isEmpty ? nil : pid
        responsable = texto(d["responsable"])
        rubro = texto(d["rubro"])
        fecha = texto(d["fecha"])
        notas = texto(d["notas"])
        comentario = texto(d["comentario"])
        remito = texto(d["remito"])
        fechaEntregaReal = texto(d["fechaEntregaReal"])
        solRef = texto(d["solRef"])
        archivoOrigen = texto(d["archivoOrigen"])
        urgente = verdadero(d["urgente"])
        importadoPDF = verdadero(d["importadoPDF"])
        ts = numero(d["ts"]) ?? 0

        items = JSONTree.lista(d["items"]).enumerated().compactMap { i, x in
            guard let it = x as? [String: Any] else { return nil }
            return ItemOC(id: i, desc: texto(it["desc"]), cant: texto(it["cant"]),
                          unit: texto(it["unit"]), unidad: texto(it["unidad"]))
        }

        func factura(_ v: Any) -> FacturaOC? {
            guard let f = v as? [String: Any] else { return nil }
            return FacturaOC(num: texto(f["num"]), importe: numero(f["importe"]), cuit: texto(f["cuit"]),
                             total: numero(f["total"]), ts: numero(f["ts"]))
        }
        tieneFactura = verdadero(d["factura"])
        if tieneFactura, let f = d["factura"].flatMap(factura) {
            facturaPrincipal = f
            let varias = JSONTree.lista(d["facturas"]).compactMap(factura)
            facturas = varias.isEmpty ? [f] : varias
        } else {
            facturaPrincipal = nil
            facturas = []
        }

        notasInternas = JSONTree.lista(d["notasInternas"]).compactMap { x in
            guard let n = x as? [String: Any] else { return nil }
            return NotaInterna(txt: texto(n["txt"]), ts: numero(n["ts"]))
        }
    }

    var totalFacturado: Double { facturas.reduce(0) { $0 + ($1.importe ?? 0) } }

    /// La web muestra la fecha de entrega tal cual; acá se da vuelta (2026-10-23 → 23/10/2026).
    var fechaEntregaTexto: String {
        fecha.isEmpty ? "sin fecha" : fecha.split(separator: "-").reversed().joined(separator: "/")
    }

    /// `parseInt(o.num || 0)` de la web.
    var numeroEntero: Int { Int(num.prefix { $0.isNumber }) ?? 0 }

    var rangoEstado: Int { ["pendiente": 0, "parcial": 1, "entregado": 2][estado] ?? 0 }
}

enum Pestana: String, CaseIterable, Identifiable {
    case todos, pendiente, parcial, entregado, facturadas
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .todos: return "Todos"
        case .pendiente: return "Pend."
        case .parcial: return "Parcial"
        case .entregado: return "Entregado"
        case .facturadas: return "Facturadas"
        }
    }
}

enum Orden: String, CaseIterable, Identifiable {
    case reciente, numero, proveedor, obra, estado
    var id: String { rawValue }
    var titulo: String {
        switch self {
        case .reciente: return "Más recientes"
        case .numero: return "N° de OC"
        case .proveedor: return "Proveedor"
        case .obra: return "Obra"
        case .estado: return "Estado"
        }
    }
}

/// Mismos filtros y el mismo orden que `renderC()` de la web.
enum Filtro {
    static func aplicar(_ ocs: [OC], pestana: Pestana, obra: String, encargado: String,
                        busqueda: String, orden: Orden) -> [OC] {
        let q = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        return ocs.filter { o in
            if o.importadoPDF && (o.obra.isEmpty || o.responsable.isEmpty) { return false }
            switch pestana {
            case .todos: break
            case .facturadas: if !o.tieneFactura { return false }
            default: if o.estado != pestana.rawValue { return false }
            }
            if !obra.isEmpty && o.obra != obra { return false }
            if !encargado.isEmpty && o.responsable != encargado { return false }
            if !q.isEmpty {
                let campos = [o.num, o.proveedor, o.responsable, o.obra, o.facturaPrincipal?.num ?? ""]
                    + o.facturas.map(\.num)
                if !campos.contains(where: { $0.lowercased().contains(q) }) { return false }
            }
            return true
        }.sorted { a, b in
            if a.urgente != b.urgente { return a.urgente }
            switch orden {
            case .reciente: return a.ts > b.ts
            case .numero: return a.numeroEntero < b.numeroEntero
            case .proveedor: return a.proveedor.localizedCompare(b.proveedor) == .orderedAscending
            case .obra: return a.obra.localizedCompare(b.obra) == .orderedAscending
            case .estado: return a.rangoEstado < b.rangoEstado
            }
        }
    }

    static func cuenta(_ ocs: [OC], _ p: Pestana) -> Int {
        switch p {
        case .todos: return ocs.count
        case .facturadas: return ocs.filter(\.tieneFactura).count
        default: return ocs.filter { $0.estado == p.rawValue }.count
        }
    }
}

enum Formato {
    private static let moneda: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    private static let formatoFechaHora: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d/M/yyyy HH:mm"
        return f
    }()

    private static let soloFecha: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_AR")
        f.dateFormat = "d/M/yyyy"
        return f
    }()

    /// `_facFmtMoneda` de la web: "$ 131.970,34".
    static func pesos(_ n: Double) -> String {
        "$ " + (moneda.string(from: NSNumber(value: n)) ?? String(n))
    }

    /// `fd(ts)` de la web.
    static func fechaHora(_ ts: Double) -> String {
        formatoFechaHora.string(from: Date(timeIntervalSince1970: ts / 1000))
    }

    /// `new Date().toLocaleDateString('es-AR')`.
    static func hoy() -> String { soloFecha.string(from: Date()) }
}


/// Ficha de proveedor (`provData/<id>`).
struct FichaProveedor: Identifiable, Hashable {
    let id: String
    let nombre: String
    let tel: String
    let mail: String
    let cuit: String
    let direccion: String

    init?(clave: String, _ v: Any) {
        guard let d = v as? [String: Any] else { return nil }
        let i = texto(d["id"])
        id = i.isEmpty ? clave : i
        nombre = texto(d["nombre"])
        tel = texto(d["tel"])
        mail = texto(d["mail"])
        cuit = texto(d["cuit"])
        direccion = texto(d["direccion"])
    }
}

/// Contacto de WhatsApp para avisos (`waContacts`).
struct ContactoWA: Hashable, Identifiable {
    var id: String { numero }
    let nombre: String
    let numero: String
    let apikey: String
    let rol: String
    var diccionario: [String: Any] { ["nombre": nombre, "numero": numero, "apikey": apikey, "rol": rol] }
}

/// Lista de precios de un proveedor (`listasPrecios/<id>`): manual (productos y precios) o archivo (PDF/imagen).
struct ListaPrecios: Identifiable, Hashable {
    struct Item: Hashable { let prod: String; let precio: String }
    let id: String
    let proveedor: String
    let tipo: String
    let fecha: String
    let ts: Double
    let items: [Item]
    let fileType: String
    let fileData: String

    init?(clave: String, _ v: Any) {
        guard let d = v as? [String: Any] else { return nil }
        let i = texto(d["id"])
        id = i.isEmpty ? clave : i
        proveedor = texto(d["proveedor"])
        tipo = texto(d["tipo"])
        fecha = texto(d["fecha"])
        ts = numero(d["ts"]) ?? 0
        items = JSONTree.lista(d["items"]).compactMap { x in
            guard let it = x as? [String: Any] else { return nil }
            return Item(prod: texto(it["prod"]), precio: texto(it["precio"]))
        }
        fileType = texto(d["fileType"])
        fileData = texto(d["fileData"])
    }

    /// `l.fecha || fd(l.ts)`
    var rotulo: String { fecha.isEmpty ? Formato.fechaHora(ts) : fecha }
}

/// Una obra de la lista `obras` (activa o archivada).
struct ObraItem: Identifiable, Hashable {
    var id: String { nombre }
    let nombre: String
    let archivada: Bool
}
