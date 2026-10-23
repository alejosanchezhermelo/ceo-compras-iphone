import Foundation
import PDFKit

/// Acciones del grupo B (pedido de Alejo 2026-10-23): proveedores, obras, encargados, numeración,
/// contactos de WhatsApp, listas de precios y OC importadas. Copiadas de la web (index.html).
extension Store {

    // MARK: Listas que la web guarda enteras (proveedores, obras, encargados, waContacts)

    /// Lee la lista con su huella, la cambia y la vuelve a guardar SOLO si nadie la tocó en el medio
    /// (si la PC la cambió, vuelve a leer y reintenta). `cambiar` devuelve nil si no hay nada que hacer.
    func editarLista(_ nodo: String, _ cambiar: ([Any]) -> [Any]?) async -> String? {
        guard puedeEditar else { return "Guardar no está habilitado." }
        do {
            for _ in 0..<4 {
                let (valor, huella) = try await Firebase.shared.leerConHuella(prefijo + nodo)
                guard let nueva = cambiar(JSONTree.lista(valor)) else { return nil }
                let guardar: Any = nueva.isEmpty ? NSNull() : nueva
                if try await Firebase.shared.escribirSiNoCambio(prefijo + nodo, guardar, huella: huella) { return nil }
            }
            return "La lista cambió varias veces seguidas. Probá de nuevo."
        } catch {
            return "No se pudo guardar. Revisá la conexión e intentá de nuevo."
        }
    }

    private static func sinRepetirSinMayusculas(_ l: [String]) -> [String] {
        var vistos = Set<String>()
        return l.filter { vistos.insert($0.lowercased()).inserted }
    }

    // MARK: Proveedores (ranking, ficha, CUIT, renombrar, sacar de la lista)

    struct FilaRanking: Identifiable {
        var id: String { nombre }
        let nombre: String
        var total = 0, entregadas = 0, parciales = 0, pendientes = 0
        var porcentaje: Int { total == 0 ? 0 : Int((Double(entregadas) / Double(total) * 100).rounded()) }
    }

    /// `renderRanking`: por proveedor, ordenado por % de entregas completas y después por cantidad.
    func ranking() -> [FilaRanking] {
        var s: [String: FilaRanking] = [:]
        for o in ordenes {
            let p = o.proveedor.isEmpty ? "Sin proveedor" : o.proveedor
            var f = s[p] ?? FilaRanking(nombre: p)
            f.total += 1
            if o.estado == "entregado" { f.entregadas += 1 } else if o.estado == "parcial" { f.parciales += 1 } else { f.pendientes += 1 }
            s[p] = f
        }
        return s.values.sorted {
            let a = $0.total == 0 ? 0 : Double($0.entregadas) / Double($0.total)
            let b = $1.total == 0 ? 0 : Double($1.entregadas) / Double($1.total)
            return a != b ? a > b : $0.total > $1.total
        }
    }

    func ficha(nombre: String) -> FichaProveedor? {
        fichasProveedores.first { $0.nombre.lowercased() == nombre.lowercased() }
    }

    /// Preguntas de `_guardarCuit`: CUIT inválido, o que ya lo tiene otro proveedor.
    func avisosCuit(paraId id: String, nombre: String, _ cuitEscrito: String) -> [String] {
        let c = Facturas.soloDigitos(cuitEscrito)
        guard !c.isEmpty else { return [] }
        var avisos: [String] = []
        if !Facturas.cuitValido(c) { avisos.append("El CUIT \(Facturas.fmtCuit(c)) no parece válido (revisá los números). ¿Lo guardo igual?") }
        if let otro = fichasProveedores.first(where: { $0.id != id && Facturas.soloDigitos($0.cuit) == c }) {
            avisos.append("Ese CUIT ya lo tiene \(otro.nombre.isEmpty ? "otro proveedor" : otro.nombre). ¿Lo guardo igual en \(nombre)? (vale si son la misma empresa)")
        }
        return avisos
    }

    /// `guardarCuitProv` (lista de proveedores sin CUIT): guarda solo los números.
    func guardarCuit(_ f: FichaProveedor, _ cuitEscrito: String) async -> String? {
        let c = Facturas.soloDigitos(cuitEscrito)
        if c.isEmpty { return "Escribí el CUIT" }
        return await ejecutar(["provData/\(f.id)/cuit": c])
    }

    /// `guardarFichaProveedor`: teléfono, mail, CUIT, dirección y nombre (si cambia, también en la lista).
    func guardarFicha(nombreOriginal: String, tel: String, mail: String, cuit: String, direccion: String, nombre: String) async -> String? {
        let datos: [String: Any] = ["tel": tel, "mail": mail, "cuit": cuit, "direccion": direccion, "nombre": nombre]
        var cambios: [String: Any] = [:]
        if let f = ficha(nombre: nombreOriginal) {
            for (k, v) in datos { cambios["provData/\(f.id)/\(k)"] = v }
            if let e = await ejecutar(cambios) { return e }
            if nombre != nombreOriginal {
                return await editarLista("proveedores") { l in
                    var lista = Store.sinRepetirSinMayusculas(l.map { texto($0) })
                    guard let i = lista.firstIndex(of: nombreOriginal) else { return nil }
                    lista[i] = nombre
                    return lista
                }
            }
            return nil
        }
        // Proveedor sin ficha todavía: se crea (getProvId de la web) con los datos cargados
        let id = "prov_" + IDs.gen()
        var nuevo = datos
        nuevo["id"] = id
        nuevo["ts"] = Store.ahoraMs()
        return await ejecutar(["provData/\(id)": nuevo])
    }

    /// `editarProveedor`: renombra en la ficha, en la lista y en TODAS las OC de ese proveedor.
    func renombrarProveedor(_ viejo: String, _ escrito: String) async -> String? {
        let nuevo = capitalizarProveedor(escrito.trimmingCharacters(in: .whitespaces))
        if nuevo.isEmpty || nuevo == viejo { return nil }
        var cambios: [String: Any] = [:]
        let f = ficha(nombre: viejo)
        if let f { cambios["provData/\(f.id)/nombre"] = nuevo }
        var cant = 0
        for o in ordenes where o.proveedor == viejo || (f != nil && o.provIdGuardado == f?.id) {
            cambios["ordenes/\(o.id)/proveedor"] = nuevo
            cant += 1
        }
        let (h, e) = evento("✏️ Proveedor \"\(viejo)\" renombrado a \"\(nuevo)\"" + (cant > 0 ? " (\(cant) OC actualizadas)" : ""), tipo: "c", ocId: nil)
        cambios[h] = e
        if let err = await ejecutar(cambios) { return err }
        return await editarLista("proveedores") { l in
            let lista = Store.sinRepetirSinMayusculas(l.map { texto($0) })
            return lista.contains(viejo) ? lista.map { $0 == viejo ? nuevo : $0 } : nil
        }
    }

    /// `delProvEl`: lo saca de la lista de sugerencias (la ficha y las OC quedan).
    func sacarProveedorDeLista(_ nombre: String) async -> String? {
        await editarLista("proveedores") { l in
            let lista = Store.sinRepetirSinMayusculas(l.map { texto($0) })
            return lista.contains(nombre) ? lista.filter { $0 != nombre } : nil
        }
    }

    // MARK: Obras

    /// Una obra de la lista `obras` como objeto (`{nombre, archivada}`), como la deja la web al editar.
    private static func obraComoObjeto(_ o: Any) -> [String: Any] {
        if let s = o as? String { return ["nombre": s, "archivada": false] }
        return o as? [String: Any] ?? [:]
    }

    /// `addObra`
    func agregarObra(_ escrito: String) async -> String? {
        let v = escrito.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return nil }
        return await editarLista("obras") { l in
            if l.contains(where: { ($0 as? String ?? texto(($0 as? [String: Any])?["nombre"])) == v }) { return nil }
            return l + [["nombre": v, "archivada": false] as [String: Any]]
        }
    }

    /// `archObra` / `unarchObra`
    func archivarObra(_ nombre: String, archivar: Bool) async -> String? {
        if let e = await editarLista("obras", { l in
            l.map { o -> Any in
                let n = o as? String ?? texto((o as? [String: Any])?["nombre"])
                if n == nombre { return ["nombre": nombre, "archivada": archivar] as [String: Any] }
                return o is String ? Store.obraComoObjeto(o) : o
            }
        }) { return e }
        let (h, ev) = evento(archivar ? "🏗 Obra \"\(nombre)\" archivada" : "🏗 Obra \"\(nombre)\" reactivada",
                             tipo: archivar ? "d" : "c", ocId: nil)
        return await ejecutar([h: ev])
    }

    /// `editarObra`: renombra en obrasData, en la lista, en las OC y en las solicitudes.
    func renombrarObra(_ viejo: String, _ escrito: String) async -> String? {
        let nuevo = escrito.trimmingCharacters(in: .whitespaces)
        if nuevo.isEmpty || nuevo == viejo { return nil }
        var cambios: [String: Any] = [:]
        var obraIdVieja: String?
        for (k, v) in arboles["obrasData"] as? [String: Any] ?? [:] {
            guard let d = v as? [String: Any], texto(d["nombre"]).lowercased() == viejo.lowercased() else { continue }
            let id = texto(d["id"]).isEmpty ? k : texto(d["id"])
            obraIdVieja = id
            cambios["obrasData/\(id)/nombre"] = nuevo
            break
        }
        var cant = 0
        for (k, v) in arboles["ordenes"] as? [String: Any] ?? [:] {
            guard let d = v as? [String: Any] else { continue }
            if texto(d["obra"]) == viejo || (obraIdVieja != nil && texto(d["obraId"]) == obraIdVieja) {
                cambios["ordenes/\(texto(d["id"]).isEmpty ? k : texto(d["id"]))/obra"] = nuevo
                cant += 1
            }
        }
        for (k, v) in arboles["solicitudes"] as? [String: Any] ?? [:] {
            guard let d = v as? [String: Any], texto(d["obra"]) == viejo else { continue }
            cambios["solicitudes/\(texto(d["id"]).isEmpty ? k : texto(d["id"]))/obra"] = nuevo
            cant += 1
        }
        if let e = await editarLista("obras", { l in
            l.map { o -> Any in
                if let s = o as? String { return s == viejo ? nuevo : s }
                guard let d = o as? [String: Any], texto(d["nombre"]) == viejo else { return o }
                return ["nombre": nuevo, "archivada": verdadero(d["archivada"])] as [String: Any]
            }
        }) { return e }
        let (h, ev) = evento("✏️ Obra \"\(viejo)\" renombrada a \"\(nuevo)\"" + (cant > 0 ? " (\(cant) registros actualizados)" : ""),
                             tipo: "c", ocId: nil)
        cambios[h] = ev
        return await ejecutar(cambios)
    }

    // MARK: Encargados

    /// `addEnc`
    func agregarEncargado(_ escrito: String) async -> String? {
        let v = escrito.trimmingCharacters(in: .whitespaces)
        if v.isEmpty { return nil }
        return await editarLista("encargados") { l in
            l.contains(where: { texto($0) == v }) ? nil : l + [v]
        }
    }

    /// `delEnc`
    func eliminarEncargado(_ nombre: String) async -> String? {
        await editarLista("encargados") { l in l.filter { texto($0) != nombre } }
    }

    // MARK: Numeración de OC

    /// `guardarNextNum`
    func guardarProximoNumero(_ escrito: String) async -> String? {
        guard let v = Int(escrito.trimmingCharacters(in: .whitespaces)), v >= 1 else { return "Escribí un número válido" }
        return await ejecutar(["config/nextOCNum": v])
    }

    // MARK: Contactos de WhatsApp

    /// `addWA`
    func agregarContacto(encargado: String, numero: String, apikey: String) async -> String? {
        let nu = numero.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
        let k = apikey.trimmingCharacters(in: .whitespaces)
        if encargado.isEmpty || nu.isEmpty || k.isEmpty { return "Completá todos los campos" }
        if contactosWA.contains(where: { $0.numero == nu }) { return "Ese número ya está agregado" }
        let c = ContactoWA(nombre: encargado == "__comp__" ? "Compras" : encargado, numero: nu, apikey: k,
                           rol: encargado == "__comp__" ? "compras" : "encargado")
        return await editarLista("waContacts") { l in
            l.contains(where: { texto(($0 as? [String: Any])?["numero"]) == nu }) ? nil : l + [c.diccionario]
        }
    }

    /// `editarWA`
    func editarContacto(_ c: ContactoWA, numero: String, apikey: String) async -> String? {
        let nu = numero.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "+", with: "")
        let k = apikey.trimmingCharacters(in: .whitespaces)
        if nu.isEmpty || k.isEmpty { return "Completá ambos campos" }
        return await editarLista("waContacts") { l in
            l.map { x -> Any in
                guard var d = x as? [String: Any], texto(d["numero"]) == c.numero else { return x }
                d["numero"] = nu
                d["apikey"] = k
                return d
            }
        }
    }

    /// `delWAEl`
    func eliminarContacto(_ c: ContactoWA) async -> String? {
        await editarLista("waContacts") { l in l.filter { texto(($0 as? [String: Any])?["numero"]) != c.numero } }
    }

    // MARK: Listas de precios

    /// Fecha como la guarda la web: la del campo dada vuelta ("23/10/2026") o la de hoy ("23/10/2026").
    private static func fechaLista(_ f: Date?) -> String {
        guard let f else { return Formato.hoy() }
        return Fechas.aTexto(f).split(separator: "-").reversed().joined(separator: "/")
    }

    /// `guardarLista` (carga manual)
    func guardarListaManual(proveedor: String, fecha: Date?, items: [(String, String)]) async -> String? {
        let prov = capitalizarProveedor(proveedor.trimmingCharacters(in: .whitespaces))
        if prov.isEmpty { return "Ingresá el nombre del proveedor" }
        let its: [[String: Any]] = items.compactMap { p, pr in
            let prod = p.trimmingCharacters(in: .whitespaces)
            if prod.isEmpty { return nil }
            let precio = pr.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            return ["prod": prod, "precio": precio.isEmpty ? "0" : precio]
        }
        if its.isEmpty { return "Agregá al menos un producto" }
        let id = IDs.push()
        return await ejecutar(["listasPrecios/\(id)": ["id": id, "proveedor": prov, "tipo": "manual", "items": its,
                                                       "ts": Store.ahoraMs(), "fecha": Store.fechaLista(fecha)]])
    }

    /// `guardarLista` (PDF o imagen, máximo 2 MB, guardado adentro de la base como la web)
    func guardarListaArchivo(proveedor: String, fecha: Date?, datos: Data, tipo: String) async -> String? {
        let prov = capitalizarProveedor(proveedor.trimmingCharacters(in: .whitespaces))
        if prov.isEmpty { return "Ingresá el nombre del proveedor" }
        if datos.count > 2 * 1024 * 1024 { return "El archivo es muy grande (máx. 2 MB)" }
        let id = IDs.push()
        let dataURL = "data:\(tipo);base64," + datos.base64EncodedString()
        return await ejecutar(["listasPrecios/\(id)": ["id": id, "proveedor": prov, "tipo": "archivo", "fileData": dataURL,
                                                       "fileType": tipo, "ts": Store.ahoraMs(), "fecha": Store.fechaLista(fecha)]])
    }

    /// `delListaEl`
    func eliminarLista(_ l: ListaPrecios) async -> String? {
        await ejecutar(["listasPrecios/\(l.id)": NSNull()])
    }

    /// `extraerDePDF` + `parsearListaPrecios`: lee los renglones "producto ... $ precio" de un PDF con texto.
    nonisolated static func extraerPrecios(de datos: Data) -> [(String, String)] {
        guard let doc = PDFDocument(data: datos), let texto = doc.string else { return [] }
        guard let re = try? NSRegularExpression(pattern: "\\$?\\s*(\\d{1,3}(?:[.,]\\d{3})*(?:[.,]\\d{1,2})?)\\s*$") else { return [] }
        var items: [(String, String)] = []
        for crudo in texto.components(separatedBy: CharacterSet.newlines) {
            let linea = crudo.trimmingCharacters(in: .whitespaces)
            if linea.count < 3 { continue }
            let ns = linea as NSString
            guard let m = re.firstMatch(in: linea, range: NSRange(location: 0, length: ns.length)) else { continue }
            let prod = ns.replacingCharacters(in: m.range, with: "").trimmingCharacters(in: .whitespaces)
            let precioStr = ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
            if let p = Double(precioStr), p > 0, prod.count > 2 { items.append((prod, String(format: "%.2f", p))) }
            if items.count >= 200 { break }
        }
        return items
    }

    // MARK: OC importadas de PDF sin asignar

    var importadasSinAsignar: [OC] {
        ordenes.filter { $0.importadoPDF && ($0.obra.isEmpty || $0.responsable.isEmpty) }.sorted { $0.ts > $1.ts }
    }

    /// `asignarOC`: obra + encargado (+ proveedor si se escribió) y la OC pasa a pendiente.
    func asignarImportada(_ o: OC, obra: String, encargado: String, proveedor: String) async -> String? {
        if obra.isEmpty || encargado.isEmpty { return "Completá obra y encargado" }
        var c: [String: Any] = ["ordenes/\(o.id)/obra": obra, "ordenes/\(o.id)/responsable": encargado,
                                "ordenes/\(o.id)/estado": "pendiente", "ordenes/\(o.id)/ts": Store.ahoraMs()]
        let p = proveedor.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty { c["ordenes/\(o.id)/proveedor"] = p }
        return await ejecutar(c)
    }
}
