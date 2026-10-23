import Foundation

/// Lo que se está cargando en el formulario de nueva OC / editar OC.
struct BorradorOC {
    var num = ""
    var obra = ""
    var encargado = ""
    var proveedor = ""
    var tieneFecha = false
    var fecha = Date()
    var notas = ""
    var items: [BorradorItem] = [BorradorItem(), BorradorItem()]   // la web arranca con 2 renglones

    init(numeroSugerido: Int) {
        num = String(numeroSugerido)
    }

    init(editando o: OC) {
        num = o.num
        obra = o.obra
        encargado = o.responsable
        proveedor = o.proveedor
        if let f = Fechas.desdeTexto(o.fecha) {
            tieneFecha = true
            fecha = f
        }
        notas = o.notas
        items = o.items.map { BorradorItem(desc: $0.desc, cant: $0.cant == "—" ? "" : $0.cant, unit: $0.unit) }
        if items.isEmpty { items = [BorradorItem(), BorradorItem()] }
    }

    /// Fecha como la guarda la web (`<input type="date">`): "2026-10-23", o "" si no tiene.
    var fechaTexto: String { tieneFecha ? Fechas.aTexto(fecha) : "" }
}

struct BorradorItem: Identifiable {
    let id = UUID()
    var desc = ""
    var cant = ""
    var unit = ""
}

enum Fechas {
    private static let f: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func aTexto(_ d: Date) -> String { f.string(from: d) }
    static func desdeTexto(_ s: String) -> Date? { s.isEmpty ? nil : f.date(from: s) }
}

/// Identificadores iguales a los de la web.
@MainActor
enum IDs {
    private static let letras = Array("-0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz")
    private static var ultimoTiempo: Int64 = 0
    private static var ultimoAzar = [Int](repeating: 0, count: 12)

    /// Clave como la de `push()` de Firebase (ordenadas por fecha, 20 caracteres).
    static func push() -> String {
        var ahora = Int64(Date().timeIntervalSince1970 * 1000)
        let repetido = ahora == ultimoTiempo
        ultimoTiempo = ahora
        var tiempo = [Character](repeating: "-", count: 8)
        for i in stride(from: 7, through: 0, by: -1) {
            tiempo[i] = letras[Int(ahora % 64)]
            ahora /= 64
        }
        if !repetido {
            for i in 0..<12 { ultimoAzar[i] = Int.random(in: 0..<64) }
        } else {
            var i = 11
            while i >= 0 && ultimoAzar[i] == 63 { ultimoAzar[i] = 0; i -= 1 }
            if i >= 0 { ultimoAzar[i] += 1 }
        }
        return String(tiempo) + String(ultimoAzar.map { letras[$0] })
    }

    /// `genId()` de la web: fecha en base 36 + 4 letras al azar.
    static func gen() -> String {
        let base36 = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let ms = Int64(Date().timeIntervalSince1970 * 1000)
        return String(ms, radix: 36) + String((0..<4).map { _ in base36.randomElement()! })
    }
}

/// "ferretera san luis" → "Ferretera San Luis" (igual que la web).
func capitalizarProveedor(_ s: String) -> String {
    s.split(separator: " ", omittingEmptySubsequences: false).map { w -> String in
        guard let p = w.first else { return String(w) }
        return String(p).uppercased() + w.dropFirst().lowercased()
    }.joined(separator: " ")
}
