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
                Text(a)
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
        .animation(.easeOut(duration: 0.25), value: store.aviso)
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
}


/// Las 6 pestañas de la PWA, en el mismo orden, con una barra propia abajo.
struct ContenidoPestanas: View {
    @State private var pestana = 0
    @State private var visitadas: Set<Int> = [0]

    private let items: [(String, String)] = [
        ("ÓRDENES", "shippingbox"), ("ACTIVIDAD", "clock"), ("AJUSTES", "gearshape"),
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
                    pantalla(i)
                        .opacity(pestana == i ? 1 : 0)
                        .allowsHitTesting(pestana == i)
                        .accessibilityHidden(pestana != i)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tecladoAbierto { barra }
        }
    }

    @ViewBuilder private func pantalla(_ i: Int) -> some View {
        switch i {
        case 0: ListaOC(abrirProveedores: { visitadas.insert(4); pestana = 4 })
        case 1: PantallaActividad()
        case 2: PantallaAjustes()
        case 3: PantallaPrecios()
        case 4: PantallaProveedores()
        default: PantallaFacturas()
        }
    }

    private var barra: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let elegida = pestana == i
                Button { visitadas.insert(i); pestana = i } label: {
                    VStack(spacing: 3) {
                        Image(systemName: items[i].1).font(.system(size: 18, weight: elegida ? .semibold : .regular))
                        Text(items[i].0).font(T.mono(8, .medium)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .foregroundStyle(elegida ? T.bl : T.tx3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 7).padding(.bottom, 4)
                    .background(alignment: .top) {
                        if elegida { Rectangle().fill(T.bl).frame(height: 2) }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(T.sf.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(T.bd).frame(height: 1) }
    }
}
