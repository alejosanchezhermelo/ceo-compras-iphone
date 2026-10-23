import Foundation

/// Acciones del grupo A (pedido de Alejo 2026-10-23): mismas que la web, mismos textos de historial.
/// Cada una escribe TODO junto (o nada) con un solo PATCH. En modo prueba van a `pruebas-iphone/`.
extension Store {

    // MARK: Ayudas

    static func ahoraMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    /// `logE(tipo, texto, ocId)` de la web: devuelve la ruta y el valor del evento para sumarlo a un PATCH.
    func evento(_ texto: String, tipo: String, ocId: String?, ts: Int64 = Store.ahoraMs()) -> (String, [String: Any]) {
        let id = IDs.push()
        var e: [String: Any] = ["id": id, "tipo": tipo, "texto": texto, "ts": ts]
        if let ocId { e["ocId"] = ocId }
        return ("historial/\(id)", e)
    }

    /// Escribe varios cambios juntos. Devuelve el error para mostrar, o nil si salió bien.
    func ejecutar(_ cambios: [String: Any]) async -> String? {
        guard puedeEditar else { return "Guardar no está habilitado." }
        do {
            try await Firebase.shared.actualizarJuntos(base: base, cambios)
            return nil
        } catch {
            return "No se pudo guardar. Revisá la conexión e intentá de nuevo."
        }
    }

    /// `notifyC` de la web: aviso por WhatsApp a Compras (en modo prueba no se manda).
    func avisarCompras(_ msg: String) async {
        if modoPrueba { return }
        guard let c = waContacts.first(where: { texto($0["rol"]) == "compras" }),
              !texto(c["numero"]).isEmpty, !texto(c["apikey"]).isEmpty else { return }
        await Firebase.shared.avisarWhatsApp(numero: texto(c["numero"]), apikey: texto(c["apikey"]), texto: msg)
    }

    /// Ficha del proveedor de una OC (`_provDeOC`): por id, o por nombre en OC de formato viejo.
    func fichaProveedor(_ o: OC) -> (id: String, nombre: String, cuit: String)? {
        let pd = arboles["provData"] as? [String: Any] ?? [:]
        func ficha(_ clave: String, _ v: Any?) -> (String, String, String)? {
            guard let d = v as? [String: Any] else { return nil }
            let id = texto(d["id"])
            return (id.isEmpty ? clave : id, texto(d["nombre"]), texto(d["cuit"]))
        }
        if let pid = o.provIdGuardado, let f = ficha(pid, pd[pid]) { return f }
        let n = o.proveedor.trimmingCharacters(in: .whitespaces).lowercased()
        if n.isEmpty { return nil }
        for (k, v) in pd {
            if let f = ficha(k, v), f.1.trimmingCharacters(in: .whitespaces).lowercased() == n { return f }
        }
        return nil
    }

    // MARK: Urgente / notas / eliminar

    /// `toggleUrgK`
    func cambiarUrgente(_ o: OC) async -> String? {
        let nuevo = !o.urgente
        let (h, e) = evento(nuevo ? "🔴 OC marcada como urgente" : "✅ OC urgente desactivada", tipo: "c", ocId: o.id)
        if let err = await ejecutar(["ordenes/\(o.id)/urgente": nuevo, h: e]) { return err }
        if nuevo {
            await avisarCompras("🔴 URGENTE: OC \(o.num.isEmpty ? o.id : o.num) - \(o.proveedor.isEmpty ? "sin proveedor" : o.proveedor)"
                                + (o.obra.isEmpty ? "" : " (\(o.obra))"))
        }
        return nil
    }

    /// `addNI`
    func agregarNotaInterna(_ o: OC, _ txt: String) async -> String? {
        let t = txt.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        var lista: [[String: Any]] = o.notasInternas.map { n in
            var d: [String: Any] = ["txt": n.txt]
            if let ts = n.ts { d["ts"] = Int64(ts) }
            return d
        }
        lista.append(["txt": t, "ts": Store.ahoraMs()])
        let (h, e) = evento("📝 Nota interna agregada a OC \(o.num.isEmpty ? o.id : o.num)", tipo: "c", ocId: o.id)
        return await ejecutar(["ordenes/\(o.id)/notasInternas": lista, h: e])
    }

    /// `delOC` (el evento queda sin ocId, igual que en la web)
    func eliminarOC(_ o: OC) async -> String? {
        let (h, e) = evento("🗑 OC \(o.num.isEmpty ? o.id : o.num) eliminada por Compras", tipo: "d", ocId: nil)
        return await ejecutar([h: e, "ordenes/\(o.id)": NSNull()])
    }

    // MARK: PDF (generarPDF de la web)

    /// Al tocar "Generar OC": si la OC no tenía número de PDF se le asigna el próximo, y queda anotado.
    func registrarPDF(_ o: OC) async -> String? {
        var cambios: [String: Any] = [:]
        var num = o.numOCPDF ?? 0
        if o.numOCPDF == nil {
            num = nextOCNum
            cambios["ordenes/\(o.id)/numOCPDF"] = num
        }
        let (h, e) = evento("OC PDF No \(num) generada - \(o.proveedor.isEmpty ? "sin proveedor" : o.proveedor)", tipo: "c", ocId: o.id)
        cambios[h] = e
        if let err = await ejecutar(cambios) { return err }
        if o.numOCPDF == nil { try? await subirProximoNumero(String(num), prefijo) }
        return nil
    }

    // MARK: Facturas (carga rápida desde la ficha)

    /// Revisa N° y monto (`guardarFacturaRapida` / `sumarFacturaOC`). Devuelve el error o nil.
    func validarFactura(_ o: OC, num: String, monto: String, sumando: Bool) -> String? {
        let n = num.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return "Escribí el número de factura" }
        guard let imp = Facturas.importe(monto), imp > 0 else { return "Escribí el monto (ej: 131.970,34)" }
        _ = imp
        if sumando && o.facturas.contains(where: { Facturas.mismoNum($0.num, n) }) {
            return "Esa factura ya está cargada en esta OC"
        }
        return nil
    }

    /// Preguntas antes de guardar el CUIT nuevo (`_guardarCuit`): CUIT inválido o repetido en otro proveedor.
    func avisosCuit(_ o: OC, _ cuitEscrito: String) -> [String] {
        let c = Facturas.soloDigitos(cuitEscrito)
        guard !c.isEmpty, let pv = fichaProveedor(o), pv.cuit.isEmpty else { return [] }
        var avisos: [String] = []
        if !Facturas.cuitValido(c) {
            avisos.append("El CUIT \(Facturas.fmtCuit(c)) no parece válido (revisá los números). ¿Lo guardo igual?")
        }
        let pd = arboles["provData"] as? [String: Any] ?? [:]
        for (k, v) in pd {
            guard let d = v as? [String: Any] else { continue }
            let id = texto(d["id"]).isEmpty ? k : texto(d["id"])
            if id != pv.id && Facturas.soloDigitos(texto(d["cuit"])) == c {
                let otro = texto(d["nombre"]).isEmpty ? "otro proveedor" : texto(d["nombre"])
                avisos.append("Ese CUIT ya lo tiene \(otro). ¿Lo guardo igual en \(pv.nombre)? (vale si son la misma empresa)")
                break
            }
        }
        return avisos
    }

    /// Pregunta si esa factura ya está en otra OC (vale si una factura cubre varias OC).
    func avisoFacturaRepetida(_ o: OC, num: String, monto: String, cuitEscrito: String) -> String? {
        let imp = Facturas.importe(monto)
        var cu = fichaProveedor(o)?.cuit ?? ""
        if cu.isEmpty { cu = Facturas.soloDigitos(cuitEscrito) }
        let ya = Facturas.yaCargada(num.trimmingCharacters(in: .whitespaces), cuit: cu, total: imp, en: ordenes)
            .filter { $0.id != o.id }
        guard let otra = ya.first else { return nil }
        return "Esa factura ya está cargada en la OC \(otra.num). ¿La cargo igual acá? (vale si una factura cubre varias OC)"
    }

    /// Primera factura de la OC (`guardarFacturaRapida` + `_doGuardarFQ`). Si se escribió CUIT, va al proveedor.
    func guardarFactura(_ o: OC, num: String, monto: String, cuitEscrito: String) async -> String? {
        guard let imp = Facturas.importe(monto) else { return "Escribí el monto (ej: 131.970,34)" }
        let n = num.trimmingCharacters(in: .whitespaces)
        var cambios: [String: Any] = [:]
        var cu = ""
        if let pv = fichaProveedor(o) {
            cu = pv.cuit
            let nuevo = Facturas.soloDigitos(cuitEscrito)
            if cu.isEmpty && !nuevo.isEmpty {
                cambios["provData/\(pv.id)/cuit"] = nuevo
                cu = nuevo
            }
        }
        let ahora = Store.ahoraMs()
        cambios["ordenes/\(o.id)/factura"] = ["num": n, "importe": imp, "cuit": cu, "total": imp, "ts": ahora]
        let (h, e) = evento("🧾 Factura \(n) (\(Formato.pesos(imp))) cargada en OC \(o.num)", tipo: "c", ocId: o.id, ts: ahora)
        cambios[h] = e
        return await ejecutar(cambios)
    }

    /// Factura que llegó después sobre la misma OC (`sumarFacturaOC` + `_doSumarFQ`).
    func sumarFactura(_ o: OC, num: String, monto: String) async -> String? {
        guard let imp = Facturas.importe(monto) else { return "Escribí el monto (ej: 131.970,34)" }
        let n = num.trimmingCharacters(in: .whitespaces)
        var cu = ""
        if let pid = o.provIdGuardado,
           let d = (arboles["provData"] as? [String: Any])?[pid] as? [String: Any] { cu = texto(d["cuit"]) }
        let ahora = Store.ahoraMs()
        let lista = o.facturas + [FacturaOC(num: n, importe: imp, cuit: cu, total: imp, ts: Double(ahora))]
        let d = Facturas.datos(lista, ahora: ahora)
        var cambios: [String: Any] = [:]
        for (k, v) in d { cambios["ordenes/\(o.id)/\(k)"] = v }
        let totalNuevo = ((d["factura"] as? [String: Any])?["importe"] as? Double) ?? imp
        let (h, e) = evento("🧾 Factura \(n) (\(Formato.pesos(imp))) sumada a OC \(o.num) — total \(Formato.pesos(totalNuevo))",
                            tipo: "c", ocId: o.id, ts: ahora)
        cambios[h] = e
        return await ejecutar(cambios)
    }

    /// `quitarFactura`: saca todas las facturas de la OC.
    func quitarFacturas(_ o: OC) async -> String? {
        let (h, e) = evento("🧾 Factura quitada de OC \(o.num)", tipo: "c", ocId: o.id)
        return await ejecutar(["ordenes/\(o.id)/factura": NSNull(), "ordenes/\(o.id)/facturas": NSNull(), h: e])
    }

    /// `quitarFacturaN`: saca una sola (si era la única, es como quitarlas todas).
    func quitarFactura(_ o: OC, indice i: Int) async -> String? {
        var lista = o.facturas
        guard lista.count >= 2 else { return await quitarFacturas(o) }
        guard lista.indices.contains(i) else { return nil }
        let f = lista.remove(at: i)
        var cambios: [String: Any] = [:]
        for (k, v) in Facturas.datos(lista, ahora: Store.ahoraMs()) { cambios["ordenes/\(o.id)/\(k)"] = v }
        let (h, e) = evento("🧾 Factura \(f.num) sacada de OC \(o.num)", tipo: "c", ocId: o.id)
        cambios[h] = e
        return await ejecutar(cambios)
    }

    // MARK: Solicitudes

    /// `saveSolComment`
    func comentarSolicitud(_ s: Solicitud, _ txt: String) async -> String? {
        let t = txt.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        return await ejecutar(["solicitudes/\(s.id)/comentarioCompras": t])
    }

    /// `archSol`
    func archivarSolicitud(_ s: Solicitud) async -> String? {
        let (h, e) = evento("Solicitud archivada por Compras", tipo: "d", ocId: nil)
        return await ejecutar(["solicitudes/\(s.id)/estado": "archivada", h: e])
    }
}
