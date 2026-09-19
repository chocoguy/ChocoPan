import Foundation

struct Anime4KPreset: Identifiable, Hashable {
    let name: String
    let shaders: [String]

    var id: String { name }
    var isOff: Bool { shaders.isEmpty }
}

extension Anime4KPreset {
    static let off = Anime4KPreset(name: "Off", shaders: [])

    static let all: [Anime4KPreset] = [
        off,
        Anime4KPreset(name: "A (HQ)", shaders: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_VL",
            "Anime4K_Upscale_CNN_x2_VL",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ]),
        Anime4KPreset(name: "B (HQ)", shaders: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_Soft_VL",
            "Anime4K_Upscale_CNN_x2_VL",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ]),
        Anime4KPreset(name: "C (HQ)", shaders: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Upscale_Denoise_CNN_x2_VL",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_M",
        ]),
        Anime4KPreset(name: "A (Fast)", shaders: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_M",
            "Anime4K_Upscale_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ]),
        Anime4KPreset(name: "B (Fast)", shaders: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Restore_CNN_Soft_M",
            "Anime4K_Upscale_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ]),
        Anime4KPreset(name: "C (Fast)", shaders: [
            "Anime4K_Clamp_Highlights",
            "Anime4K_Upscale_Denoise_CNN_x2_M",
            "Anime4K_AutoDownscalePre_x2",
            "Anime4K_AutoDownscalePre_x4",
            "Anime4K_Upscale_CNN_x2_S",
        ]),
    ]

    func resolve() -> (paths: [String], missing: [String]) {
        var paths: [String] = []
        var missing: [String] = []
        for shader in shaders {
            if let url = Self.url(forShader: shader) {
                paths.append(url.path)
            } else {
                missing.append(shader)
            }
        }
        return (paths, missing)
    }

    private static func url(forShader name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "glsl", subdirectory: "Anime4K_v4.0")
            ?? Bundle.main.url(forResource: name, withExtension: "glsl")
    }
}
