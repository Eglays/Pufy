import Foundation

enum LegalLinks {
    static let base = "https://eglays.github.io"
    static let supportEmail = "ahmt.yacel@gmail.com"
    static let reportEndpoint: String? = nil

    static var isTurkish: Bool {
        !AppLanguage.isEnglish
    }

    static var privacyURLString: String {
        base + (isTurkish ? "/tr/gizlilik/" : "/en/privacy/")
    }

    static var termsURLString: String {
        base + (isTurkish ? "/tr/kosullar/" : "/en/terms/")
    }

    static var deletionURLString: String {
        base + (isTurkish ? "/tr/veri-silme/" : "/en/delete-data/")
    }

    static var supportURLString: String {
        base + (isTurkish ? "/tr/destek/" : "/en/support/")
    }

    static var privacyURL: URL? { URL(string: privacyURLString) }
    static var termsURL: URL? { URL(string: termsURLString) }
    static var deletionURL: URL? { URL(string: deletionURLString) }
    static var supportURL: URL? { URL(string: supportURLString) }
}
