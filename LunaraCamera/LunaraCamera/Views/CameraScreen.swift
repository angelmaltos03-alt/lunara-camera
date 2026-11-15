import SwiftUI

struct CameraScreen: View {
    @StateObject private var camera = CameraManager()
    @State private var enhancedImage: UIImage?
    @State private var detectedScene: PhotoScene = .general
    @State private var isProcessing = false
    @State private var statusText: String?
    @State private var showOriginal = false
    private let analyzer = SceneAnalyzer()
    private let processor = PhotoProcessor()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let original = camera.capturedImage { reviewView(original: original) }
            else if camera.isAuthorized {
                CameraPreview(session: camera.session).ignoresSafeArea()
                cameraOverlay
            } else { permissionView }
        }
        .onAppear { camera.requestAccessAndConfigure() }
        .onDisappear { camera.stop() }
        .onChange(of: camera.capturedImage) { _, image in if let image { process(image) } }
        .alert("LUNARA", isPresented: Binding(get: { camera.errorMessage != nil }, set: { if !$0 { camera.errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) { camera.errorMessage = nil }
        } message: { Text(camera.errorMessage ?? "") }
    }
    private var cameraOverlay: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("LUNARA").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("OPEN SOURCE · ADAPTIVE CAMERA").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.white.opacity(0.7))
                }
                Spacer(); Image(systemName: "sparkles").font(.title2).foregroundStyle(.mint)
            }.padding(.horizontal, 24).padding(.top, 18)
            Spacer()
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    Text(String(format: "ZOOM  %.1fx", Double(camera.zoomFactor)))
                    Spacer()
                    if camera.isMoonDetected { Label("LUNA DETECTADA · MOON AI", systemImage: "moon.stars.fill").foregroundStyle(.yellow) }
                }.font(.system(size: 10, weight: .semibold)).tracking(0.8)
                Slider(value: Binding(get: { Double(camera.zoomFactor) }, set: { camera.setZoom(CGFloat($0)) }), in: 1...Double(max(1.0, camera.maximumZoom))).tint(.mint)
                HStack(spacing: 8) {
                    Circle().fill(.mint).frame(width: 7, height: 7)
                    Text("AUTO · ESCENA ADAPTATIVA")
                }.font(.system(size: 10, weight: .semibold)).tracking(0.8)
            }.padding(.horizontal, 14).padding(.vertical, 10).background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
            Spacer()
            HStack {
                Image(systemName: "photo.on.rectangle").font(.title2).frame(width: 54, height: 54).foregroundStyle(.white.opacity(0.4))
                Spacer()
                Button { camera.capture() } label: {
                    Circle().stroke(.white, lineWidth: 5).frame(width: 76, height: 76).overlay(Circle().fill(.white).frame(width: 62, height: 62))
                }
                Spacer()
                Image(systemName: "arrow.triangle.2.circlepath.camera").font(.title2).frame(width: 54, height: 54).foregroundStyle(.white.opacity(0.4))
            }.padding(.horizontal, 30).padding(.bottom, 28)
        }.foregroundStyle(.white)
    }
    private var permissionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill").font(.system(size: 48)).foregroundStyle(.mint)
            Text("Permite el acceso a la cámara").font(.title2.bold())
            Text("LUNARA necesita la cámara para capturar y optimizar tus fotografías.").multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.7))
            Button("Volver a intentar") { camera.requestAccessAndConfigure() }.buttonStyle(.borderedProminent)
        }.padding(32).foregroundStyle(.white)
    }
    private func reviewView(original: UIImage) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button("Volver a cámara") { camera.capturedImage = nil; enhancedImage = nil }
                Spacer(); Text("RESULTADO LUNARA").font(.caption.bold()).tracking(1.2)
            }.padding()
            Spacer(minLength: 8)
            if let result = enhancedImage {
                Image(uiImage: showOriginal ? original : result).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 18)).padding(.horizontal, 12)
                HStack {
                    Text(showOriginal ? "ORIGINAL" : "LUNARA")
                    Spacer()
                    Text(detectedScene == .moon ? "MOON AI · Luna detectada" : "Escena: \(detectedScene.rawValue)")
                }.font(.caption.bold()).foregroundStyle(.white.opacity(0.75)).padding(.horizontal, 18).padding(.top, 12)
                Button { showOriginal.toggle() } label: {
                    Label(showOriginal ? "Ver optimizada" : "Comparar con original", systemImage: "arrow.left.arrow.right").frame(maxWidth: .infinity).padding()
                }.buttonStyle(.bordered).padding(.horizontal)
                Button { Task { await saveResult(result) } } label: {
                    Label("Guardar fotografía optimizada", systemImage: "square.and.arrow.down").font(.headline).frame(maxWidth: .infinity).padding()
                }.buttonStyle(.borderedProminent).tint(.mint).padding(.horizontal).padding(.bottom, 22)
            } else {
                ProgressView(isProcessing ? "Analizando y optimizando..." : "Preparando fotografía...").tint(.mint)
                Spacer()
            }
            if let statusText { Text(statusText).font(.footnote).foregroundStyle(.mint).padding(.bottom, 12) }
        }.foregroundStyle(.white)
    }
    private func process(_ image: UIImage) {
        isProcessing = true; enhancedImage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let scene = analyzer.detect(in: image)
            let result = processor.enhance(image, scene: scene)
            DispatchQueue.main.async {
                detectedScene = scene; enhancedImage = result; isProcessing = false
            }
        }
    }
    private func saveResult(_ image: UIImage) async {
        do { try await PhotoLibrarySaver.save(image); statusText = "Fotografía guardada en Fotos." }
        catch { statusText = error.localizedDescription }
    }
}