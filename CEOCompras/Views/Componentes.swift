import SwiftUI
import PDFKit

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Azul de CEO (#1A3E6F, el `--bl` de la web); más claro en modo oscuro para que se lea.
    static let ceoAzul = Color(UIColor { t in
        t.userInterfaceStyle == .dark
            ? UIColor(red: 0.47, green: 0.64, blue: 0.90, alpha: 1)
            : UIColor(red: 26 / 255, green: 62 / 255, blue: 111 / 255, alpha: 1)
    })
}

extension Color {
    /// "#1A3E6F" o "1A3E6F" → color. Devuelve nil si no es un color válido.
    init?(hexTexto: String) {
        var t = hexTexto.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

extension Rubro {
    /// Color del rubro; si no se puede leer, gris.
    var tinta: Color { Color(hexTexto: color) ?? T.tx2 }
}

/// Etiqueta de color, como los "tag" de la web (`.tag` + `.tp` / `.tpa` / `.te` / `.to`).
struct Etiqueta: View {
    let texto: String
    let fondo: Color
    let color: Color
    var borde: Color = .clear
    /// Ícono de Apple adelante del texto (v0.19, en lugar del emoji).
    var icono: String? = nil

    var body: some View {
        (icono.map { ic($0, texto) } ?? Text(texto))
            .font(T.sans(11, .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(fondo, in: Capsule())
            .overlay(Capsule().stroke(borde, lineWidth: 1))
            .foregroundStyle(color)
    }

    /// Mismos colores que `cardOC` de la PWA: Pendiente ámbar, Parcial rojo, Entregado verde.
    static func estado(_ oc: OC) -> Etiqueta {
        switch oc.estado {
        case "entregado": return Etiqueta(texto: "Entregado", fondo: T.gnL, color: T.gn, borde: T.gnM)
        case "parcial": return Etiqueta(texto: "Entrega parcial", fondo: T.rdL, color: T.rd, borde: T.rdM)
        default: return Etiqueta(texto: "Pendiente", fondo: T.amL, color: T.am, borde: T.amM)
        }
    }

    static func urgente() -> Etiqueta {
        Etiqueta(texto: "URGENTE", fondo: T.urgente, color: .white, borde: T.urgente, icono: "exclamationmark.circle.fill")
    }

    static func obra(_ nombre: String) -> Etiqueta {
        Etiqueta(texto: nombre, fondo: T.blL, color: T.bl, borde: T.blM)
    }

    static func factura(_ f: FacturaOC) -> Etiqueta {
        Etiqueta(texto: "Fact. \(f.num)" + (f.importe.map { " · " + Formato.pesos($0) } ?? ""),
                 fondo: T.gnL, color: T.gn, borde: T.gnM, icono: "receipt")
    }

    /// `.rubro-tag` de la web: fondo del color del rubro muy claro, letra y borde del mismo color.
    static func rubro(_ r: Rubro) -> some View {
        Text(r.nombre)
            .font(T.sans(11, .semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(r.tinta.opacity(0x22 / 255.0), in: Capsule())
            .overlay(Capsule().stroke(r.tinta.opacity(0x55 / 255.0), lineWidth: 1))
            .foregroundStyle(r.tinta)
    }

    static func solicitud() -> Etiqueta {
        Etiqueta(texto: "Pendiente de OC", fondo: T.ppL, color: T.pp, borde: T.ppM)
    }
}

/// Acomoda las etiquetas en renglones (si no entran en uno, bajan al siguiente).
struct Renglones: Layout {
    var espacio: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maximo = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, altoFila: CGFloat = 0, ancho: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > maximo { x = 0; y += altoFila + espacio; altoFila = 0 }
            x += t.width + espacio
            altoFila = max(altoFila, t.height)
            ancho = max(ancho, x - espacio)
        }
        return CGSize(width: min(ancho, maximo), height: y + altoFila)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, altoFila: CGFloat = 0
        for s in subviews {
            let t = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + t.width > bounds.maxX { x = bounds.minX; y += altoFila + espacio; altoFila = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(t.width, bounds.width), height: t.height))
            x += t.width + espacio
            altoFila = max(altoFila, t.height)
        }
    }
}

/// Un dato de la ficha ("Obra: Vida"). No se muestra si está vacío.
struct Dato: View {
    let titulo: String
    let valor: String

    init(_ titulo: String, _ valor: String) {
        self.titulo = titulo
        self.valor = valor
    }

    var body: some View {
        if !valor.isEmpty {
            LabeledContent(titulo) {
                Text(valor).multilineTextAlignment(.trailing).foregroundStyle(.primary)
            }
        }
    }
}

/// Archivo PDF listo para mostrar o compartir.
struct ArchivoPDF: Identifiable {
    let id = UUID()
    let url: URL
    let titulo: String
}

/// Hoja de "Compartir" de iOS (WhatsApp, Mail, guardar en Archivos, etc.).
struct HojaCompartir: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ c: UIActivityViewController, context: Context) {}
}

struct VistaPDFKit: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.backgroundColor = .secondarySystemBackground
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {}
}

struct VisorPDF: View {
    let archivo: ArchivoPDF
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VistaPDFKit(url: archivo.url)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(archivo.titulo)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cerrar") { dismiss() }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { imprimir(archivo) } label: { Image(systemName: "printer") }
                        ShareLink(item: archivo.url) { Image(systemName: "square.and.arrow.up") }
                    }
                }
        }
    }

    private func imprimir(_ a: ArchivoPDF) {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = a.titulo
        let c = UIPrintInteractionController.shared
        c.printInfo = info
        c.printingItem = a.url
        c.present(animated: true)
    }
}
