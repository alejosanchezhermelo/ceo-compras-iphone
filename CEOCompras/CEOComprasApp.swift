import SwiftUI

@main
struct CEOComprasApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var escena

    init() {
        // Barra de arriba y de abajo con los colores y la letra de la PWA
        let fondo = UIColor(T.sf), borde = UIColor(T.bd)
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = fondo
        nav.shadowColor = borde
        nav.titleTextAttributes = [
            .font: UIFont(name: "CEOSyne-Bold", size: 17) ?? .boldSystemFont(ofSize: 17),
            .foregroundColor: UIColor(T.tx),
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = fondo
        tab.shadowColor = borde
        let letra = UIFont(name: "CEODMMono-Medium", size: 9) ?? .systemFont(ofSize: 9)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.titleTextAttributes = [.font: letra, .foregroundColor: UIColor(T.tx3)]
            item.normal.iconColor = UIColor(T.tx3)
            item.selected.titleTextAttributes = [.font: letra, .foregroundColor: UIColor(T.bl)]
            item.selected.iconColor = UIColor(T.bl)
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }

    var body: some Scene {
        WindowGroup {
            Raiz()
                .environment(store)
                .tint(T.bl)
                .preferredColorScheme(.light)   // la PWA no tiene modo oscuro
        }
        .onChange(of: escena) { _, nueva in store.cambioDeEscena(nueva) }
    }
}

/// Pestañas abajo (como la barra de la PWA) y el bloqueo encima: al volver, aparece donde estabas.
struct Raiz: View {
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            if store.haEntrado {
                ContenidoPestanas()
            }
            switch store.fase {
            case .adentro: EmptyView()
            case .bloqueada: PantallaLogin().transition(.opacity)
            case .necesitaCodigo: PantallaCodigo()
            }
        }
        .overlay(alignment: .bottom) {
            if let a = store.aviso {
                textoAviso(a)
                    .font(T.sans(13, .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(T.tx.opacity(0.92), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: a) {
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if store.aviso == a { store.aviso = nil }
                    }
                    .onTapGesture { store.aviso = nil }
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.fase)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.aviso)
        // Cada cartelito de "listo" vibra; el de urgente con un toque firme.
        .onChange(of: store.aviso) { _, nuevo in
            guard let nuevo else { return }
            if nuevo.hasPrefix("🔴") { Vibrar.firme() } else { Vibrar.listo() }
        }
        .task { await store.alAbrir() }
        .alert("¿Entrar con Face ID la próxima vez?", isPresented: Binding(
            get: { store.ofrecerFaceID },
            set: { store.ofrecerFaceID = $0 })) {
            Button("Activar") { Task { await store.activarFaceID() } }
            Button("Ahora no", role: .cancel) { store.noOfrecerFaceID() }
        } message: {
            Text("Abrís la app, mirás el teléfono y entrás. Se puede cambiar en Ajustes.")
        }
    }

    /// El cartelito con el ícono de Apple en lugar del emoji del principio.
    private func textoAviso(_ a: String) -> Text {
        if let p = IconoAviso.separar(a) {
            return Text("\(Text(Image(systemName: p.simbolo)).foregroundStyle(p.color))  \(p.texto)")
        }
        return Text(a)
    }
}


/// Las 6 pestañas de la PWA, en el mismo orden, con una barra propia abajo.
struct ContenidoPestanas: View {
    @Environment(Store.self) private var store
    @State private var pestana = 0
    @State private var visitadas: Set<Int> = [0]
    /// Cuántas veces se tocó cada pestaña (cada toque hace "saltar" su ícono).
    @State private var toques = [Int](repeating: 0, count: 6)
    @Namespace private var pastilla
    @Environment(\.accessibilityReduceMotion) private var sinMovimiento

    private let items: [(String, String)] = [
        ("ÓRDENES", "shippingbox"), ("ACTIVIDAD", "clock"), ("GASTOS", "chart.bar"),
        ("PRECIOS", "dollarsign.circle"), ("PROVEEDORES", "trophy"), ("FACTURAS", "doc.text.viewfinder"),
    ]

    var body: some View {
        // Si el teclado está abierto, la zona segura de abajo crece (más de ~120 puntos): ahí se esconde la barra.
        // Se mira el tamaño en cada momento (antes se usaban los avisos del teclado, que a veces no llegaban
        // al volver de la cámara o de imprimir, y la barra quedaba escondida).
        GeometryReader { g in
            pestanas(tecladoAbierto: g.safeAreaInsets.bottom > 120)
        }
    }

    /// Las 6 pantallas quedan armadas una encima de otra y la barra elige cuál se ve.
    /// NO se usa TabView: con más de 5 pestañas el iPhone mete las últimas en un menú "More"
    /// escondido, y la flechita de atrás de Facturas llevaba a ese menú en blanco (foto de Alejo, 23/10).
    /// Cada pantalla se arma la primera vez que se abre y después conserva lo que estabas haciendo.
    private func pestanas(tecladoAbierto: Bool) -> some View {
        ZStack {
            ForEach(0..<6, id: \.self) { i in
                if visitadas.contains(i) {
                    // La que se va se corre un poquito hacia un lado y la que entra viene del otro
                    // (del lado de la pestaña que tocaste), con un fundido rápido.
                    pantalla(i)
                        .opacity(pestana == i ? 1 : 0)
                        .offset(x: pestana == i || sinMovimiento ? 0 : (i < pestana ? -24 : 24))
                        .allowsHitTesting(pestana == i)
                        .accessibilityHidden(pestana != i)
                }
            }
        }
        // Ajustes ya no es una pestaña: se abre desde el engranaje de arriba a la derecha (v0.21).
        .sheet(isPresented: Binding(get: { store.mostrarAjustes }, set: { store.mostrarAjustes = $0 })) {
            PantallaAjustes()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tecladoAbierto {
                // El "➕ Nueva OC" va pegado ARRIBA de la barra (antes flotaba suelto y en iOS 26 quedaba
                // encimado con la barra de vidrio: foto de Alejo, 27/10).
                VStack(alignment: .trailing, spacing: 10) {
                    if pestana == 0 && store.puedeEditar {
                        BotonNuevaOC { store.pedirNuevaOC = true }
                            .padding(.trailing, 16)
                    }
                    barra
                }
            }
        }
    }

    @ViewBuilder private func pantalla(_ i: Int) -> some View {
        switch i {
        case 0: ListaOC(abrirProveedores: { ir(a: 4) })
        case 1: PantallaActividad()
        case 2: PantallaGastos()
        case 3: PantallaPrecios()
        case 4: PantallaProveedores()
        default: PantallaFacturas()
        }
    }

    /// En iOS 26: barra de vidrio flotante (Liquid Glass) y la pestaña elegida con una pastilla azul clara.
    /// Antes de iOS 26: la barra de siempre, pegada abajo (igual a `#mobileNav` de la PWA).
    @ViewBuilder private var barra: some View {
        if #available(iOS 26.0, *) {
            botonesBarra(vidrio: true)
                .padding(.horizontal, 6).padding(.vertical, 5)
                .glassEffect(.regular, in: Capsule())
                .padding(.horizontal, 10)
                .padding(.bottom, 2)
        } else {
            botonesBarra(vidrio: false)
                .background(T.sf.ignoresSafeArea(edges: .bottom))
                .overlay(alignment: .top) { Rectangle().fill(T.bd).frame(height: 1) }
        }
    }

    private func botonesBarra(vidrio: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let elegida = pestana == i
                Button { ir(a: i) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].1)
                            .font(.system(size: 18, weight: elegida ? .semibold : .regular))
                            .symbolEffect(.bounce, value: toques[i])
                        Text(items[i].0).font(T.mono(8, .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(elegida ? T.bl : (vidrio ? T.tx2 : T.tx3))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7).padding(.bottom, 4)
                    .background {
                        // La pastilla (o la rayita azul) es UNA sola que se desliza de una pestaña a la otra.
                        if elegida {
                            if vidrio {
                                Capsule().fill(T.bl.opacity(0.12))
                                    .matchedGeometryEffect(id: "pastilla", in: pastilla)
                            } else {
                                VStack {
                                    Rectangle().fill(T.bl).frame(height: 2)
                                        .matchedGeometryEffect(id: "pastilla", in: pastilla)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Cambia de pestaña con animación, salto del ícono y un toque muy leve.
    private func ir(a i: Int) {
        toques[i] += 1
        guard i != pestana else { return }
        Vibrar.seleccion()
        withAnimation(.snappy(duration: 0.3)) {
            visitadas.insert(i)
            pestana = i
        }
    }
}
