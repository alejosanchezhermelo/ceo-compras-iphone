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
    /// Ícono de Apple adelante del texto (v0.19, en lugar del emoji).
    var icono: String? = nil
    var body: some View {
        HStack(spacing: 8) {
            (icono.map { ic($0, texto) } ?? Text(texto)).font(T.sans(12, .semibold)).foregroundStyle(T.tx2)
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
    /// true = ocupa todo el ancho; false = del tamaño del texto (botones en fila que bajan de renglón).
    var lleno = true
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
            .frame(maxWidth: lleno ? CGFloat.infinity : nil)
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

// MARK: Liquid Glass (iOS 26)
// Solo en lo que flota sobre la pantalla: el botón "➕ Nueva OC" (BotonNuevaOC), la barra de abajo y la hoja "OC No …".
// Las tarjetas, materiales y botones de las OC quedan sólidos (con sol se leen mejor y siguen iguales a la PWA).
// En iOS 18 todo se ve como antes.

extension View {
    /// Fondo de una hoja que sube desde abajo: en iOS 26 se deja el vidrio del sistema; antes, blanco.
    @ViewBuilder func fondoHoja() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background(Color.white)
        }
    }
}


/// "Pedidos · COMPRAS" arriba a la izquierda. En iOS 26 el sistema le pone un círculo de vidrio a cada botón
/// de arriba y lo achicaba hasta dejar solo el ícono (foto de Alejo, 27/10): se le saca ese fondo.
struct ConEncabezado: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.toolbar {
                ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos().fixedSize() }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar { ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos() } }
        }
    }
}

extension View {
    func conEncabezado() -> some View { modifier(ConEncabezado()) }
}

// MARK: Vibraciones (v0.19)
// Toques cortos como las apps de Apple. Si el iPhone tiene las vibraciones del sistema apagadas, no vibra.

@MainActor
enum Vibrar {
    /// Toque muy leve: cambiar de pestaña.
    static func seleccion() { UISelectionFeedbackGenerator().selectionChanged() }
    /// Toque suave: abrir / cerrar una OC.
    static func suave() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    /// Toque firme: marcar urgente.
    static func firme() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    /// Doble toque de "listo": se guardó algo.
    static func listo() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    /// Aviso: antes de eliminar.
    static func aviso() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    /// Algo falló o falta un dato.
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

extension View {
    /// Vibra con "error" cada vez que aparece un cartel de error en la pantalla.
    func vibrarAlError(_ error: String?) -> some View {
        onChange(of: error) { _, nuevo in if nuevo != nil { Vibrar.error() } }
    }
}

// MARK: Íconos de Apple en lugar de emojis (v0.19)

/// Texto con un ícono de Apple adelante, en una sola línea de texto (toma la letra y el color de lo que lo rodea).
func ic(_ simbolo: String, _ texto: String) -> Text {
    texto.isEmpty ? Text(Image(systemName: simbolo)) : Text("\(Image(systemName: simbolo)) \(texto)")
}

/// Íconos de los cartelitos de abajo ("✅ OC activada" → ✓ verde + "OC activada").
/// Los textos siguen trayendo el emoji (son los mismos que la web); acá se cambia solo cómo se ven.
enum IconoAviso {
    static let tabla: [(String, String, Color)] = [
        ("✅", "checkmark.circle.fill", Color(hex: 0x6FCF97)),
        ("🗑", "trash.fill", Color(hex: 0xF2A3A3)),
        ("🔴", "exclamationmark.circle.fill", Color(hex: 0xFF8A80)),
        ("📦", "archivebox.fill", Color(hex: 0xE8B86A)),
        ("📝", "note.text", Color(hex: 0xAABFD8)),
    ]

    /// Separa el emoji del principio (si es uno conocido) y devuelve el ícono y el texto sin el emoji.
    static func separar(_ s: String) -> (simbolo: String, color: Color, texto: String)? {
        // Se compara "por dentro" (unicodeScalars) para que "🗑" y "🗑️" cuenten como el mismo.
        let letras = s.unicodeScalars
        for (emoji, simbolo, color) in tabla {
            let e = emoji.unicodeScalars
            guard letras.starts(with: e) else { continue }
            let resto = String(Substring(letras.dropFirst(e.count)))
            return (simbolo, color, resto.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FE0F} ")))
        }
        return nil
    }
}

// MARK: Carga con tarjetas "fantasma" (v0.19)

/// Brillo que pasa de lado a lado sobre las formas grises mientras se cargan los datos.
struct Brillo: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento
    @State private var avance: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay {
                if !sinMovimiento {
                    GeometryReader { g in
                        LinearGradient(colors: [.clear, .white.opacity(0.75), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: g.size.width * 0.5)
                            .offset(x: -g.size.width * 0.5 + avance * g.size.width * 1.5)
                    }
                    .mask(content)
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) { avance = 1 }
            }
    }
}

extension View {
    func brillo() -> some View { modifier(Brillo()) }
}

/// Una tarjeta gris con la forma de una OC (número, etiquetas, proveedor y fecha).
struct TarjetaFantasma: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Capsule().frame(width: 44, height: 14)
                Capsule().frame(width: 70, height: 14)
                Capsule().frame(width: 54, height: 14)
            }
            Capsule().frame(width: 190, height: 11)
            Capsule().frame(width: 110, height: 9)
        }
        .foregroundStyle(T.sf2)
        .padding(.vertical, 15).padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .brillo()
        .tarjeta()
    }
}

/// Un renglón gris con la forma de un evento del historial (punto + texto + fecha).
struct EventoFantasma: View {
    let ancho: CGFloat
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().frame(width: 8, height: 8).padding(.top, 4)
            VStack(alignment: .leading, spacing: 6) {
                Capsule().frame(width: ancho, height: 11)
                Capsule().frame(width: 80, height: 8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(T.sf2)
        .padding(.vertical, 9)
        .brillo()
    }
}
