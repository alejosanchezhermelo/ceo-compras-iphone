import Foundation

/// Reglas de facturas copiadas de la web (index.html). Si cambian allá, cambiarlas acá.
enum Facturas {
    /// `_facParseImporte`: "131.970,34" → 131970.34 ; "1.234" → 1234 ; "12.5" → 12.5
    static func importe(_ str: String) -> Double? {
        var s = String(str.trimmingCharacters(in: .whitespaces).filter { "0123456789.,-".contains($0) })
        if s.isEmpty { return nil }
        if s.contains(",") {
            s = s.replacingOccurrences(of: ".", with: "")
            if let r = s.range(of: ",") { s.replaceSubrange(r, with: ".") }
        } else {
            let partes = s.split(separator: ".", omittingEmptySubsequences: false)
            if partes.count > 2 || (partes.count == 2 && partes[1].count == 3) {
                s = s.replacingOccurrences(of: ".", with: "")
            }
        }
        // parseFloat: toma lo que pueda del principio
        var prefijo = ""
        for c in s {
            let prueba = prefijo + String(c)
            if Double(prueba) != nil || prueba == "-" || prueba == "-." || prueba == "." { prefijo = prueba } else { break }
        }
        return Double(prefijo)
    }

    private static func numeros(_ s: String) -> (Int, Int, String)? {
        let partes = s.split(separator: "-", omittingEmptySubsequences: false)
        guard partes.count == 2, !partes[0].isEmpty, !partes[1].isEmpty,
              partes[0].allSatisfy({ $0.isASCII && $0.isNumber }), partes[1].allSatisfy({ $0.isASCII && $0.isNumber }),
              let a = Int(partes[0]), let b = Int(partes[1].prefix(18)) else { return nil }
        return (a, b, String(partes[1]))
    }

    /// `_facMismoNum`: 3-12398 = 0003-00012398
    static func mismoNum(_ a: String, _ b: String) -> Bool {
        let x = a.trimmingCharacters(in: .whitespaces).uppercased()
        let y = b.trimmingCharacters(in: .whitespaces).uppercased()
        if let m = numeros(x), let n = numeros(y) { return m.0 == n.0 && m.1 == n.1 }
        return x == y
    }

    /// `_facSufijo`: lo que va después de la "/" en el Excel (0003-00012345 + 0003-00012398 → 98).
    static func sufijo(_ p0: String, _ n0: String) -> String {
        let p = p0.trimmingCharacters(in: .whitespaces), n = n0.trimmingCharacters(in: .whitespaces)
        if let mp = numeros(p), let mn = numeros(n) {
            if mp.0 != mn.0 { return n }
            let a = Array(mp.2)
            var bS = String(mn.2.drop { $0 == "0" })
            if bS.isEmpty { bS = "0" }
            if bS.count > a.count { return n }
            bS = String(repeating: "0", count: a.count - bS.count) + bS
            let b = Array(bS)
            var k = 0
            while k < a.count && a[k] == b[k] { k += 1 }
            let resto = String(b[k...])
            return resto.isEmpty ? n : resto
        }
        let pa = Array(p), na = Array(n)
        var j = 0
        while j < pa.count && j < na.count && pa[j] == na[j] { j += 1 }
        return (j > 0 && j < na.count) ? String(na[j...]) : n
    }

    /// `_facNumCombinado`
    static func numCombinado(_ l: [FacturaOC]) -> String {
        let p = (l.first?.num ?? "").trimmingCharacters(in: .whitespaces)
        return ([p] + l.dropFirst().map { sufijo(p, $0.num) }).joined(separator: "/")
    }

    /// `_facDatos`: lo que se guarda en la OC a partir de la lista de facturas (NSNull = borrar).
    static func datos(_ l: [FacturaOC], ahora: Int64) -> [String: Any] {
        if l.isEmpty { return ["factura": NSNull(), "facturas": NSNull()] }
        if l.count == 1 { return ["factura": l[0].diccionario, "facturas": NSNull()] }
        let s = (l.reduce(0) { $0 + ($1.importe ?? 0) } * 100).rounded() / 100
        let resumen: [String: Any] = ["num": numCombinado(l), "importe": s, "cuit": l[0].cuit, "total": s, "ts": ahora]
        return ["factura": resumen, "facturas": l.map(\.diccionario)]
    }

    static func soloDigitos(_ s: String) -> String { s.filter { $0.isASCII && $0.isNumber } }

    /// `_facCuitValido` (dígito verificador)
    static func cuitValido(_ cuit: String) -> Bool {
        let c = soloDigitos(cuit).compactMap { Int(String($0)) }
        guard c.count == 11 else { return false }
        let w = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]
        let s = (0..<10).reduce(0) { $0 + c[$1] * w[$1] }
        var v = 11 - (s % 11)
        if v == 11 { v = 0 } else if v == 10 { v = 9 }
        return v == c[10]
    }

    /// `_facFmtCuit`: 30707329927 → 30-70732992-7
    static func fmtCuit(_ cuit: String) -> String {
        let c = Array(soloDigitos(cuit))
        return c.count == 11 ? String(c[0..<2]) + "-" + String(c[2..<10]) + "-" + String(c[10]) : cuit
    }

    /// `_facFacturaYaCargada`: OC que ya tienen esa factura (por N° y CUIT, o por total si falta el CUIT).
    static func yaCargada(_ num: String, cuit: String, total: Double?, en ordenes: [OC]) -> [OC] {
        let c = soloDigitos(cuit)
        return ordenes.filter { o in
            o.facturas.contains { f in
                if !mismoNum(f.num, num) { return false }
                let fc = soloDigitos(f.cuit)
                if !c.isEmpty && !fc.isEmpty { return c == fc }
                let ft = f.total ?? 0
                if let total, total != 0, ft != 0 { return abs(ft - total) < 0.05 }
                return true
            }
        }
    }
}
