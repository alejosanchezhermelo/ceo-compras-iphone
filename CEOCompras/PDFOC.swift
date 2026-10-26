import UIKit

/// Copia de `generarPDFDoc(ocData)` de la web (jsPDF + autoTable): mismas medidas en mm,
/// mismos textos, colores y columnas. Si se cambia el PDF de la web, cambiarlo también acá.
enum PDFOC {
    struct Datos {
        let num: Int
        let proveedor: String
        let obra: String
        let responsable: String
        let notas: String
        let fecha: String
        let items: [ItemOC]

        /// `generarPDF(id)` de la web. Sin `numOCPDF` la web asigna un número nuevo (escribe en la base):
        /// en la etapa 1 (solo lectura) esas OC no se pueden generar desde el iPhone.
        init?(_ oc: OC) {
            guard let n = oc.numOCPDF else { return nil }
            num = n
            proveedor = oc.proveedor
            obra = oc.obra
            responsable = oc.responsable
            notas = oc.notas
            fecha = oc.fecha.isEmpty ? Formato.hoy() : oc.fecha.split(separator: "-").reversed().joined(separator: "/")
            items = oc.items
        }

        /// Para el PDF "OC + factura": la web usa `o.numOCPDF || o.num` (sin registrar nada).
        init(paraCombo oc: OC) {
            num = oc.numOCPDF ?? Int(oc.num) ?? 0
            proveedor = oc.proveedor
            obra = oc.obra
            responsable = oc.responsable
            notas = oc.notas
            fecha = oc.fecha.isEmpty ? Formato.hoy() : oc.fecha.split(separator: "-").reversed().joined(separator: "/")
            items = oc.items
        }
    }

    enum Falla: LocalizedError {
        case sinNumero
        var errorDescription: String? { "Esta OC todavía no tiene número de PDF. Generala una vez desde la PC." }
    }

    static let mm: CGFloat = 72 / 25.4
    private static let azul = UIColor(red: 26 / 255, green: 62 / 255, blue: 111 / 255, alpha: 1)

    /// Arma el PDF y lo deja en un archivo temporal "OC <num>.pdf" (mismo nombre que la web).
    static func archivo(_ oc: OC) throws -> URL {
        guard let d = Datos(oc) else { throw Falla.sinNumero }
        let formato = UIGraphicsPDFRendererFormat()
        formato.documentInfo = [kCGPDFContextTitle as String: "OC \(d.num)",
                                kCGPDFContextCreator as String: "CEO Compras"]
        let render = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 210 * mm, height: 297 * mm), format: formato)
        let data = render.pdfData { ctx in
            ctx.beginPage()
            dibujar(d, ctx)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("OC \(d.num).pdf")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: Dibujo

    private enum Alineacion { case izquierda, centro, derecha }

    private static func fuente(_ size: CGFloat, _ negrita: Bool) -> UIFont {
        UIFont(name: negrita ? "Helvetica-Bold" : "Helvetica", size: size)
            ?? .systemFont(ofSize: size, weight: negrita ? .bold : .regular)
    }

    /// Como `pdf.text(s, x, y)` de jsPDF: x e y en mm, y es la línea de base. Respeta los "\n".
    private static func escribir(_ s: String, _ x: CGFloat, _ y: CGFloat, size: CGFloat, negrita: Bool = false,
                                 color: UIColor = .black, alinear: Alineacion = .izquierda) {
        let f = fuente(size, negrita)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
        for (i, linea) in s.components(separatedBy: "\n").enumerated() {
            let ancho = (linea as NSString).size(withAttributes: attrs).width
            var px = x * mm
            if alinear == .centro { px -= ancho / 2 }
            if alinear == .derecha { px -= ancho }
            let base = y * mm + CGFloat(i) * size * 1.15
            (linea as NSString).draw(at: CGPoint(x: px, y: base - f.ascender), withAttributes: attrs)
        }
    }

    static func dibujar(_ d: Datos, _ ctx: UIGraphicsPDFRendererContext) {
        let numStr = String(format: "%07d", d.num)
        escribir("CEO CONSTRUCCIONES SRL", 20, 18, size: 14, negrita: true)
        escribir("CUIT: 30-70732992-7  |  Ingresos Brutos: 021-309245-4", 20, 24, size: 9)
        escribir("SUIPACHA 2050 - FUNES", 20, 29, size: 9)
        escribir("00001 " + numStr, 150, 18, size: 10)
        escribir("ORIGINAL  |  IVA RESPONSABLE INSCRIPTO", 135, 24, size: 8)
        escribir("Comprobante no valido como Factura", 135, 29, size: 8)

        azul.setFill()
        UIRectFill(CGRect(x: 15 * mm, y: 34 * mm, width: 180 * mm, height: 9 * mm))
        escribir("ORDEN DE COMPRA", 105, 40.5, size: 13, negrita: true, color: .white, alinear: .centro)

        escribir("No OC: \(d.num)", 20, 51, size: 10)
        escribir("Fecha: \(d.fecha)", 80, 51, size: 10)
        var y: CGFloat = 57
        if !d.obra.isEmpty { escribir("Obra: \(d.obra)", 20, y, size: 10); y += 6 }
        if !d.responsable.isEmpty { escribir("Responsable: \(d.responsable)", 20, y, size: 10); y += 6 }
        escribir("Proveedor: " + d.proveedor.uppercased(), 20, y + 2, size: 10, negrita: true)

        // String(it.cant || '1') y it.unit || it.unidad (igual que la web desde 2026-10-26)
        let filas = d.items.map { [$0.desc, $0.cant.isEmpty ? "1" : $0.cant, $0.unit.isEmpty ? $0.unidad : $0.unit] }
        var fy = tabla(filas, desde: y + 8, ctx: ctx) + 6

        if !d.notas.isEmpty { escribir("Obs: " + d.notas, 20, fy, size: 9); fy += 8 }
        azul.setStroke()
        let linea = UIBezierPath()
        linea.move(to: CGPoint(x: 15 * mm, y: fy * mm))
        linea.addLine(to: CGPoint(x: 195 * mm, y: fy * mm))
        linea.lineWidth = 0.5 * mm
        linea.stroke()
        let gris = UIColor(white: 100 / 255, alpha: 1)
        escribir("Consultas: +54 9 341 468-2417  |  admcompras@ceoconstrucciones.com.ar", 20, fy + 5, size: 8, color: gris)
        escribir("CEO Construcciones SRL", 175, fy + 5, size: 8, color: gris, alinear: .derecha)
    }

    /// Tabla como autoTable (tema "striped"): márgenes de 40 pt, columnas Cantidad y Unidad de 22 mm,
    /// relleno de celda 3 mm, letra 9, encabezado azul que se repite si la tabla sigue en otra hoja.
    /// Devuelve dónde terminó (en mm).
    private static func tabla(_ filas: [[String]], desde inicio: CGFloat, ctx: UIGraphicsPDFRendererContext) -> CGFloat {
        let margen: CGFloat = 40 / mm
        let ancho = 210 - 2 * margen
        let columnas: [CGFloat] = [ancho - 44, 22, 22]
        let relleno: CGFloat = 3
        let size: CGFloat = 9
        let alto1 = size * 1.15 / mm
        let normal = fuente(size, false)
        let negrita = fuente(size, true)
        let franja = UIColor(red: 245 / 255, green: 247 / 255, blue: 251 / 255, alpha: 1)
        let tinta = UIColor(white: 20 / 255, alpha: 1)

        func cortar(_ s: String, _ anchoMM: CGFloat, _ f: UIFont) -> [String] {
            let max = anchoMM * mm
            let attrs: [NSAttributedString.Key: Any] = [.font: f]
            func mide(_ t: String) -> CGFloat { (t as NSString).size(withAttributes: attrs).width }
            var salida: [String] = []
            for parrafo in s.components(separatedBy: "\n") {
                var actual = ""
                for palabra in parrafo.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                    let prueba = actual.isEmpty ? palabra : actual + " " + palabra
                    if mide(prueba) <= max || actual.isEmpty && mide(palabra) <= max {
                        actual = prueba
                        continue
                    }
                    if !actual.isEmpty { salida.append(actual) }
                    // palabra más larga que la columna: se corta por letras
                    var resto = palabra
                    actual = ""
                    while mide(resto) > max, resto.count > 1 {
                        var corte = resto.count - 1
                        while corte > 1 && mide(String(resto.prefix(corte))) > max { corte -= 1 }
                        salida.append(String(resto.prefix(corte)))
                        resto = String(resto.dropFirst(corte))
                    }
                    actual = resto
                }
                salida.append(actual)
            }
            return salida.isEmpty ? [""] : salida
        }

        func fila(_ celdas: [[String]], y: CGFloat, alto: CGFloat, fondo: UIColor?, f: UIFont, color: UIColor) {
            if let fondo {
                fondo.setFill()
                UIRectFill(CGRect(x: margen * mm, y: y * mm, width: ancho * mm, height: alto * mm))
            }
            let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
            var x = margen
            for (i, lineas) in celdas.enumerated() {
                for (j, l) in lineas.enumerated() {
                    let arriba = y + relleno + CGFloat(j) * alto1 + (alto1 - f.lineHeight / mm) / 2
                    (l as NSString).draw(at: CGPoint(x: (x + relleno) * mm, y: arriba * mm), withAttributes: attrs)
                }
                x += columnas[i]
            }
        }

        var y = inicio
        let limite: CGFloat = 297 - margen
        let encabezado = ["Articulo", "Cantidad", "Unidad"].map { [$0] }
        func ponerEncabezado() {
            let alto = alto1 + 2 * relleno
            fila(encabezado, y: y, alto: alto, fondo: azul, f: negrita, color: .white)
            y += alto
        }

        ponerEncabezado()
        for (i, celdas) in filas.enumerated() {
            let partidas = zip(celdas, columnas).map { cortar($0, $1 - 2 * relleno, normal) }
            let alto = CGFloat(partidas.map(\.count).max() ?? 1) * alto1 + 2 * relleno
            if y + alto > limite {
                ctx.beginPage()
                y = margen
                ponerEncabezado()
            }
            fila(partidas, y: y, alto: alto, fondo: i % 2 == 1 ? franja : nil, f: normal, color: tinta)
            y += alto
        }
        return y
    }
}
