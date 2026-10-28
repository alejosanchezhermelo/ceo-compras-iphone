import SwiftUI
import CryptoKit

/// Estado de toda la app.
/// - Datos reales: SOLO LECTURA (mientras `Config.escrituraReal` sea false).
/// - Modo prueba: lee y escribe en `pruebas-iphone/`, una copia aparte de la base. Nunca toca las OC reales.
@Observable @MainActor
final class Store {
    enum Fase { case bloqueada, necesitaCodigo, adentro }

    var fase: Fase = .bloqueada
    /// Ya entró al menos una vez en esta sesión (la lista queda armada debajo del bloqueo).
    var haEntrado = false
    var modoPrueba = UserDefaults.standard.bool(forKey: "modo-prueba")
    var ordenes: [OC] = []
    var eventosPorOC: [String: [EventoOC]] = [:]
    var obras: [String] = []
    var encargados: [String] = []
    var proveedores: [String] = []
    var solicitudes: [Solicitud] = []
    /// Rubros (`rubros`): nombre y color, para el campo Rubro y la etiqueta de color de la OC.
    var rubros: [Rubro] = []
    /// Listas de precios (`listasPrecios`).
    var listasPrecios: [ListaPrecios] = []
    /// Fichas de proveedores (`provData`) y obras con archivadas (`obras`), para Ajustes y Proveedores.
    var fichasProveedores: [FichaProveedor] = []
    var obrasTodas: [ObraItem] = []
    /// Contactos de WhatsApp (`waContacts`).
    var contactosWA: [ContactoWA] = []
    /// Todo el historial, del más nuevo al más viejo (pestaña Actividad).
    var eventos: [EventoOC] = []
    var nextOCNum = 858
    var conectado = false
    var mensajeConexion: String?
    var mensajeLogin: String?
    var faceIDActivado = Keychain.get(Claves.faceID) != nil
    var ofrecerFaceID = false
    /// Cartelito de confirmación ("OC 1603 creada").
    var aviso: String?
    /// El botón flotante "➕ Nueva OC" (pegado a la barra de abajo) pide abrir el formulario de la pestaña Órdenes.
    var pedirNuevaOC = false
    /// Ajustes se abre desde el engranaje de arriba a la derecha (v0.21: su pestaña pasó a ser Gastos).
    var mostrarAjustes = false
    /// Conciliaciones hechas en la PC (`conciliaciones`): N° de factura → (id de OC → importe que le tocó).
    /// Sirve para repartir por obra las facturas que se cargaron en varias OC sin el importe de cada una
    /// (pasa con facturas grandes conciliadas en la PC). Se lee de una sola vez al abrir Gastos: NO se escucha en vivo
    /// para no sumar otra conexión fija (ver la lección de la v0.2).
    var conciliaciones: [String: [String: Double]] = [:]
    /// Compras anteriores a que se cargaran las facturas en la app (`gastosExcel`, v0.23): salen del Excel
    /// maestro de la oficina y se suman en Gastos como una factura más. Se lee junto con las conciliaciones.
    var gastosExcel: [GastoExcel] = []

    /// Nodos que se leen (dentro de la base real o de la de prueba).
    static let nodos = ["config", "ordenes", "obras", "encargados", "historial", "obrasData", "provData", "proveedores", "solicitudes", "listasPrecios", "rubros"]
    /// Contactos de WhatsApp (en modo prueba se leen de la copia; igual no se manda nada).
    static let nodoContactos = "waContacts"
    /// Para guardar, todos estos tienen que haber llegado en vivo (evita repetir el bug de duplicados de agosto).
    static let nodosParaGuardar: Set<String> = ["config", "ordenes", "obrasData", "provData", "proveedores"]

    @ObservationIgnored var arboles: [String: Any] = [:]
    @ObservationIgnored var waContacts: [[String: Any]] = []
    @ObservationIgnored private var arbolContactos: Any?
    @ObservationIgnored private var nodosEnVivo = Set<String>()
    @ObservationIgnored var generacion = 0
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

    /// Dónde se lee y escribe: "pruebas-iphone/" en modo prueba, la raíz en datos reales.
    var prefijo: String { modoPrueba ? "pruebas-iphone/" : "" }
    var base: String { modoPrueba ? "pruebas-iphone" : "" }

    var puedeEditar: Bool { modoPrueba || Config.escrituraReal }

    // MARK: Conexión en vivo

    func conectar() {
        tareas.forEach { $0.cancel() }
        let gen = generacion
        tareas = Store.nodos.map { escuchar($0, ruta: prefijo + $0, gen: gen) }
            + [escuchar(Store.nodoContactos, ruta: prefijo + Store.nodoContactos, gen: gen)]
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

    func cambiarModoPrueba(_ activar: Bool) {
        guard activar != modoPrueba else { return }
        modoPrueba = activar
        UserDefaults.standard.set(activar, forKey: "modo-prueba")
        generacion += 1
        tareas.forEach { $0.cancel() }
        tareaCache?.cancel()
        arboles = [:]
        nodosEnVivo = []
        configEnVivo = false
        ordenes = []
        eventosPorOC = [:]
        obras = []
        encargados = []
        proveedores = []
        solicitudes = []
        rubros = []
        eventos = []
        listasPrecios = []
        fichasProveedores = []
        obrasTodas = []
        conciliaciones = [:]
        gastosExcel = []
        conectado = false
        cargarCache()
        conectar()
    }

    // El Store vive mientras viva la app, así que se lo toma directo (sin "weak").
    private func escuchar(_ nodo: String, ruta: String, gen: Int) -> Task<Void, Never> {
        Task {
            var espera: UInt64 = 1
            while !Task.isCancelled {
                let inicio = Date()
                do {
                    try await Firebase.shared.escuchar(ruta) { evento, camino, dato in
                        await self.aplicar(nodo, evento, camino, dato, gen: gen)
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

    private func aplicar(_ nodo: String, _ evento: String, _ ruta: String, _ dato: Any, gen: Int) {
        guard gen == generacion else { return }   // llegó tarde, de antes de cambiar de modo
        if nodo == Store.nodoContactos {
            arbolContactos = JSONTree.aplicar(arbolContactos, evento: evento, ruta: ruta, dato: dato)
            waContacts = JSONTree.lista(arbolContactos).compactMap { $0 as? [String: Any] }
            contactosWA = waContacts.map { ContactoWA(nombre: texto($0["nombre"]), numero: texto($0["numero"]),
                                                      apikey: texto($0["apikey"]), rol: texto($0["rol"])) }
            return
        }
        arboles[nodo] = JSONTree.aplicar(arboles[nodo], evento: evento, ruta: ruta, dato: dato)
        nodosEnVivo.insert(nodo)
        // Solo se tocan si cambian: cada cambio redibuja las pantallas que los muestran
        if !conectado { conectado = true }
        if mensajeConexion != nil { mensajeConexion = nil }
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
            eventos = (a as? [String: Any] ?? [:]).compactMap { k, v -> EventoOC? in
                guard let e = v as? [String: Any] else { return nil }
                return EventoOC(id: k, ocId: texto(e["ocId"]), tipo: texto(e["tipo"]), texto: texto(e["texto"]), ts: numero(e["ts"]) ?? 0)
            }.sorted { $0.ts > $1.ts }
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
            var vistasT = Set<String>()
            obrasTodas = JSONTree.lista(a).compactMap { o -> ObraItem? in
                var item: ObraItem?
                if let s = o as? String { item = ObraItem(nombre: s, archivada: false) }
                else if let d = o as? [String: Any] { item = ObraItem(nombre: texto(d["nombre"]), archivada: verdadero(d["archivada"])) }
                guard let item, !item.nombre.isEmpty, vistasT.insert(item.nombre).inserted else { return nil }
                return item
            }
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
        case "proveedores":
            proveedores = Store.sinRepetir(JSONTree.lista(a).map { texto($0) })
        case "solicitudes":
            solicitudes = (a as? [String: Any] ?? [:]).compactMap { Solicitud(clave: $0.key, $0.value) }
                // La web muestra también las "convertida" (ya tienen OC); en el iPhone se esconden
                // a pedido de Alejo (23/10): al generar la OC desde la solicitud, la solicitud desaparece.
                .filter { $0.estado != "archivada" && $0.estado != "convertida" }.sorted { $0.ts > $1.ts }
        case "provData":
            fichasProveedores = (a as? [String: Any] ?? [:]).compactMap { FichaProveedor(clave: $0.key, $0.value) }
                .sorted { $0.nombre.localizedCompare($1.nombre) == .orderedAscending }
        case "rubros":
            // `Object.entries(rubros)` de la web: cada rubro con su id
            rubros = (a as? [String: Any] ?? [:]).compactMap { k, v -> Rubro? in
                guard let d = v as? [String: Any] else { return nil }
                let n = texto(d["nombre"])
                return n.isEmpty ? nil : Rubro(id: k, nombre: n, color: texto(d["color"]))
            }.sorted { $0.id < $1.id }   // orden en que se cargaron, como la web
        case "listasPrecios":
            listasPrecios = (a as? [String: Any] ?? [:]).compactMap { ListaPrecios(clave: $0.key, $0.value) }
        case "conciliaciones":
            // `sel` = { idDeOC: "12345,67" } (como lo guarda la conciliación de la web)
            var c: [String: [String: Double]] = [:]
            for (num, v) in a as? [String: Any] ?? [:] {
                guard let d = v as? [String: Any], let sel = d["sel"] as? [String: Any] else { continue }
                var porOC: [String: Double] = [:]
                for (oc, x) in sel {
                    if let t = x as? String, let n = Facturas.importe(t) { porOC[oc] = n } else if let n = numero(x) { porOC[oc] = n }
                }
                if !porOC.isEmpty { c[num] = porOC }
            }
            conciliaciones = c
        case "gastosExcel":
            gastosExcel = (a as? [String: Any] ?? [:]).compactMap { GastoExcel(clave: $0.key, $0.value) }
        default:
            break   // obrasData se consulta directo al guardar
        }
    }

    /// Igual que la web: saca repetidos sin mirar mayúsculas.
    private static func sinRepetir(_ lista: [String]) -> [String] {
        var vistos = Set<String>()
        return lista.filter { vistos.insert($0.lowercased()).inserted }
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

    // MARK: Guardar OC (etapa 2) — mismos pasos que `saveOrden()` / `_doSaveOrden()` de la web

    func numeroRepetido(_ num: String, editandoId: String?) -> Bool {
        let n = num.trimmingCharacters(in: .whitespaces)
        return ordenes.contains { $0.num == n && $0.id != editandoId }
    }

    /// Mismas validaciones que la web. Devuelve el error, o nil si está todo bien.
    func validar(_ b: BorradorOC, editando: OC?) -> String? {
        guard puedeEditar else { return "Guardar no está habilitado con los datos reales todavía." }
        let faltan = Store.nodosParaGuardar.subtracting(nodosEnVivo)
        if !faltan.isEmpty { return "Todavía se están cargando los datos. Esperá unos segundos y reintentá." }
        let num = b.num.trimmingCharacters(in: .whitespaces)
        if num.isEmpty { return "Ingresá el número de OC" }
        if !num.allSatisfy({ $0.isASCII && $0.isNumber }) { return "El número de OC debe ser solo números (ej: 858)" }
        if b.obra.trimmingCharacters(in: .whitespaces).isEmpty { return "Elegí una obra" }
        if b.encargado.isEmpty { return "Elegí el encargado" }
        for it in b.items where !it.desc.trimmingCharacters(in: .whitespaces).isEmpty {
            let c = Store.cantidad(it.cant)
            if !c.isEmpty && Double(c) == nil { return "La cantidad de “\(it.desc)” tiene que ser un número" }
        }
        return nil
    }

    /// El campo de la web es numérico: "2,5" del teclado argentino se guarda como "2.5".
    private static func cantidad(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    }

    /// Guarda una OC nueva o editada. Devuelve si salió bien y el mensaje para mostrar.
    func guardar(_ b: BorradorOC, editando: OC?, desdeSolicitud sol: Solicitud? = nil) async -> (ok: Bool, mensaje: String) {
        if let e = validar(b, editando: editando) { return (false, e) }
        let gen = generacion
        let enPrueba = modoPrueba
        let p = prefijo
        let num = b.num.trimmingCharacters(in: .whitespaces)
        let obra = b.obra.trimmingCharacters(in: .whitespaces)
        let resp = b.encargado
        let provEscrito = b.proveedor.trimmingCharacters(in: .whitespaces)
        let prov = capitalizarProveedor(provEscrito)
        let notas = b.notas.trimmingCharacters(in: .whitespaces)
        let items: [[String: Any]] = b.items.compactMap { it in
            let d = it.desc.trimmingCharacters(in: .whitespaces)
            if d.isEmpty { return nil }
            let c = Store.cantidad(it.cant)
            return ["desc": d, "cant": c.isEmpty ? "—" : c, "unit": it.unit.trimmingCharacters(in: .whitespaces)]
        }
        let numEntero = Int(num) ?? 0
        let numPDF: Any = numEntero > 0 ? (numEntero as Any) : (NSNull() as Any)   // parseInt(num) || null
        let ahora = Int64(Date().timeIntervalSince1970 * 1000)

        do {
            // 1) Proveedor nuevo: se suma a la lista sin pisar lo que haya agregado la PC en el medio.
            if !prov.isEmpty && !proveedores.contains(prov) {
                try await agregarProveedor(prov, p)
            }

            // 2) La OC, su obra/proveedor (si son nuevos) y el historial, todo junto.
            var cambios: [String: Any] = [:]
            let obraId = idDe("obrasData", obra, prefijoId: "obra_", &cambios) { id in
                ["id": id, "nombre": obra, "activa": true, "ts": ahora]
            }
            let provId = idDe("provData", prov, prefijoId: "prov_", &cambios) { id in
                ["id": id, "nombre": prov, "tel": "", "mail": "", "cuit": "", "direccion": "", "ts": ahora]
            }
            let ocId: String
            let textoHistorial: String
            if let o = editando {
                ocId = o.id
                let campos: [String: Any] = [
                    "num": num, "numOCPDF": numPDF, "obra": obra, "obraId": obraId, "responsable": resp,
                    "proveedor": prov, "provId": provId, "rubro": b.rubro, "notas": notas, "items": items,
                    // La web NO guarda la fecha al editar (es un error suyo); el iPhone sí.
                    "fecha": b.fechaTexto,
                ]
                for (k, v) in campos { cambios["ordenes/\(ocId)/\(k)"] = v }
                textoHistorial = "✏️ OC \(num) editada por Compras"
            } else {
                ocId = IDs.push()
                var oc: [String: Any] = [
                    "id": ocId, "num": num, "obra": obra, "obraId": obraId, "responsable": resp,
                    "proveedor": prov, "provId": provId, "rubro": b.rubro, "fecha": b.fechaTexto, "notas": notas,
                    "estado": "pendiente", "items": items, "comentario": "", "ts": ahora,
                ]
                if let n = numPDF as? Int { oc["numOCPDF"] = n }
                if let sol { oc["solRef"] = sol.encargado }
                cambios["ordenes/\(ocId)"] = oc
                textoHistorial = "📦 OC \(num) creada por Compras → \(resp) (\(obra))"
                if let sol {
                    // modalDesdeSol de la web: la solicitud pasa a "convertida" y queda anotado
                    cambios["solicitudes/\(sol.id)/estado"] = "convertida"
                    let (hs, es) = evento("📋 Solicitud de \(sol.encargado) convertida en OC \(num)", tipo: "c", ocId: nil, ts: ahora + 1)
                    cambios[hs] = es
                }
            }
            let hid = IDs.push()
            cambios["historial/\(hid)"] = ["id": hid, "tipo": "c", "texto": textoHistorial, "ocId": ocId, "ts": ahora]
            try await Firebase.shared.actualizarJuntos(base: enPrueba ? "pruebas-iphone" : "", cambios)

            // 3) Próximo número de OC (sin pisar un número que haya usado la PC en el medio).
            try await subirProximoNumero(num, p)
        } catch {
            return (false, "No se pudo guardar. Revisá la conexión e intentá de nuevo.\n(\(error))")
        }

        // 4) Aviso por WhatsApp al encargado (en modo prueba no se manda).
        var final = editando == nil ? "OC \(num) creada" : "OC \(num) guardada"
        if gen == generacion {
            let msg = editando == nil
                ? "🏗 Pedidos\n📦 Nueva OC \(num) asignada a vos\nObra: \(obra)\nProveedor: \(provEscrito.isEmpty ? "sin especificar" : provEscrito)\nEntrega estimada: \(b.fechaTexto.isEmpty ? "sin fecha" : b.fechaTexto)"
                : "🏗 Pedidos\n✏️ La OC \(num) fue editada por Compras."
            final += await avisarEncargado(resp, msg, enPrueba: enPrueba)
        }
        return (true, final)
    }

    /// `getObraId` / `getProvId` de la web: busca por nombre (sin mirar mayúsculas); si no existe, lo crea.
    func idDe(_ nodo: String, _ nombre: String, prefijoId: String, _ cambios: inout [String: Any],
                      nuevo: (String) -> [String: Any]) -> String {
        if nombre.isEmpty { return "" }
        let buscado = nombre.lowercased()
        for (clave, v) in arboles[nodo] as? [String: Any] ?? [:] {
            guard let d = v as? [String: Any], texto(d["nombre"]).lowercased() == buscado else { continue }
            let id = texto(d["id"])
            return id.isEmpty ? clave : id
        }
        let id = prefijoId + IDs.gen()
        cambios["\(nodo)/\(id)"] = nuevo(id)
        return id
    }

    private func agregarProveedor(_ prov: String, _ p: String) async throws {
        for _ in 0..<4 {
            let (valor, huella) = try await Firebase.shared.leerConHuella(p + "proveedores")
            let lista = Store.sinRepetir(JSONTree.lista(valor).map { texto($0) })
            if lista.contains(prov) { return }
            if try await Firebase.shared.escribirSiNoCambio(p + "proveedores", lista + [prov], huella: huella) { return }
        }
        throw FBError.http(412, "la lista de proveedores cambió varias veces seguidas")
    }

    /// `subirNextNum` de la web: si el número usado es >= al contador, el contador pasa a número + 1.
    func subirProximoNumero(_ num: String, _ p: String) async throws {
        guard let v = Int(num), v > 0 else { return }
        for _ in 0..<4 {
            let (actual, huella) = try await Firebase.shared.leerConHuella(p + "config/nextOCNum")
            let contador = Int(numero(actual) ?? 858)
            if v < contador { return }
            if try await Firebase.shared.escribirSiNoCambio(p + "config/nextOCNum", v + 1, huella: huella) { return }
        }
        throw FBError.http(412, "el número de OC cambió varias veces seguidas")
    }

    /// `notifyE` de la web.
    private func avisarEncargado(_ nombre: String, _ msg: String, enPrueba: Bool) async -> String {
        if enPrueba { return " · Modo prueba: no se mandó el WhatsApp a \(nombre)." }
        guard let c = waContacts.first(where: { texto($0["nombre"]) == nombre && texto($0["rol"]) == "encargado" }),
              !texto(c["numero"]).isEmpty, !texto(c["apikey"]).isEmpty else { return "" }
        await Firebase.shared.avisarWhatsApp(numero: texto(c["numero"]), apikey: texto(c["apikey"]), texto: msg)
        return " · Aviso por WhatsApp a \(nombre)."
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

    // MARK: Copia local (para abrir al instante, aun sin señal). Una por modo.

    nonisolated private static func archivoCache(prueba: Bool) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(prueba ? "ceo-datos-prueba.json" : "ceo-datos.json")
    }

    private func cargarCache() {
        guard let d = try? Data(contentsOf: Store.archivoCache(prueba: modoPrueba)),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return }
        arboles = obj
        for n in Store.nodos { reconstruir(n, enVivo: false) }
        reconstruir("conciliaciones", enVivo: false)
        reconstruir("gastosExcel", enVivo: false)
    }

    /// Lee las conciliaciones una vez (al abrir Gastos o al deslizar para actualizar).
    func cargarConciliaciones() async {
        let gen = generacion
        guard let r = try? await Firebase.shared.leerConHuella(prefijo + "conciliaciones"), gen == generacion else { return }
        arboles["conciliaciones"] = r.valor
        reconstruir("conciliaciones", enVivo: true)
        if let e = try? await Firebase.shared.leerConHuella(prefijo + "gastosExcel"), gen == generacion {
            arboles["gastosExcel"] = e.valor
            reconstruir("gastosExcel", enVivo: true)
        }
        guardarCacheLuego()
    }

    private func guardarCacheLuego() {
        tareaCache?.cancel()
        let copia = arboles
        let prueba = modoPrueba
        tareaCache = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            await Task.detached(priority: .utility) {
                guard JSONSerialization.isValidJSONObject(copia),
                      let d = try? JSONSerialization.data(withJSONObject: copia) else { return }
                try? d.write(to: Store.archivoCache(prueba: prueba),
                             options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }.value
        }
    }
}
