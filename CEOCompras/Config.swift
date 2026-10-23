import Foundation

/// Datos públicos del proyecto de Firebase: son los mismos que ya usa la web
/// (están a la vista en el index.html publicado). Nada secreto vive en este archivo.
enum Config {
    static let apiKey = "AIzaSyD9_ZCLV2INMpawRpT7zyb69VvKcIQMmZ8"
    /// App Check se valida contra la app WEB registrada en Firebase; el iPhone usa su "código de dispositivo".
    static let appId = "1:844177055954:web:e83cd075029e05921a4d0b"
    static let projectId = "sistema-ceo"
    static let dbURL = "https://sistema-ceo-default-rtdb.firebaseio.com"
    /// Mismo valor por defecto que la web (`config.password || 'compras123'`).
    static let passwordPorDefecto = "compras123"
    /// Minutos en segundo plano tras los que la app se vuelve a bloquear.
    static let bloqueoTrasSegundos: TimeInterval = 5 * 60
}

enum Claves {
    static let codigoDispositivo = "appcheck-codigo-dispositivo"
    static let refreshToken = "auth-refresh-token"
    static let faceID = "faceid-password-guardada"
    static let faceIDOfrecido = "faceid-ofrecido"
}
