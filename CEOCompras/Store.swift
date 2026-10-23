import SwiftUI
import CryptoKit

/// Estado de toda la app. ETAPA 1: SOLO LECTURA — nunca escribe en Firebase.
@Observable @MainActor
final class Store {
    enum Fase { case bloqueada, necesitaCodigo, adentro }

    var fase: Fase = .bloqueada
    /// Ya entró al menos una vez en esta sesión (la lista queda armada debajo del bloqueo).
    var haEntrado = false
    var ordenes: [OC] = []
    var eventosPorOC: [String: [EventoOC]] = [:]
    var obras: [String] = []
    var encargados: [String] = []
    var nextOCNum = 858
    var conectado = false
    var mensajeConexion: String?
    var mensajeLogin: String?
    var faceIDActivado = Keychain.get(Claves.faceID) != nil
    var ofrecerFaceID = false

    /// Nodos de la base que usa la etapa 1 (no se baja `pruebas`, `listasPrecios`, etc.).
    static let nodos = ["config", "ordenes", "obras", "encargados", "historial"]

    @ObservationIgnored private var arboles: [String: Any] = [:]
    @ObservationIgnored private var configPassword = ""
    @ObservationIgnored private var configCargado = false
    @ObservationIgnored private var configEnVivo = false
    @ObservationIgnored private var verificarFaceIDPendiente = false
    @ObservationIgnored private var tareas: [Task<Void, Never>] = []
    @ObservationIgnored private var tareaCache: Task<Void, Never>?
    @ObservationIgnored private var enFondoDesde: Date?
    @ObservationIgnored private var vieneDeFondo = false
    @ObservationIgnored private var faceIDEnCurso = false

    init() {
        cargarCache()
        conectar()
    }

    // MARK: Conexión en vivo

    func conectar() {
        tareas.forEach { $0.cancel() }
        tareas = Store.nodos.map { escuchar($0) }
    }

    func reconectar() async {
        conectar()
        try? await Task.sleep(nanoseconds: 800_000_000)
    }

    func reintentarCodigo() {
        fase = haEntrado ? .adentro : .bloqueada
        mensajeConexion = nil
        conectar()
        Task { await entrarConFaceID() }
    }

    private func escuchar(_ nodo: String) -> Task<Void, Never> {
        // El Store vive mientras viva la app, así que se lo toma directo (sin "weak").
        Task {
            var espera: UInt64 = 1
            while !Task.isCancelled {
                let inicio = Date()
                do {
                    try await Firebase.shared.escuchar(nodo) { evento, ruta, dato in
                        await self.aplicar(nodo, evento, ruta, dato)
                    }
                } catch FBError.codigoNoRegistrado {
                    self.fase = .necesitaCodigo
                    return
                } catch {
                    if Task.isCancelled { return }
                    if Date().timeIntervalSince(inicio) > 60 { espera = 1 }
                    if espera > 2 {
                        self.conectado = false
                        self.mensajeConexion = "Sin conexión. Mostrando lo último guardado."
                    }
                }
                try? await Task.sleep(nanoseconds: espera * 1_000_000_000)
                espera = min(espera * 2, 30)
            }
        }
    }

    private func aplicar(_ nodo: String, _ evento: String, _ ruta: String, _ dato: Any) {
        arboles[nodo] = JSONTree.aplicar(arboles[nodo], evento: evento, ruta: ruta, dato: dato)
        conectado = true
        mensajeConexion = nil
        reconstruir(nodo, enVivo: true)
        guardarCacheLuego()
    }

    private func reconstruir(_ nodo: String, enVivo: Bool) {
        let a = arboles[nodo]
        switch nodo {
        case "ordenes":
            let d = a as? [String: Any] ?? [:]
            ordenes = d.compactMap { OC(clave: $0.key, $0.value) }
        case "historial":
            var g: [String: [EventoOC]] = [:]
            for (k, v) in a as? [String: Any] ?? [:] {
                guard let e = v as? [String: Any] else { continue }
                let oc = texto(e["ocId"])
                if oc.isEmpty { continue }
                g[oc, default: []].append(EventoOC(id: k, ocId: oc, tipo: texto(e["tipo"]),
                                                   texto: texto(e["texto"]), ts: numero(e["ts"]) ?? 0))
            }
            for k in g.keys { g[k]?.sort { $0.ts < $1.ts } }
            eventosPorOC = g
        case "config":
            let d = a as? [String: Any] ?? [:]
            configPassword = texto(d["password"])
            nextOCNum = Int(numero(d["nextOCNum"]) ?? 858)
            configCargado = true
            if enVivo {
                configEnVivo = true
                verificarFaceIDContraConfig()
            }
        case "obras":
            // obras.filter(oA).map(oN) de la web
            var vistas = Set<String>()
            obras = JSONTree.lista(a).compactMap { o -> String? in
                var n = ""
                if let s = o as? String { n = s }
                else if let d = o as? [String: Any], !verdadero(d["archivada"]) { n = texto(d["nombre"]) }
                guard !n.isEmpty, vistas.insert(n).inserted else { return nil }
                return n
            }
        case "encargados":
            var vistos = Set<String>()
            encargados = JSONTree.lista(a).map { texto($0) }.filter { !$0.isEmpty && vistos.insert($0).inserted }
        default:
            break
        }
    }

    // MARK: Entrada (misma regla que la web)

    /// `config.password || 'compras123'`
    private var passwordVigente: String {
        configPassword.isEmpty ? Config.passwordPorDefecto : configPassword
    }

    func entrarConPassword(_ escrita: String) async {
        mensajeLogin = nil
        var espera = 0
        while !configEnVivo && espera < 80 && fase == .bloqueada {
            try? await Task.sleep(nanoseconds: 100_000_000)
            espera += 1
        }
        guard configEnVivo else {
            if fase == .bloqueada { mensajeLogin = "Sin conexión. Verificá tu red e intentá de nuevo." }
            return
        }
        let guardada = passwordVigente
        let ok = guardada.count == 64 ? Store.sha256(escrita) == guardada : escrita == guardada
        guard ok else {
            mensajeLogin = "Contraseña incorrecta"
            return
        }
        entrar()
        if !faceIDActivado && Biometria.disponible() && !UserDefaults.standard.bool(forKey: Claves.faceIDOfrecido) {
            ofrecerFaceID = true
        }
    }

    func entrarConFaceID() async {
        guard faceIDActivado, !faceIDEnCurso, fase == .bloqueada else { return }
        faceIDEnCurso = true
        defer { faceIDEnCurso = false }
        guard await Biometria.autenticar("Entrar a CEO Compras") else { return }
        // Si la contraseña de Compras cambió desde que se activó Face ID, no deja pasar (igual que la web).
        if configCargado && Keychain.get(Claves.faceID) != passwordVigente {
            anularFaceID()
            return
        }
        // Se entra ya con los datos guardados; cuando llega la configuración en vivo se vuelve a comprobar.
        verificarFaceIDPendiente = !configEnVivo
        entrar()
    }

    private func entrar() {
        mensajeLogin = nil
        haEntrado = true
        fase = .adentro
    }

    private func verificarFaceIDContraConfig() {
        guard verificarFaceIDPendiente else { return }
        verificarFaceIDPendiente = false
        if Keychain.get(Claves.faceID) != passwordVigente {
            fase = .bloqueada
            anularFaceID()
        }
    }

    private func anularFaceID() {
        Keychain.set(Claves.faceID, nil)
        faceIDActivado = false
        mensajeLogin = "La contraseña de Compras cambió. Entrá con la nueva y volvé a activar Face ID en Ajustes."
    }

    func activarFaceID() async {
        UserDefaults.standard.set(true, forKey: Claves.faceIDOfrecido)
        guard await Biometria.autenticar("Activar Face ID para entrar a CEO Compras") else { return }
        Keychain.set(Claves.faceID, passwordVigente)
        faceIDActivado = true
    }

    func desactivarFaceID() {
        Keychain.set(Claves.faceID, nil)
        faceIDActivado = false
    }

    func noOfrecerFaceID() {
        UserDefaults.standard.set(true, forKey: Claves.faceIDOfrecido)
    }

    func bloquear() {
        fase = .bloqueada
        Task { await entrarConFaceID() }
    }

    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Primer plano / segundo plano

    func alAbrir() async {
        try? await Task.sleep(nanoseconds: 350_000_000)
        await entrarConFaceID()
    }

    func cambioDeEscena(_ escena: ScenePhase) {
        switch escena {
        case .background:
            // Solo cuenta el segundo plano real: la ventana de Face ID pone la app "inactiva", no "en fondo".
            vieneDeFondo = true
            enFondoDesde = Date()
        case .active:
            guard vieneDeFondo else { return }
            vieneDeFondo = false
            let ausencia = enFondoDesde.map { Date().timeIntervalSince($0) } ?? 0
            enFondoDesde = nil
            if ausencia > 15 { conectar() }   // iOS corta las conexiones en segundo plano
            if fase == .adentro && ausencia > Config.bloqueoTrasSegundos { fase = .bloqueada }
            if fase == .bloqueada { Task { await entrarConFaceID() } }
        default:
            break
        }
    }

    // MARK: Copia local (para abrir al instante, aun sin señal)

    nonisolated private static var archivoCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ceo-datos.json")
    }

    private func cargarCache() {
        guard let d = try? Data(contentsOf: Store.archivoCache),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        arboles = obj
        for n in Store.nodos { reconstruir(n, enVivo: false) }
    }

    private func guardarCacheLuego() {
        tareaCache?.cancel()
        let copia = arboles
        tareaCache = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await Task.detached(priority: .utility) {
                guard JSONSerialization.isValidJSONObject(copia),
                      let d = try? JSONSerialization.data(withJSONObject: copia) else { return }
                try? d.write(to: Store.archivoCache, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }.value
        }
    }
}
