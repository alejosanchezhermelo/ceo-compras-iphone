import Foundation

/// Copia local de un nodo de Firebase, a la que se le aplican los cambios que llegan en vivo.
/// Las listas de Firebase (arrays) se guardan como diccionario "0", "1", ... para poder
/// aplicar cambios por ruta; `lista()` las devuelve ordenadas.
enum JSONTree {
    static func normalizar(_ v: Any) -> Any? {
        if v is NSNull { return nil }
        if let a = v as? [Any] {
            var d: [String: Any] = [:]
            for (i, x) in a.enumerated() { if let n = normalizar(x) { d[String(i)] = n } }
            return d.isEmpty ? nil : d
        }
        if let d = v as? [String: Any] {
            var r: [String: Any] = [:]
            for (k, x) in d { if let n = normalizar(x) { r[k] = n } }
            return r.isEmpty ? nil : r
        }
        return v
    }

    static func poner(_ raiz: Any?, _ camino: ArraySlice<String>, _ valor: Any?) -> Any? {
        guard let clave = camino.first else { return valor }
        var d = (raiz as? [String: Any]) ?? [:]
        let hijo = poner(d[clave], camino.dropFirst(), valor)
        if let hijo { d[clave] = hijo } else { d.removeValue(forKey: clave) }
        return d.isEmpty ? nil : d
    }

    /// Aplica un evento "put" (reemplaza) o "patch" (actualiza algunos hijos).
    static func aplicar(_ raiz: Any?, evento: String, ruta: String, dato: Any) -> Any? {
        let camino = ruta.split(separator: "/").map(String.init)
        if evento == "put" {
            return poner(raiz, camino[...], normalizar(dato))
        }
        guard let cambios = dato as? [String: Any] else { return raiz }
        var r = raiz
        for (k, v) in cambios {
            r = poner(r, (camino + [k])[...], normalizar(v))
        }
        return r
    }

    static func lista(_ v: Any?) -> [Any] {
        if let a = v as? [Any] { return a }
        guard let d = v as? [String: Any] else { return [] }
        return d.sorted { (Int($0.key) ?? Int.max, $0.key) < (Int($1.key) ?? Int.max, $1.key) }.map(\.value)
    }
}

// MARK: Lectores tolerantes (hay OC de formato viejo y nuevo, y campos que a veces faltan)

func texto(_ v: Any?) -> String {
    switch v {
    case let s as String: return s
    case let n as NSNumber: return n.stringValue
    default: return ""
    }
}

func numero(_ v: Any?) -> Double? {
    switch v {
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s.replacingOccurrences(of: ",", with: "."))
    default: return nil
    }
}

/// Igual que "verdadero" en JavaScript (lo que usa la web para decidir).
func verdadero(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let n as NSNumber: return n.doubleValue != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
