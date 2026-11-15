import SwiftUI

struct CameraScreen: View {
    @StateObject private var camera = CameraManager()
    @State private var enhancedImage: UIImage?
    @State private var detectedScene: PhotoScene = .general
    @State private var isProcessing = false
    @State private var statusText: String?
    @State private var showOriginal = false
    @State private var editingMode: PhotoEditMode = .auto
    @State private var selectedLook: PhotoLook = .natural
    @State private var lookIntensity = 0.55
    @State private var adjustments = PhotoAdjustments()

    private let analyzer = SceneAnalyzer()
    private let processor = PhotoProcessor()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let original = camera.capturedImage {
                reviewView(original: original)
            } else if camera.isAuthorized {
                CameraPreview(camera: camera, mode: editingMode, look: selectedLook, intensity: lookIntensity, adjustments: adjustments).ignoresSafeArea()
                cameraOverlay
            } else {
                permissionView
            }
        }
        .onAppear { camera.requestAccessAndConfigure() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedImage) { _, image in
            if let image { resetAndProcess(image) }
        }
        .alert("LUNARA", isPresented: Binding(
            get: { camera.errorMessage != nil },
            set: { if !$0 { camera.errorMessage = nil } }
        )) {
            Button("Aceptar", role: .cancel) { camera.errorMessage = nil }
        } message: {
            Text(camera.errorMessage ?? "")
        }
    }

    private var cameraOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LUNARA")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("COMPUTATIONAL PHOTOGRAPHY")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.mint)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        camera.isMoonModeEnabled.toggle()
                        if camera.isMoonModeEnabled { camera.setZoom(min(max(camera.zoomFactor, 4.0), camera.maximumZoom)) }
                    } label: {
                        Label(camera.isMoonModeEnabled ? "MOON ON" : "MOON MODE", systemImage: "moon.stars.fill")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(camera.isMoonModeEnabled ? Color.yellow.opacity(0.25) : Color.white.opacity(0.12), in: Capsule())
                            .foregroundStyle(camera.isMoonModeEnabled ? .yellow : .white)
                    }
                    Spacer()
                    Image(systemName: "magnifyingglass")
                    Text(String(format: "ZOOM  %.1fx", Double(camera.zoomFactor)))
                    Spacer()
                    if camera.isMoonDetected {
                        Label("LUNA DETECTADA", systemImage: "moon.stars.fill")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)

                Slider(
                    value: Binding(
                        get: { Double(camera.zoomFactor) },
                        set: { camera.setZoom(CGFloat($0)) }
                    ),
                    in: 1...Double(max(1.0, camera.maximumZoom))
                )
                .tint(.mint)

                Picker("Cámara", selection: $editingMode) {
                    Text("AUTO").tag(PhotoEditMode.auto)
                    Text("PRO").tag(PhotoEditMode.pro)
                }
                .pickerStyle(.segmented)
                .onChange(of: editingMode) { _, mode in
                    camera.manualControlsEnabled = mode == .pro
                }

                if editingMode == .pro {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text("ISO")
                            Spacer()
                            Text("\(Int(camera.isoValue))").monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { camera.isoValue },
                            set: { camera.setManualExposure(seconds: camera.shutterSeconds, iso: $0) }
                        ), in: camera.minimumISO...max(camera.minimumISO + 1, camera.maximumISO))

                        HStack {
                            Text("Obturación")
                            Spacer()
                            Text(String(format: "1/%.0f s", 1 / max(camera.shutterSeconds, 0.0001))).monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { camera.shutterSeconds },
                            set: { camera.setManualExposure(seconds: $0, iso: camera.isoValue) }
                        ), in: camera.minimumShutterSeconds...max(camera.minimumShutterSeconds + 0.0001, camera.maximumShutterSeconds))

                        HStack {
                            Text("Enfoque manual")
                            Spacer()
                            Text(camera.focusPosition > 0.97 ? "Infinito" : String(format: "%.2f", camera.focusPosition)).monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { camera.focusPosition },
                            set: { camera.setManualFocus($0) }
                        ), in: 0...1)

                        HStack {
                            Text("Balance de blancos")
                            Spacer()
                            Text("\(Int(camera.whiteBalanceTemperature)) K").monospacedDigit()
                        }
                        Slider(value: Binding(
                            get: { camera.whiteBalanceTemperature },
                            set: { camera.setWhiteBalance(temperature: $0) }
                        ), in: 2500...9000)
                    }
                    .font(.caption.weight(.medium))
                    .tint(.mint)
                }

                HStack(spacing: 8) {
                    Circle().fill(.mint).frame(width: 7, height: 7)
                    Text(camera.isMoonModeEnabled ? "EXPOSICIÓN LUNAR · ISO MÍNIMO" : (editingMode == .pro ? "PRO · CONTROLES DEL SENSOR" : "AUTO · ESCENA ADAPTATIVA"))
                }
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            HStack {
                Image(systemName: "photo.on.rectangle")
                    .font(.title2)
                    .frame(width: 54, height: 54)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button { camera.isMoonModeEnabled ? camera.captureMoonBurst() : camera.capture() } label: {
                    Circle()
                        .stroke(.white, lineWidth: 5)
                        .frame(width: 76, height: 76)
                        .overlay(Circle().fill(.white).frame(width: 62, height: 62))
                }
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.title2)
                    .frame(width: 54, height: 54)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 30)
            .padding(.bottom, 28)
        }
        .foregroundStyle(.white)
    }

    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.mint)
            Text("Permite el acceso a la cámara")
                .font(.title2.bold())
            Text("LUNARA necesita la cámara para capturar y optimizar tus fotografías.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.7))
            Button("Volver a intentar") { camera.requestAccessAndConfigure() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .foregroundStyle(.white)
    }

    private func reviewView(original: UIImage) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button("Volver a cámara") {
                        camera.capturedImage = nil
                        enhancedImage = nil
                        statusText = nil
                        camera.moonStackSummary = nil
                    }
                    Spacer()
                    Text("RESULTADO LUNARA")
                        .font(.caption.bold())
                        .tracking(1.2)
                }
                .padding(.top, 8)

                if let result = enhancedImage {
                    Image(uiImage: showOriginal ? original : result)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 380)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    HStack {
                        Text(showOriginal ? "ORIGINAL" : "LUNARA")
                        Spacer()
                        Text("Escena: \(detectedScene.rawValue)")
                    }
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.75))

                    editorPanel

                    Button {
                        showOriginal.toggle()
                    } label: {
                        Label(
                            showOriginal ? "Ver optimizada" : "Comparar con original",
                            systemImage: "arrow.left.arrow.right"
                        )
                        .frame(maxWidth: .infinity)
                        .padding()
                    }
                    .buttonStyle(.bordered)

                    Button {
                        Task { await saveResult(result) }
                    } label: {
                        Label("Guardar fotografía optimizada", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.mint)

                    if let moonStackSummary = camera.moonStackSummary {
                        Text(moonStackSummary)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.mint)
                    }

                    if let statusText {
                        Text(statusText)
                            .font(.footnote)
                            .foregroundStyle(.mint)
                    }
                } else {
                    ProgressView(isProcessing ? "Analizando y optimizando..." : "Preparando fotografía...")
                        .tint(.mint)
                        .padding(.vertical, 50)
                }

                Text("En modo lunar se capturan hasta siete fotogramas con exposición corta e ISO mínimo. LUNARA puntúa nitidez, alinea los fotogramas registrables y promedia la información coincidente. Si la alineación falla, conserva la toma más nítida. No se inventan cráteres.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 18)
            }
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
        }
    }

    private var editorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MODO DE EDICIÓN")
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))

            Picker("Modo", selection: $editingMode) {
                ForEach(PhotoEditMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: editingMode) { _, _ in reprocessCaptured() }

            Text("ESTILO")
                .font(.caption.bold())
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))

            Picker("Estilo", selection: $selectedLook) {
                ForEach(PhotoLook.allCases) { look in
                    Text(look.title).tag(look)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: selectedLook) { _, _ in reprocessCaptured() }

            if selectedLook != .natural {
                sliderRow(
                    "Intensidad del estilo",
                    value: $lookIntensity,
                    range: 0...1,
                    valueText: "\(Int(lookIntensity * 100))%"
                )
            }

            if editingMode == .pro {
                Divider().overlay(.white.opacity(0.15))
                Text("AJUSTES MANUALES")
                    .font(.caption.bold())
                    .tracking(1)
                    .foregroundStyle(.mint)

                sliderRow("Exposición", value: $adjustments.exposureEV, range: -1.5...1.5, valueText: String(format: "%+.2f EV", adjustments.exposureEV))
                sliderRow("Contraste", value: $adjustments.contrast, range: -0.30...0.30, valueText: String(format: "%+.2f", adjustments.contrast))
                sliderRow("Saturación", value: $adjustments.saturation, range: -0.40...0.40, valueText: String(format: "%+.2f", adjustments.saturation))
                sliderRow("Temperatura", value: $adjustments.warmth, range: -1...1, valueText: String(format: "%+.2f", adjustments.warmth))
                sliderRow("Definición", value: $adjustments.sharpness, range: 0...0.8, valueText: String(format: "%.2f", adjustments.sharpness))

                Button("Restablecer ajustes PRO") {
                    adjustments = PhotoAdjustments()
                    selectedLook = .natural
                    lookIntensity = 0.55
                    reprocessCaptured()
                }
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.mint)
            }
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
    }

    private func sliderRow(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
            }
            .font(.caption)
            Slider(value: value, in: range) { isEditing in
                if !isEditing { reprocessCaptured() }
            }
            .tint(.mint)
        }
    }

    private func resetAndProcess(_ image: UIImage) {
        editingMode = .auto
        selectedLook = .natural
        lookIntensity = 0.55
        adjustments = PhotoAdjustments()
        showOriginal = false
        statusText = nil
        process(image, scene: camera.isMoonModeEnabled ? .moon : nil, mode: .auto, look: .natural, intensity: 0.55, adjustments: PhotoAdjustments())
    }

    private func reprocessCaptured() {
        guard let image = camera.capturedImage else { return }
        process(
            image,
            scene: detectedScene,
            mode: editingMode,
            look: selectedLook,
            intensity: lookIntensity,
            adjustments: adjustments
        )
    }

    private func process(
        _ image: UIImage,
        scene fixedScene: PhotoScene? = nil,
        mode: PhotoEditMode,
        look: PhotoLook,
        intensity: Double,
        adjustments: PhotoAdjustments
    ) {
        isProcessing = true
        let analyzer = self.analyzer
        let processor = self.processor

        DispatchQueue.global(qos: .userInitiated).async {
            let scene = fixedScene ?? analyzer.detect(in: image)
            let result = processor.enhance(
                image,
                scene: scene,
                mode: mode,
                look: look,
                intensity: intensity,
                adjustments: adjustments
            )
            DispatchQueue.main.async {
                detectedScene = scene
                enhancedImage = result
                isProcessing = false
            }
        }
    }

    private func saveResult(_ image: UIImage) async {
        do {
            try await PhotoLibrarySaver.save(image)
            statusText = "Fotografía guardada en Fotos."
        } catch {
            statusText = error.localizedDescription
        }
    }
}
