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
                TabView {
                    ListaOC()
                        .tabItem { Label("ÓRDENES", systemImage: "shippingbox") }
                    PantallaActividad()
                        .tabItem { Label("ACTIVIDAD", systemImage: "clock") }
                    PantallaAjustes()
                        .tabItem { Label("AJUSTES", systemImage: "gearshape") }
                }
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
