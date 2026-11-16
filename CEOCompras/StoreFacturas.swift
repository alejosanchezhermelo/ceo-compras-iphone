import Foundation
import PDFKit
import UIKit

/// "Cargar factura" (pestaña Facturas de la PWA): lo que se lee del QR y se guarda en una o varias OC.
extension Store {

    // MARK: PDFs que llegan para cargar (v0.24)

    /// Pone un PDF en la cola de la pestaña Facturas. Devuelve false si lo que llegó no es un PDF.
    @discardableResult
    func encolarPDF(_ datos: Data, nombre: String) -> Bool {
        // Todo PDF arranca con "%PDF" (a veces después de unos pocos bytes de relleno)
        guard datos.prefix(1024).range(of: Data("%PDF".utf8)) != nil else { return false }
        pdfsEntrantes.append(PDFEntrante(nombre: nombre, datos: datos))
        return true
    }

    /// Un archivo que llegó desde otra app ("Compartir" → "Copiar a CEO Compras"). iOS lo deja como copia en la carpeta
    /// Inbox de la app: se lee, se borra la copia y el PDF queda en la cola. Lo que no sea un PDF se ignora.
    func recibirArchivo(_ url: URL) {
        guard url.isFileURL else { return }
        let acceso = url.startAccessingSecurityScopedResource()
        defer { if acceso { url.stopAccessingSecurityScopedResource() } }
        let datos = try? Data(contentsOf: url)
        // Solo se borra la copia que dejó iOS en Inbox; nunca un archivo original.
        if url.path.contains("/Inbox/") { try? FileManager.default.removeItem(at: url) }
        guard let datos else { return }
        if encolarPDF(datos, nombre: url.deletingPathExtension().lastPathComponent) { pdfsRecibidos += 1 }
    }

    // MARK: La factura nombra una OC (v0.24)

    /// N° de OC que existen (el N° y el N° de PDF), sin ceros adelante: sirve para validar lo que dice una factura.
    func numerosDeOC() -> Set<String> {
        var s = Set<String>()
        for o in ordenes {
            if let n = Int(o.num.trimmingCharacters(in: .whitespaces)) { s.insert(String(n)) }
            if let p = o.numOCPDF { s.insert(String(p)) }
        }
        return s
    }

    /// De los números que dice la factura, las OC que existen (mismo N° O mismo N° de PDF), en el orden en que la
    /// factura las nombra. Si un número coincide con 0 o con MÁS de una OC es dudoso y no se devuelve.
    func ocsDeNumeros(_ numeros: [String]) -> [OC] {
        var salida: [OC] = []
        for n in numeros {
            guard let v = Int(n) else { continue }
            let candidatas = ordenes.filter { Int($0.num.trimmingCharacters(in: .whitespaces)) == v || $0.numOCPDF == v }
            if candidatas.count == 1, let o = candidatas.first, !salida.contains(where: { $0.id == o.id }) {
                salida.append(o)
            }
        }
        return salida
    }

    /// La OC es del proveedor por su id o por el nombre (lo mismo que mira `ocsParaFactura`).
    func esDeProveedor(_ o: OC, _ p: FichaProveedor) -> Bool {
        o.provIdGuardado == p.id || (!o.proveedor.isEmpty && o.proveedor.lowercased() == p.nombre.lowercased())
    }

    /// `_facBuscarProveedor`: proveedor del padrón con ese CUIT.
    func proveedorPorCuit(_ cuit: String) -> FichaProveedor? {
        let c = Facturas.soloDigitos(cuit)
        if c.isEmpty { return nil }
        return fichasProveedores.first { !$0.cuit.isEmpty && Facturas.soloDigitos($0.cuit) == c }
    }

    /// `_facOCsCandidatas`: OC sin factura; las del proveedor, o las que coinciden con la búsqueda.
    func ocsParaFactura(proveedor: FichaProveedor?, busqueda: String, tildadas: Set<String>) -> [OC] {
        let sinFactura = ordenes.filter { !$0.tieneFactura }
        let q = busqueda.trimmingCharacters(in: .whitespaces).lowercased()
        var lista: [OC]
        if !q.isEmpty {
            lista = sinFactura.filter {
                $0.num.lowercased().contains(q) || $0.proveedor.lowercased().contains(q) || $0.obra.lowercased().contains(q)
            }
        } else if let p = proveedor {
            lista = sinFactura.filter {
                $0.provIdGuardado == p.id || (!$0.proveedor.isEmpty && $0.proveedor.lowercased() == p.nombre.lowercased())
            }
        } else {
            lista = sinFactura
        }
        // las tildadas siempre quedan a la vista
        let ids = Set(lista.map(\.id))
        lista += ordenes.filter { tildadas.contains($0.id) && !ids.contains($0.id) }
        return lista.sorted { $0.numeroEntero > $1.numeroEntero }
    }

    /// `_facAplicarProv`: le pone a un proveedor del padrón el CUIT que vino en la factura.
    func vincularCuit(_ f: FichaProveedor, cuit: String) async -> String? {
        await ejecutar(["provData/\(f.id)/cuit": cuit])
    }

    /// `_facCrearProvAuto`: proveedor nuevo (a la lista y con su ficha) con el CUIT de la factura.
    func crearProveedor(_ escrito: String, cuit: String) async -> String? {
        let nombre = capitalizarProveedor(escrito.trimmingCharacters(in: .whitespaces))
        if nombre.isEmpty { return "Escribí el nombre del proveedor" }
        if let e = await editarLista("proveedores", { l in
            let lista = l.map { texto($0) }
            return lista.contains(nombre) ? nil : lista + [nombre]
        }) { return e }
        if let f = fichasProveedores.first(where: { $0.nombre.lowercased() == nombre.lowercased() }) {
            return await vincularCuit(f, cuit: cuit)
        }
        let id = "prov_" + IDs.gen()
        return await ejecutar(["provData/\(id)": ["id": id, "nombre": nombre, "tel": "", "mail": "", "cuit": cuit,
                                                  "direccion": "", "ts": Store.ahoraMs()]])
    }

    /// Igual que `guardarFacturaQR`, pero ANTES mira en la BASE (no en la copia en memoria, que puede venir atrasada)
    /// si alguna OC destino ya tiene factura: si es así NO escribe nada y avisa. Así nunca se pisa una factura anterior.
    func guardarFacturaSinPisar(num: String, total: Double, cuit: String, importes: [String: Double]) async -> String? {
        for id in importes.keys {
            guard let o = ordenes.first(where: { $0.id == id }) else {
                return "No se encontró una de las OC. Revisá y probá de nuevo."
            }
            let previas: [FacturaOC]
            do { previas = try await facturasEnLaBase(o) } catch {
                return "No se pudo revisar la OC. Revisá la conexión e intentá de nuevo."
            }
            if !previas.isEmpty {
                return "La OC \(o.num) ya tiene la factura \(Facturas.numCombinado(previas)): usá «Sumar esta factura»."
            }
        }
        return await guardarFacturaQR(num: num, total: total, cuit: cuit, importes: importes)
    }

    /// `_facGuardar`: a cada OC tildada le queda `factura = {num, importe, cuit, total, ts}`.
    /// (La web no anota esto en el historial; el iPhone sí, para que se vea en Actividad.)
    func guardarFacturaQR(num: String, total: Double, cuit: String, importes: [String: Double]) async -> String? {
        let ahora = Store.ahoraMs()
        var cambios: [String: Any] = [:]
        for (id, imp) in importes {
            cambios["ordenes/\(id)/factura"] = ["num": num, "importe": imp, "cuit": cuit, "total": total, "ts": ahora]
            let numOC = ordenes.first { $0.id == id }?.num ?? ""
            let (h, e) = evento("🧾 Factura \(num) (\(Formato.pesos(imp))) cargada en OC \(numOC)", tipo: "c", ocId: id, ts: ahora)
            cambios[h] = e
        }
        return await ejecutar(cambios)
    }
}

extension PDFOC {
    /// "OC + factura" en un solo PDF (`_facBloque` de la web): cada OC en su hoja y la factura al final
    /// (como imagen, igual que la web, porque las facturas de AFIP vienen protegidas).
    static func combinado(ocs: [OC], factura: Data, nombre: String) throws -> URL {
        let render = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 210 * mm, height: 297 * mm))
        let doc = PDFDocumentLector.abrir(factura)
        let data = render.pdfData { ctx in
            for o in ocs {
                ctx.beginPage()
                dibujar(Datos(paraCombo: o), ctx)
            }
            guard let doc else { return }
            for i in 0..<doc.pageCount {
                guard let pag = doc.page(at: i) else { continue }
                let caja = pag.bounds(for: .mediaBox)
                let img = pag.thumbnail(of: CGSize(width: caja.width * 2, height: caja.height * 2), for: .mediaBox)
                ctx.beginPage(withBounds: CGRect(origin: .zero, size: caja.size), pageInfo: [:])
                img.draw(in: CGRect(origin: .zero, size: caja.size))
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(nombre + ".pdf")
        try data.write(to: url, options: .atomic)
        return url
    }
}


enum PDFDocumentLector {
    static func abrir(_ d: Data) -> PDFDocument? {
        guard let doc = PDFDocument(data: d) else { return nil }
        if doc.isLocked { doc.unlock(withPassword: "") }
        return doc
    }
}
