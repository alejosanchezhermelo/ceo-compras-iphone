import Foundation
import Security

/// Llavero del iPhone (cifrado por el sistema). Si por algún motivo el llavero no
/// responde, se guarda en las preferencias de la app, que también son privadas de la app.
enum Keychain {
    private static let servicio = "com.alejosanchez.ceocompras"

    static func get(_ clave: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var salida: AnyObject?
        if SecItemCopyMatching(q as CFDictionary, &salida) == errSecSuccess,
           let d = salida as? Data, let s = String(data: d, encoding: .utf8) {
            return s
        }
        return UserDefaults.standard.string(forKey: "kc." + clave)
    }

    static func set(_ clave: String, _ valor: String?) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: servicio,
            kSecAttrAccount as String: clave,
        ]
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: "kc." + clave)
        guard let valor else { return }
        var nuevo = base
        nuevo[kSecValueData as String] = Data(valor.utf8)
        nuevo[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if SecItemAdd(nuevo as CFDictionary, nil) != errSecSuccess {
            UserDefaults.standard.set(valor, forKey: "kc." + clave)
        }
    }
}
