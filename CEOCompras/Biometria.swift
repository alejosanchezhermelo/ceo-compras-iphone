import LocalAuthentication

/// Face ID nativo: el mismo que usan las apps de bancos. Sin ventana intermedia.
enum Biometria {
    static func disponible() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Pide la cara; si falla, iOS ofrece el código del iPhone como alternativa.
    static func autenticar(_ motivo: String) async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Usar contraseña"
        do {
            return try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: motivo)
        } catch {
            return false
        }
    }
}
