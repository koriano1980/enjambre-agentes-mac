import Foundation

enum Cripto {
    static func sha256(_ mensaje: [UInt8]) -> [UInt8] {
        var datos = mensaje
        let bitLength = UInt64(mensaje.count) * 8
        datos.append(0x80)
        while (datos.count % 64) != 56 { datos.append(0) }
        for desplazamiento in stride(from: 56, through: 0, by: -8) {
            datos.append(UInt8((bitLength >> desplazamiento) & 0xFF))
        }
        var h: [UInt32] = [
            0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
            0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
        ]
        let k: [UInt32] = [
            0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5, 0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
            0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3, 0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
            0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC, 0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
            0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7, 0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
            0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13, 0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
            0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3, 0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
            0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5, 0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
            0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208, 0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
        ]
        var offset = 0
        while offset < datos.count {
            var w = [UInt32](repeating: 0, count: 64)
            for i in 0..<16 {
                let j = offset + i * 4
                w[i] = (UInt32(datos[j]) << 24) | (UInt32(datos[j + 1]) << 16) | (UInt32(datos[j + 2]) << 8) | UInt32(datos[j + 3])
            }
            for i in 16..<64 {
                let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3)
                let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10)
                w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for i in 0..<64 {
                let s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
                let ch = (e & f) ^ ((~e) & g)
                let t1 = hh &+ s1 &+ ch &+ k[i] &+ w[i]
                let s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
                let maj = (a & b) ^ (a & c) ^ (b & c)
                let t2 = s0 &+ maj
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
            offset += 64
        }
        return h.flatMap { palabra in
            [UInt8((palabra >> 24) & 0xFF), UInt8((palabra >> 16) & 0xFF), UInt8((palabra >> 8) & 0xFF), UInt8(palabra & 0xFF)]
        }
    }

    static func hmacSHA256(clave: [UInt8], mensaje: [UInt8]) -> [UInt8] {
        let bloque = 64
        var claveBloque = clave
        if claveBloque.count > bloque { claveBloque = sha256(claveBloque) }
        if claveBloque.count < bloque { claveBloque.append(contentsOf: repeatElement(0, count: bloque - claveBloque.count)) }
        let ipad = claveBloque.map { $0 ^ 0x36 }
        let opad = claveBloque.map { $0 ^ 0x5C }
        return sha256(opad + sha256(ipad + mensaje))
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    public static func firma(secreto: String, mensaje: String) -> String {
        hex(hmacSHA256(clave: Array(secreto.utf8), mensaje: Array(mensaje.utf8)))
    }

    public static func firmaValida(secreto: String, mensaje: String, firmaHex: String) -> Bool {
        let esperada = Array(firma(secreto: secreto, mensaje: mensaje).utf8)
        let recibida = Array(firmaHex.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        guard esperada.count == recibida.count, !esperada.isEmpty else { return false }
        var diferencia: UInt8 = 0
        for (a, b) in zip(esperada, recibida) { diferencia |= a ^ b }
        return diferencia == 0
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x >> n) | (x << (32 - n))
    }
}
