import SwiftUI

@main
struct CEOComprasApp: App {
    @State private var store = Store()
    @Environment(\.scenePhase) private var escena

    var body: some Scene {
        WindowGroup {
            Raiz()
                .environment(store)
                .tint(Color.ceoAzul)
        }
        .onChange(of: escena) { _, nueva in store.cambioDeEscena(nueva) }
    }
}

/// La lista queda armada debajo y el bloqueo va encima: al volver, aparece donde estabas.
struct Raiz: View {
    @Environment(Store.self) private var store

    var body: some View {
        ZStack {
            if store.haEntrado { ListaOC() }
            switch store.fase {
            case .adentro: EmptyView()
            case .bloqueada: PantallaLogin().transition(.opacity)
            case .necesitaCodigo: PantallaCodigo()
            }
        }
        .overlay(alignment: .bottom) {
            if let a = store.aviso {
                Text(a)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.horizontal, 20)
                    .padding(.bottom, 90)
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
