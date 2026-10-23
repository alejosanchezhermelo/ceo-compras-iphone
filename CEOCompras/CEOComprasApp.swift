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


/// Las 6 pestañas de la PWA, en el mismo orden, con una barra propia abajo
/// (con el TabView común el iPhone mete la sexta en un menú "Más").
struct ContenidoPestanas: View {
    @State private var pestana = 0
    @State private var tecladoAbierto = false

    private let items: [(String, String)] = [
        ("ÓRDENES", "shippingbox"), ("ACTIVIDAD", "clock"), ("AJUSTES", "gearshape"),
        ("PRECIOS", "dollarsign.circle"), ("PROVEEDORES", "trophy"), ("FACTURAS", "doc.text.viewfinder"),
    ]

    var body: some View {
        TabView(selection: $pestana) {
            ListaOC().tag(0).toolbar(.hidden, for: .tabBar)
            PantallaActividad().tag(1).toolbar(.hidden, for: .tabBar)
            PantallaAjustes().tag(2).toolbar(.hidden, for: .tabBar)
            PantallaPrecios().tag(3).toolbar(.hidden, for: .tabBar)
            PantallaProveedores().tag(4).toolbar(.hidden, for: .tabBar)
            PantallaFacturas().tag(5).toolbar(.hidden, for: .tabBar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tecladoAbierto { barra }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in tecladoAbierto = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in tecladoAbierto = false }
    }

    private var barra: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                let elegida = pestana == i
                Button { pestana = i } label: {
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
