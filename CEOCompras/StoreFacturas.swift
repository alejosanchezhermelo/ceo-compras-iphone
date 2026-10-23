import Foundation
import PDFKit
import UIKit

/// "Cargar factura" (pestaña Facturas de la PWA): lo que se lee del QR y se guarda en una o varias OC.
extension Store {

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
