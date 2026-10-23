import Foundation

enum FBError: Error {
    /// App Check rechazó el código de este iPhone: falta registrarlo en Firebase.
    case codigoNoRegistrado
    case http(Int, String)
    case formato
}

/// Conexión a Firebase por REST, sin el SDK de Google.
/// Mismo "portero + sello" que la web: usuario anónimo (Auth) + sello de App Check.
/// La web saca el sello con reCAPTCHA; el iPhone lo saca con su código de dispositivo
/// (el "debug token" de App Check), que hay que registrar una vez en la consola.
actor Firebase {
    static let shared = Firebase()

    private let sesion: URLSession
    private let sesionEnVivo: URLSession

    private var token: String?
    private var tokenVence = Date.distantPast
    private var tokenEnCurso: Task<String, Error>?

    private var sello: String?
    private var selloVence = Date.distantPast
    private var selloEnCurso: Task<String, Error>?

    init() {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        sesion = URLSession(configuration: c)
        let v = URLSessionConfiguration.default
        v.timeoutIntervalForRequest = 90          // Firebase manda "keep-alive" cada ~30 s
        v.timeoutIntervalForResource = 60 * 60 * 24
        sesionEnVivo = URLSession(configuration: v)
    }

    /// Código único de este iPhone. Se crea la primera vez y queda en el llavero.
    static var codigoDispositivo: String {
        if let c = Keychain.get(Claves.codigoDispositivo) { return c }
        let nuevo = UUID().uuidString.lowercased()
        Keychain.set(Claves.codigoDispositivo, nuevo)
        return nuevo
    }

    func invalidar() {
        token = nil
        sello = nil
    }

    // MARK: Usuario anónimo (el "portero")

    func tokenUsuario() async throws -> String {
        if let t = token, tokenVence > Date().addingTimeInterval(120) { return t }
        if let t = tokenEnCurso { return try await t.value }
        let t = Task { try await self.pedirTokenUsuario() }
        tokenEnCurso = t
        defer { tokenEnCurso = nil }
        return try await t.value
    }

    private func pedirTokenUsuario() async throws -> String {
        // Reusar el mismo usuario anónimo de siempre (como hace la web), si está guardado.
        if let refresh = Keychain.get(Claves.refreshToken) {
            do {
                let j = try await postForm("https://securetoken.googleapis.com/v1/token?key=\(Config.apiKey)",
                                           ["grant_type": "refresh_token", "refresh_token": refresh])
                if let t = j["id_token"] as? String {
                    guardarToken(t, venceEn: j["expires_in"])
                    if let nuevo = j["refresh_token"] as? String { Keychain.set(Claves.refreshToken, nuevo) }
                    return t
                }
            } catch FBError.http(let codigo, _) where codigo == 400 {
                Keychain.set(Claves.refreshToken, nil)   // usuario vencido o borrado: se crea otro
            }
        }
        let j = try await postJSON("https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=\(Config.apiKey)",
                                   ["returnSecureToken": true])
        guard let t = j["idToken"] as? String else { throw FBError.formato }
        guardarToken(t, venceEn: j["expiresIn"])
        if let r = j["refreshToken"] as? String { Keychain.set(Claves.refreshToken, r) }
        return t
    }

    private func guardarToken(_ t: String, venceEn: Any?) {
        token = t
        let segundos = Double(venceEn as? String ?? "") ?? 3600
        tokenVence = Date().addingTimeInterval(segundos)
    }

    // MARK: Sello de App Check

    func selloAppCheck() async throws -> String {
        if let s = sello, selloVence > Date().addingTimeInterval(300) { return s }
        if let t = selloEnCurso { return try await t.value }
        let t = Task { try await self.pedirSello() }
        selloEnCurso = t
        defer { selloEnCurso = nil }
        return try await t.value
    }

    private func pedirSello() async throws -> String {
        let url = "https://firebaseappcheck.googleapis.com/v1/projects/\(Config.projectId)/apps/\(Config.appId):exchangeDebugToken?key=\(Config.apiKey)"
        do {
            let j = try await postJSON(url, ["debugToken": Firebase.codigoDispositivo])
            guard let s = j["token"] as? String else { throw FBError.formato }
            let ttl = Double((j["ttl"] as? String ?? "3600s").replacingOccurrences(of: "s", with: "")) ?? 3600
            sello = s
            selloVence = Date().addingTimeInterval(ttl)
            return s
        } catch FBError.http(let codigo, _) where codigo == 403 {
            throw FBError.codigoNoRegistrado
        }
    }

    // MARK: Lectura en vivo

    private func pedido(_ ruta: String, enVivo: Bool = true) async throws -> URLRequest {
        let s = try await selloAppCheck()
        let t = try await tokenUsuario()
        guard let url = URL(string: "\(Config.dbURL)/\(ruta).json?auth=\(t)") else { throw FBError.formato }
        var r = URLRequest(url: url)
        r.setValue(s, forHTTPHeaderField: "X-Firebase-AppCheck")
        if enVivo { r.setValue("text/event-stream", forHTTPHeaderField: "Accept") }
        return r
    }

    // MARK: Escritura (etapa 2)

    /// Lee un dato junto con su "huella" (ETag), para después escribir solo si nadie lo cambió.
    func leerConHuella(_ ruta: String) async throws -> (valor: Any?, huella: String) {
        var r = try await pedido(ruta, enVivo: false)
        r.setValue("true", forHTTPHeaderField: "X-Firebase-ETag")
        let (data, resp) = try await sesion.data(for: r)
        let http = resp as? HTTPURLResponse
        guard http?.statusCode == 200 else { throw FBError.http(http?.statusCode ?? 0, "leer \(ruta)") }
        let v = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return (v is NSNull ? nil : v, http?.value(forHTTPHeaderField: "ETag") ?? "")
    }

    /// Escribe SOLO si el dato sigue igual que cuando se leyó. Devuelve false si alguien
    /// (por ejemplo la PC) lo cambió en el medio: entonces hay que volver a leer y reintentar.
    func escribirSiNoCambio(_ ruta: String, _ valor: Any, huella: String) async throws -> Bool {
        var r = try await pedido(ruta, enVivo: false)
        r.httpMethod = "PUT"
        r.setValue(huella, forHTTPHeaderField: "if-match")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: valor, options: [.fragmentsAllowed])
        let (_, resp) = try await sesion.data(for: r)
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if codigo == 412 { return false }
        guard codigo == 200 else { throw FBError.http(codigo, "escribir \(ruta)") }
        return true
    }

    /// Varios cambios de una sola vez: o se guardan todos o ninguno.
    /// Las claves son rutas debajo de `base` ("ordenes/ID", "historial/ID", ...). NSNull borra.
    func actualizarJuntos(base: String, _ cambios: [String: Any]) async throws {
        var r = try await pedido(base, enVivo: false)
        r.httpMethod = "PATCH"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: cambios)
        let (data, resp) = try await sesion.data(for: r)
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 200 else { throw FBError.http(codigo, String(data: data, encoding: .utf8) ?? "") }
    }

    /// Aviso por WhatsApp con CallMeBot, igual que `sendWA` de la web.
    nonisolated func avisarWhatsApp(numero: String, apikey: String, texto: String) async {
        // encodeURIComponent de JavaScript
        let permitidos = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        let t = texto.addingPercentEncoding(withAllowedCharacters: permitidos) ?? ""
        guard let url = URL(string: "https://api.callmebot.com/whatsapp.php?phone=\(numero)&text=\(t)&apikey=\(apikey)") else { return }
        _ = try? await URLSession.shared.data(from: url)
    }

    /// Escucha un nodo de la base. Firebase manda primero todo el contenido ("put" en "/")
    /// y después cada cambio. Termina con error cuando se corta (la app reconecta sola).
    nonisolated func escuchar(_ ruta: String,
                              alRecibir: @escaping @Sendable (String, String, Any) async -> Void) async throws {
        let req = try await pedido(ruta)
        let (bytes, resp) = try await sesionEnVivo.bytes(for: req)
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if codigo != 200 {
            if codigo == 401 { await invalidar() }
            throw FBError.http(codigo, "escuchar \(ruta)")
        }
        var evento = ""
        for try await linea in bytes.lines {
            if linea.hasPrefix("event:") {
                evento = linea.dropFirst(6).trimmingCharacters(in: .whitespaces)
            } else if linea.hasPrefix("data:") {
                switch evento {
                case "put", "patch":
                    let crudo = Data(linea.dropFirst(5).utf8)
                    guard let obj = (try? JSONSerialization.jsonObject(with: crudo, options: [.fragmentsAllowed])) as? [String: Any],
                          let camino = obj["path"] as? String else { continue }
                    await alRecibir(evento, camino, obj["data"] ?? NSNull())
                case "cancel", "auth_revoked":
                    // Venció el permiso (pasa cada ~1 h): se piden credenciales nuevas y se reconecta.
                    await invalidar()
                    throw FBError.http(401, evento)
                default:
                    continue
                }
            }
        }
        throw FBError.http(0, "conexión cerrada")
    }

    // MARK: Ayudas HTTP

    private func postJSON(_ url: String, _ cuerpo: [String: Any]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw FBError.formato }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONSerialization.data(withJSONObject: cuerpo)
        return try await enviar(r)
    }

    private func postForm(_ url: String, _ campos: [String: String]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw FBError.formato }
        var r = URLRequest(url: u)
        r.httpMethod = "POST"
        r.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let permitidos = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        r.httpBody = campos.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: permitidos) ?? "")" }
            .joined(separator: "&").data(using: .utf8)
        return try await enviar(r)
    }

    private func enviar(_ r: URLRequest) async throws -> [String: Any] {
        let (data, resp) = try await sesion.data(for: r)
        let codigo = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 200 else { throw FBError.http(codigo, String(data: data, encoding: .utf8) ?? "") }
        return (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }
}
