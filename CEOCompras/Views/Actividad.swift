import SwiftUI

/// Pestaña Actividad (`renderActividad` de la PWA): todo el historial, del más nuevo al más viejo.
struct PantallaActividad: View {
    @Environment(Store.self) private var store
    @State private var cuantos = 150

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if store.modoPrueba { FranjaPrueba() }
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Actividad reciente").font(T.syne(15)).foregroundStyle(T.tx)
                            .padding(.bottom, 6)
                        if store.eventos.isEmpty {
                            Text("Sin actividad aún").font(T.sans(13)).foregroundStyle(T.tx3).padding(.vertical, 12)
                        }
                        ForEach(store.eventos.prefix(cuantos)) { ev in
                            FilaEvento(ev: ev)
                        }
                        if store.eventos.count > cuantos {
                            Button("Ver más") { cuantos += 150 }
                                .buttonStyle(BotonPWA(tipo: .blanco))
                                .padding(.top, 10)
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .tarjeta()
                }
                .padding(14)
            }
            .background(T.bg)
            .refreshable { await store.reconectar() }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { EncabezadoPedidos() } }
        }
    }
}

/// Un renglón de historial con el punto de color (`.hi` / `.hd` de la PWA).
struct FilaEvento: View {
    let ev: EventoOC
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(colorEvento(ev.tipo)).frame(width: 8, height: 8).padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(ev.texto).font(T.sans(13)).foregroundStyle(T.tx)
                Text(Formato.fechaHora(ev.ts)).font(T.mono(10)).foregroundStyle(T.tx3)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(T.bd).frame(height: 1) }
    }
}
