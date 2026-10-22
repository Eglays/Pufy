import SwiftUI
import AVFoundation

struct CustomCameraView: View {
    var onImageCaptured: (Data) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @StateObject private var model = CameraModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if model.isPermissionGranted {
                // Canlı Kamera Önizlemesi
                CameraPreview(session: model.session)
                    .ignoresSafeArea()
                
                // Sade Kamera Arayüzü
                VStack {
                    // Üst Bar: Kapatma Butonu
                    HStack {
                        Button(action: {
                            presentationMode.wrappedValue.dismiss()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.4))
                                .clipShape(Circle())
                        }
                        .padding(.leading, 20)
                        .padding(.top, 10)
                        
                        Spacer()
                    }
                    
                    Spacer()
                    
                    // Alt Bar: Deklanşör (Çekim) Butonu
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                            model.capturePhoto { data in
                                onImageCaptured(data)
                                presentationMode.wrappedValue.dismiss()
                            }
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 70, height: 70)
                                Circle()
                                    .stroke(Color.pufyPrimary, lineWidth: 4)
                                    .frame(width: 82, height: 82)
                            }
                        }
                        .disabled(model.isCapturing)
                        
                        Spacer()
                    }
                    .padding(.bottom, 30)
                }
            } else {
                // İzin Yoksa veya Yükleniyorsa
                VStack(spacing: 20) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    Text("Kamera İzni Gerekiyor")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Lütfen ayarlardan Pufy uygulamasının kameraya erişmesine izin verin.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    Button("Ayarları Aç") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .fontWeight(.bold)
                    .foregroundColor(Color.pufyOnPrimary)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.pufyPrimary)
                    .cornerRadius(12)
                    
                    Button("İptal") {
                        presentationMode.wrappedValue.dismiss()
                    }
                    .foregroundColor(.gray)
                    .padding(.top, 10)
                }
            }
        }
        .onAppear {
            model.checkPermission()
        }
        .onDisappear {
            model.stopSession()
        }
    }
}

// MARK: - Camera Model (AVFoundation Koordinatörü)

class CameraModel: NSObject, ObservableObject {
    @Published var isPermissionGranted = false
    @Published var isCapturing = false
    
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var isSessionRunning = false
    private var onCaptureCompletion: ((Data) -> Void)?
    
    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.isPermissionGranted = true
            self.setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.isPermissionGranted = granted
                    if granted {
                        self.setupSession()
                    }
                }
            }
        default:
            self.isPermissionGranted = false
        }
    }
    
    private func setupSession() {
        guard !isSessionRunning else { return }
        
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // Kamera Girişi
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            print("Kamera cihazı bulunamadı.")
            session.commitConfiguration()
            return
        }
        
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        // Fotoğraf Çıkışı
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        session.commitConfiguration()
        
        DispatchQueue.global(qos: .background).async {
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isSessionRunning = true
            }
        }
    }
    
    func capturePhoto(completion: @escaping (Data) -> Void) {
        guard isSessionRunning else { return }
        self.isCapturing = true
        self.onCaptureCompletion = completion
        
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func stopSession() {
        if isSessionRunning {
            DispatchQueue.global(qos: .background).async {
                self.session.stopRunning()
            }
        }
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        self.isCapturing = false
        
        guard error == nil else {
            print("Fotoğraf çekilirken hata oluştu: \(error!.localizedDescription)")
            return
        }
        
        guard let data = photo.fileDataRepresentation() else {
            print("Fotoğraf veriye dönüştürülemedi.")
            return
        }
        
        // Çekilen görseli düzgün oryantasyonda ve optimize boyutta tutmak için UIImage üzerinden geçirelim
        if let originalImage = UIImage(data: data),
           let compressedData = originalImage.jpegData(compressionQuality: 0.8) {
            onCaptureCompletion?(compressedData)
        } else {
            onCaptureCompletion?(data)
        }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

class PreviewView: UIView {
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
}
