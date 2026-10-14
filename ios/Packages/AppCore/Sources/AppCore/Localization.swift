import Foundation

/// AppCore stays plain English (it builds and tests on Linux). The app and
/// the widgets translate its strings at runtime by looking the English text
/// up in their string catalogs; `scripts/export-core-strings.py` registers
/// those keys for translators.
public enum L10n {
    public static func core(_ english: String, bundle: Bundle = .main) -> String {
        bundle.localizedString(forKey: english, value: english, table: nil)
    }
}
