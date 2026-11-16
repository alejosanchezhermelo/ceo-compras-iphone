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

    // MARK: N° de OC que nombra la factura (v0.24)

    /// Rótulo ("OC", "O.C.", "O. C.", "O/C", "ORDEN", "ORDEN DE COMPRA", "ORD. COMPRA"...) + separadores ("Nº", "NRO",
    /// "NUM", "NÚMERO"...) + número de 3 a 5 cifras (con ceros de relleno opcionales) + otros números pegados con "/", ",",
    /// "Y", "&" o "-". El texto ya viene en mayúsculas y con los espacios colapsados. `(?![A-Z])` después del rótulo evita
    /// BLOC / OCTUBRE / ORDENES; `(?!\d)` evita números largos (CUIT, CAE); `(?!\s*-\s*\d{6,8})` evita que un
    /// "punto de venta - comprobante" (0001-00001580) se lea como OC. En el patrón, U+00BA / U+00B0 son el "º" y el "°" de
    /// "Nº 1234" / "N° 1234" y U+00DA es la "Ú" de "NÚMERO".
    /// Límite conocido: "ORDEN 100 UNIDADES" o "OC 1580, 1200 KG" también dan número; por eso nada se tilda sin que el
    /// número sea de una OC que existe, del mismo proveedor y sin factura, y siempre con cartel de confirmación.
    private static let patronOC = "(?:^|[^A-Z0-9])(?:ORDEN (?:DE )?COMPRAS?|ORD\\.? (?:DE )?COMPRA|ORDEN|O\\. ?C\\.?|O/C|OC)(?![A-Z])(?:[ :.\\-#=]|N[\\u00BA\\u00B0O]\\.?|NRO\\.?|N[U\\u00DA]M(?:ERO)?\\.?)*?0*(\\d{3,5})(?!\\d)(?!\\s*-\\s*\\d{6,8})((?:\\s*(?:[/,Y\\&\\-])\\s*0*\\d{3,5}(?!\\d)(?!\\s*-\\s*\\d{6,8}))*)"

    /// Números de OC que dice la factura en su texto ("OC 1580", "Orden de compra: Nº 1234", "O/C 1580/1581"...),
    /// sin ceros adelante y sin repetir, en el orden en que aparecen. NO mira si la OC existe: eso lo decide quien llama.
    /// (Misma lógica que la detección de la web; es una función pura para poder probarla.)
    static func ocsNombradas(_ texto: String) -> [String] {
        let t = texto.uppercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard let re = try? NSRegularExpression(pattern: patronOC) else { return [] }
        let ns = t as NSString
        var salida: [String] = []
        func agregar(_ cifras: String) {
            guard let n = Int(cifras), n >= 100 else { return }   // "01580" -> 1580; menos de 100 no es una OC
            let s = String(n)
            if !salida.contains(s) { salida.append(s) }
        }
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            agregar(ns.substring(with: m.range(at: 1)))
            if m.range(at: 2).location != NSNotFound {
                let resto = ns.substring(with: m.range(at: 2))
                for parte in resto.components(separatedBy: CharacterSet.decimalDigits.inverted) where !parte.isEmpty {
                    agregar(parte)
                }
            }
        }
        return salida
    }

    // MARK: Mensaje para administración (v0.24)

    /// Una OC de la factura, con lo que hace falta para armar el mensaje.
    struct OCParaMensaje {
        let num: String
        let obra: String
        let importe: Double?   // lo que le toca a esa OC; nil si no se cargó
    }

    /// Texto plano para pegar en WhatsApp: administración solo necesita saber a qué OBRA imputar la factura.
    /// Con OC de varias obras dice "Obra: VARIAS" y una línea por obra (sin el importe si falta el de alguna OC).
    static func mensajeAdmin(factura: String, total: Double, proveedor: String, cuit: String, ocs: [OCParaMensaje]) -> String {
        // Las OC agrupadas por obra (sin mirar mayúsculas), en el orden en que vienen
        var grupos: [(obra: String, ocs: [OCParaMensaje])] = []
        for o in ocs {
            let obra = o.obra.trimmingCharacters(in: .whitespaces)
            if let i = grupos.firstIndex(where: { $0.obra.lowercased() == obra.lowercased() }) {
                grupos[i].ocs.append(o)
            } else {
                grupos.append((obra: obra, ocs: [o]))
            }
        }
        var lineas = ["FACTURA PARA IMPUTAR"]
        if grupos.count > 1 {
            lineas.append("Obra: VARIAS")
            for g in grupos {
                let nombre = g.obra.isEmpty ? "sin obra" : g.obra
                var l = "• " + nombre + ": OC " + g.ocs.map { $0.num }.joined(separator: ", ")
                let importes = g.ocs.compactMap { $0.importe }
                if importes.count == g.ocs.count { l += " — " + Formato.pesos(importes.reduce(0, +)) }
                lineas.append(l)
            }
        } else {
            let obra = grupos.first?.obra ?? ""
            lineas.append("Obra: " + (obra.isEmpty ? "SIN OBRA" : obra.uppercased()))
        }
        let nombreProv = proveedor.trimmingCharacters(in: .whitespaces)
        let c = soloDigitos(cuit)
        var prov = "Proveedor: " + (nombreProv.isEmpty ? "sin especificar" : nombreProv)
        if c.count == 11 { prov += " (CUIT " + fmtCuit(c) + ")" }
        lineas.append(prov)
        lineas.append("Factura N° " + factura + " — " + Formato.pesos(total))
        lineas.append("OC: " + ocs.map { $0.num }.joined(separator: ", "))
        return lineas.joined(separator: "\n")
    }
}
