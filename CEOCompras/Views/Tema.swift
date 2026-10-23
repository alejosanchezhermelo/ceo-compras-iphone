import SwiftUI

/// Estilo de la PWA (variables CSS de `:root` en index.html) llevado al iPhone.
/// Si cambian los colores de la web, cambiarlos acá también.
enum T {
    // Fondos y bordes
    static let bg = Color(hex: 0xF0EDE8)      // --bg
    static let sf = Color(hex: 0xFAFAF7)      // --sf  (tarjetas)
    static let sf2 = Color(hex: 0xEDEAE4)     // --sf2
    static let bd = Color(hex: 0xD6D1C8)      // --bd
    static let bd2 = Color(hex: 0xC4BFB5)     // --bd2
    // Texto
    static let tx = Color(hex: 0x1C1916)
    static let tx2 = Color(hex: 0x6B6560)
    static let tx3 = Color(hex: 0xA09A92)
    // Azul / verde / ámbar / rojo / violeta (fuerte, claro, medio)
    static let bl = Color(hex: 0x1A3E6F), blL = Color(hex: 0xE6EDF6), blM = Color(hex: 0xAABFD8)
    static let gn = Color(hex: 0x1E4D2B), gnL = Color(hex: 0xE6F0E8), gnM = Color(hex: 0x8BB89A)
    static let am = Color(hex: 0x7A4500), amL = Color(hex: 0xFDF1E0), amM = Color(hex: 0xE8B86A)
    static let rd = Color(hex: 0x7A1A1A), rdL = Color(hex: 0xFDEAEA), rdM = Color(hex: 0xDFA0A0)
    static let pp = Color(hex: 0x4A1E7A), ppL = Color(hex: 0xEEE8F8), ppM = Color(hex: 0xB8A0D8)
    static let urgente = Color(hex: 0xC0392B)
    static let urgenteFondo = Color(hex: 0xFFF5F5)

    // Letras de la PWA: Syne (títulos y N° de OC), DM Sans (texto), DM Mono (datos chicos)
    static func syne(_ size: CGFloat, _ peso: Peso = .bold) -> Font {
        .custom(peso == .bold ? "CEOSyne-Bold" : "CEOSyne-SemiBold", size: size)
    }
    static func sans(_ size: CGFloat, _ peso: Peso = .regular) -> Font {
        let n: String
        switch peso {
        case .regular: n = "CEODMSans-Regular"
        case .medium: n = "CEODMSans-Medium"
        case .semibold: n = "CEODMSans-SemiBold"
        case .bold: n = "CEODMSans-Bold"
        }
        return .custom(n, size: size)
    }
    static func mono(_ size: CGFloat, _ peso: Peso = .regular) -> Font {
        .custom(peso == .regular ? "CEODMMono-Regular" : "CEODMMono-Medium", size: size)
    }
    enum Peso { case regular, medium, semibold, bold }
}

/// Tarjeta blanca con borde fino y esquinas de 12 (`.occ` / `.panel` de la PWA).
struct Tarjeta: ViewModifier {
    var fondo: Color = T.sf
    var bordeIzq: Color? = nil
    func body(content: Content) -> some View {
        content
            .background(fondo)
            .overlay(alignment: .leading) {
                if let bordeIzq { Rectangle().fill(bordeIzq).frame(width: 4) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(T.bd, lineWidth: 1))
    }
}

extension View {
    func tarjeta(fondo: Color = T.sf, bordeIzq: Color? = nil) -> some View {
        modifier(Tarjeta(fondo: fondo, bordeIzq: bordeIzq))
    }
}

/// Título chico en mayúsculas y letra mono ("MATERIALES", `.blbl` de la PWA).
struct Rotulo: View {
    let texto: String
    var body: some View {
        Text(texto.uppercased())
            .font(T.mono(10, .medium))
            .kerning(0.7)
            .foregroundStyle(T.tx3)
    }
}

/// Separador con contador ("📦 Órdenes de compra  442", `mkDiv` de la PWA).
struct Divisor: View {
    let texto: String
    let n: Int
    var color: Color = T.bl
    var claro: Color = T.blL
    var medio: Color = T.blM
    var body: some View {
        HStack(spacing: 8) {
            Text(texto).font(T.sans(12, .semibold)).foregroundStyle(T.tx2)
            Text("\(n)")
                .font(T.mono(11, .medium))
                .padding(.horizontal, 7).padding(.vertical, 1)
                .background(claro, in: Capsule())
                .overlay(Capsule().stroke(medio, lineWidth: 1))
                .foregroundStyle(color)
            Rectangle().fill(T.bd).frame(height: 1)
        }
        .padding(.top, 6)
    }
}

/// Botones de la PWA: azul lleno (`.bp`) y blanco con borde (`.bg`).
struct BotonPWA: ButtonStyle {
    enum Tipo { case azul, blanco, color(Color), suave(Color, Color, Color) }
    var tipo: Tipo = .azul
    func makeBody(configuration: Configuration) -> some View {
        let (fondo, texto, borde): (Color, Color, Color) = {
            switch tipo {
            case .azul: return (T.bl, .white, T.bl)
            case .blanco: return (T.sf, T.tx2, T.bd)
            case .color(let c): return (c, .white, c)
            case .suave(let f, let t, let b): return (f, t, b)
            }
        }()
        return configuration.label
            .font(T.sans(13, .medium))
            .padding(.horizontal, 14).padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(fondo.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(borde, lineWidth: 1))
            .foregroundStyle(texto)
    }
}

/// Campo de texto con el estilo de los inputs de la PWA.
struct CampoPWA: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(T.sans(14))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(T.bd, lineWidth: 1))
    }
}

extension View {
    func campoPWA() -> some View { modifier(CampoPWA()) }
}

/// Punto de color del historial (`.hd.c`, `.hd.e`, ...).
func colorEvento(_ tipo: String) -> Color {
    switch tipo {
    case "c": return T.bl
    case "e": return T.gn
    case "p": return T.rd
    case "s": return T.pp
    default: return T.tx3
    }
}
