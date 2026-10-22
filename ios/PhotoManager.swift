import Foundation
import Photos
import UIKit

struct RecentPhoto: Identifiable {
    let id: String          // PHAsset.localIdentifier
    let thumbnail: UIImage
}

class PhotoManager: ObservableObject {
    static let shared = PhotoManager()

    @Published var isAuthorized: Bool = false
    @Published var recentPhotos: [RecentPhoto] = []

    private let queue = DispatchQueue(label: "com.pufy.photos", qos: .userInitiated)

    private init() {
        // Açılışta izin İSTEME (HIG: izin, özellik ilk kullanıldığında istenir) — sadece durumu oku
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        isAuthorized = status == .authorized || status == .limited
    }

    /// Fotoğraf menüsü açılınca çağrılır: izin yoksa ister, varsa son fotoğrafları getirir
    func checkAuthorization() {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        switch status {
        case .authorized, .limited:
            isAuthorized = true
            fetchRecentPhotos()
        case .notDetermined:
            requestAuthorization()
        default:
            isAuthorized = false
        }
    }

    func requestAuthorization() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] status in
            DispatchQueue.main.async {
                let granted = status == .authorized || status == .limited
                self?.isAuthorized = granted
                if granted { self?.fetchRecentPhotos() }
            }
        }
    }

    /// Küçük resimler arka planda hazırlanır (eskiden ana thread'de senkron yükleniyordu → menü açılırken takılma)
    func fetchRecentPhotos(count: Int = 12) {
        guard isAuthorized else { return }
        queue.async { [weak self] in
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            options.fetchLimit = count
            let assets = PHAsset.fetchAssets(with: .image, options: options)

            let request = PHImageRequestOptions()
            request.isSynchronous = true
            request.deliveryMode = .opportunistic
            request.resizeMode = .fast
            request.isNetworkAccessAllowed = true

            var photos: [RecentPhoto] = []
            let side: CGFloat = 240   // 80pt @3x
            assets.enumerateObjects { asset, _, _ in
                PHImageManager.default().requestImage(for: asset,
                                                      targetSize: CGSize(width: side, height: side),
                                                      contentMode: .aspectFill,
                                                      options: request) { image, _ in
                    if let image { photos.append(RecentPhoto(id: asset.localIdentifier, thumbnail: image)) }
                }
            }
            DispatchQueue.main.async { self?.recentPhotos = photos }
        }
    }

    /// Seçilen fotoğrafın yapay zekaya gidecek kaliteli (ama küçültülmüş) JPEG verisi.
    /// Eskiden 300px küçük resim gönderiliyordu → model detayları okuyamıyordu.
    func loadImageData(for assetID: String, completion: @escaping (Data?) -> Void) {
        queue.async {
            guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let request = PHImageRequestOptions()
            request.isSynchronous = true
            request.deliveryMode = .highQualityFormat
            request.isNetworkAccessAllowed = true

            var result: Data?
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: CGSize(width: 1600, height: 1600),
                                                  contentMode: .aspectFit,
                                                  options: request) { image, _ in
                if let image { result = ImageUtils.preparedJPEG(from: image) }
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}
