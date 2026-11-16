#if os(macOS)
import AVFoundation
import Speech

final class MotorVoz: NSObject, SFSpeechRecognizerDelegate {
    var alParcial: ((String) -> Void)?
    var alFinal: ((String) -> Void)?
    var alError: ((String) -> Void)?
    private let idioma: String
    private let enDispositivo: Bool
    private let maxCaracteres: Int
    private var reconocedor: SFSpeechRecognizer?
    private let sintetizador = AVSpeechSynthesizer()
    private let motor = AVAudioEngine()
    private var peticion: SFSpeechAudioBufferRecognitionRequest?
    private var tarea: SFSpeechRecognitionTask?
    private(set) var escuchando = false

    init(idioma: String, enDispositivo: Bool, maxCaracteres: Int) {
        self.idioma = idioma
        self.enDispositivo = enDispositivo
        self.maxCaracteres = maxCaracteres
        super.init()
        reconocedor = SFSpeechRecognizer(locale: Locale(identifier: idioma)) ?? SFSpeechRecognizer(locale: Locale(identifier: "es-ES"))
        reconocedor?.delegate = self
    }

    func pedirPermisos(completado: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { estado in
            DispatchQueue.main.async {
                guard estado == .authorized else {
                    self.alError?("El reconocimiento de voz no está autorizado.")
                    completado(false)
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { micro in
                    DispatchQueue.main.async {
                        if !micro { self.alError?("El micrófono no está autorizado.") }
                        completado(micro)
                    }
                }
            }
        }
    }

    func alternar() {
        escuchando ? terminar() : empezar()
    }

    func hablar(_ texto: String) {
        let recorte = String(texto.prefix(maxCaracteres))
        guard !recorte.isEmpty else { return }
        let frase = AVSpeechUtterance(string: recorte)
        frase.voice = AVSpeechSynthesisVoice(language: idioma) ?? AVSpeechSynthesisVoice(language: "es-ES")
        sintetizador.speak(frase)
    }

    private func empezar() {
        guard let reconocedor, reconocedor.isAvailable else {
            alError?("El reconocimiento en español no está disponible en este Mac.")
            return
        }
        peticion = SFSpeechAudioBufferRecognitionRequest()
        guard let peticion else { return }
        if enDispositivo, reconocedor.supportsOnDeviceRecognition {
            peticion.requiresOnDeviceRecognition = true
        }
        peticion.shouldReportPartialResults = true
        let nodo = motor.inputNode
        let formato = nodo.outputFormat(forBus: 0)
        guard formato.sampleRate > 0 else {
            alError?("No hay un micrófono utilizable.")
            return
        }
        nodo.removeTap(onBus: 0)
        nodo.installTap(onBus: 0, bufferSize: 1024, format: formato) { [weak self] buffer, _ in
            self?.peticion?.append(buffer)
        }
        motor.prepare()
        do { try motor.start() } catch {
            alError?("No pude abrir el micrófono.")
            return
        }
        escuchando = true
        tarea = reconocedor.recognitionTask(with: peticion) { [weak self] resultado, error in
            if let texto = resultado?.bestTranscription.formattedString {
                DispatchQueue.main.async { self?.alParcial?(texto) }
                if resultado?.isFinal == true {
                    DispatchQueue.main.async { self?.alFinal?(texto) }
                }
            }
            if error != nil, resultado == nil {
                DispatchQueue.main.async { self?.alError?("No entendí la frase. Prueba otra vez.") }
            }
        }
    }

    private func terminar() {
        escuchando = false
        motor.stop()
        motor.inputNode.removeTap(onBus: 0)
        peticion?.endAudio()
        tarea?.finish()
        peticion = nil
        tarea = nil
    }
}
#endif
