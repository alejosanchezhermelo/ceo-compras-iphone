import SwiftUI
import Vision
import PDFKit
import VisionKit

/// Lectura del QR de AFIP: mismo intérprete que la web (`_facParsearQR`), con el lector de QR del iPhone.
enum LectorQR {
    /// CUIT de CEO (receptor): nunca es el proveedor (`FAC_CEO_CUIT`).
    static let cuitCEO = "30707329927"

    struct DatosQR {
        let num: String        // 0003-00012345
        let total: Double
        let cuitQR: String
        let receptor: String
    }

    /// `_facParsearQR`: tolera QR con/sin llaves, con/sin base64, base64url, espacios, %-encoding, padding faltante.
    static func parsear(_ contenido: String) -> DatosQR? {
        guard let r = contenido.range(of: "p=") else { return nil }
        var p = String(contenido[r.upperBound...])
        if let amp = p.firstIndex(of: "&") { p = String(p[..<amp]) }
        if p.isEmpty { return nil }

        func json(_ s0: String) -> [String: Any]? {
            var s = s0.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.isEmpty { return nil }
            if !s.hasPrefix("{") { s = "{" + s + "}" }
            guard let d = s.data(using: .utf8),
                  let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
            return (j["nroCmp"] != nil || j["importe"] != nil) ? j : nil
        }
        var j: [String: Any]?
        var candidatos = [p]
        if let pd = p.removingPercentEncoding, pd != p { candidatos.append(pd) }
        for c in candidatos where j == nil {
            var b = String(c.filter { !$0.isWhitespace })
                .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while b.count % 4 != 0 { b += "=" }
            guard let data = Data(base64Encoded: b) else { continue }
            let txt = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
            j = json(txt)
        }
        if j == nil { j = json(p.removingPercentEncoding ?? p) }
        guard let d = j else { return nil }
        return DatosQR(num: formatoNumero(texto(d["ptoVta"]), texto(d["nroCmp"])),
                       total: numero(d["importe"]) ?? 0,
                       cuitQR: Facturas.soloDigitos(texto(d["cuit"])),
                       receptor: Facturas.soloDigitos(texto(d["nroDocRec"])))
    }

    /// `_facFmtNum`: 3 y 12345 → 0003-00012345
    static func formatoNumero(_ pv: String, _ cmp: String) -> String {
        let a = Int(Facturas.soloDigitos(pv)) ?? 0, b = Int(Facturas.soloDigitos(cmp)) ?? 0
        return String(format: "%04d-%08d", a, b)
    }

    /// `_facEsQRAfip`: es el QR de AFIP aunque venga inválido de origen.
    static func esQRAfip(_ texto: String) -> Bool { texto.lowercased().contains("afip.gob.ar/fe/qr") }

    /// `_facCuitsEnTexto` + `_facDetectarCuitProveedor`
    static func cuitProveedor(texto: String, qrCuit: String, receptor: String) -> String {
        let q = Facturas.soloDigitos(qrCuit), rec = Facturas.soloDigitos(receptor)
        if Facturas.cuitValido(q) && q != cuitCEO && q != rec { return q }
        guard let re = try? NSRegularExpression(pattern: "\\b(\\d{2})[-.\\s]?(\\d{8})[-.\\s]?(\\d)\\b") else { return "" }
        let ns = texto as NSString
        for m in re.matches(in: texto, range: NSRange(location: 0, length: ns.length)) {
            let c = ns.substring(with: m.range(at: 1)) + ns.substring(with: m.range(at: 2)) + ns.substring(with: m.range(at: 3))
            if Facturas.cuitValido(c) && c != cuitCEO && c != rec { return c }
        }
        return ""
    }

    /// `_facNumDeTexto`: el primer "0003-00012345" del texto, para la carga a mano.
    static func numeroDeTexto(_ texto: String) -> (pv: String, cmp: String) {
        guard let re = try? NSRegularExpression(pattern: "(\\d{4,5})\\s*-\\s*(\\d{7,8})"),
              let m = re.firstMatch(in: texto, range: NSRange(location: 0, length: (texto as NSString).length)) else { return ("", "") }
        let ns = texto as NSString
        return (String(format: "%04d", Int(ns.substring(with: m.range(at: 1))) ?? 0),
                String(format: "%08d", Int(ns.substring(with: m.range(at: 2))) ?? 0))
    }

    /// `_facTotalDeTexto`: el número de plata más grande del texto.
    static func totalDeTexto(_ texto: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: "\\d{1,3}(?:\\.\\d{3})*,\\d{2}") else { return nil }
        let ns = texto as NSString
        let max = re.matches(in: texto, range: NSRange(location: 0, length: ns.length))
            .compactMap { Facturas.importe(ns.substring(with: $0.range)) }.max() ?? 0
        return max > 0 ? max : nil
    }

    // MARK: Buscar el QR en una imagen (Vision)

    /// Devuelve los textos de todos los QR encontrados. Prueba a tamaño real y agrandado (QR chicos en capturas).
    static func qrs(en imagen: CGImage) -> [String] {
        func buscar(_ img: CGImage) -> [String] {
            let req = VNDetectBarcodesRequest()
            req.symbologies = [.qr]
            try? VNImageRequestHandler(cgImage: img, options: [:]).perform([req])
            return (req.results ?? []).compactMap(\.payloadStringValue)
        }
        var r = buscar(imagen)
        if r.isEmpty {
            for escala in [2.0, 3.0] {
                let w = Int(Double(imagen.width) * escala), h = Int(Double(imagen.height) * escala)
                if w * h > 16_000_000 { break }
                guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { break }
                ctx.interpolationQuality = .none
                ctx.draw(imagen, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let grande = ctx.makeImage() { r = buscar(grande) }
                if !r.isEmpty { break }
            }
        }
        return r
    }

    enum Resultado {
        case ok(DatosQR, texto: String)
        case qrInvalido(texto: String)      // es el QR de AFIP pero no trae datos (Materiales Avenida)
        case noEsAfip                        // se leyó un QR, pero es de otra cosa
        case sinQR(texto: String)            // no se encontró QR (se precarga la carga a mano con el texto)
    }

    /// De los QR leídos, el de AFIP con datos.
    static func evaluar(_ codigos: [String], texto: String) -> Resultado {
        var invalido = false
        for c in codigos {
            if let d = parsear(c) { return .ok(d, texto: texto) }
            if esQRAfip(c) { invalido = true }
        }
        if invalido { return .qrInvalido(texto: texto) }
        return codigos.isEmpty ? .sinQR(texto: texto) : .noEsAfip
    }

    /// `_facLeerFacturaPDF`: renderiza hasta 3 páginas y busca el QR; además junta el texto para el CUIT.
    static func leerPDF(_ datos: Data) -> Resultado {
        guard let doc = PDFDocument(data: datos) else { return .sinQR(texto: "") }
        if doc.isLocked { doc.unlock(withPassword: "") }
        let paginas = min(doc.pageCount, 3)
        var texto = ""
        for i in 0..<paginas { texto += " " + (doc.page(at: i)?.string ?? "") }
        var codigos: [String] = []
        for escala in [3.0, 4.5] {
            for i in 0..<paginas {
                guard let pag = doc.page(at: i) else { continue }
                let caja = pag.bounds(for: .mediaBox)
                let tam = CGSize(width: caja.width * escala, height: caja.height * escala)
                if tam.width * tam.height > 30_000_000 { continue }
                let img = pag.thumbnail(of: tam, for: .mediaBox)
                if let cg = img.cgImage { codigos += qrs(en: cg) }
                if case .ok = evaluar(codigos, texto: texto) { return evaluar(codigos, texto: texto) }
            }
            if case .qrInvalido = evaluar(codigos, texto: texto) { break }   // agrandar no lo arregla
        }
        return evaluar(codigos, texto: texto)
    }
}

/// Cámara que busca el QR en vivo (VisionKit). Avisa cada QR leído; la pantalla decide si sirve.
struct EscanerQR: UIViewControllerRepresentable {
    let alLeer: (String) -> Void

    @MainActor static var disponible: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                           qualityLevel: .accurate, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinador { Coordinador(alLeer: alLeer) }

    @MainActor final class Coordinador: NSObject, DataScannerViewControllerDelegate {
        let alLeer: (String) -> Void
        init(alLeer: @escaping (String) -> Void) { self.alLeer = alLeer }
        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for item in items {
                if case .barcode(let b) = item, let t = b.payloadStringValue { alLeer(t) }
            }
        }
    }
}
