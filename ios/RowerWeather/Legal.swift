import SwiftUI

/// The operator's details for the legal notice (Impressum, § 5 DDG) and the
/// privacy policy. Placeholders until the owner fills them in before release.
enum LegalInfo {
    static let name = "[Vorname Nachname]"
    /// A street address where legal mail can be served (an address service is fine), not a P.O. box.
    static let address = ["[Straße Nr.]", "[PLZ Ort]", "Deutschland"]
    static let email = "[kontakt@rowfrog.com]"
    /// The second direct way to reach the operator: a phone number or a contact form.
    static let secondContact = "[Telefon oder Kontaktformular]"
    static let privacyURL = URL(string: "https://rowfrog.com/privacy")!
    static let impressumURL = URL(string: "https://rowfrog.com/impressum")!
}

/// The legal notice. It is the same in both languages, as German law asks for it in German.
struct ImpressumView: View {
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text(LegalInfo.name).font(.headline)
                    ForEach(LegalInfo.address, id: \.self) { Text($0) }
                }
                LabeledContent("E-Mail", value: LegalInfo.email)
                LabeledContent(tr("Contact"), value: LegalInfo.secondContact)
            } header: {
                Text("Angaben gemäß § 5 DDG")
            }
            Section {
                Text("Verantwortlich für den Inhalt nach § 18 Abs. 2 MStV: \(LegalInfo.name), Anschrift wie oben.")
                Text("Verbraucherstreitbeilegung: Wir sind nicht bereit und nicht verpflichtet, an Streitbeilegungsverfahren vor einer Verbraucherschlichtungsstelle teilzunehmen.")
            }
            .font(.subheadline)
            Section {
                Link(destination: LegalInfo.impressumURL) {
                    Label("rowfrog.com/impressum", systemImage: "safari")
                }
            }
        }
        .navigationTitle(tr("Legal notice"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The privacy policy in short, with a link to the full text on the website.
struct PrivacySummaryView: View {
    private var points: [(symbol: String, text: String)] {
        [
            ("person.crop.circle.badge.xmark", tr("No account, no ads, no tracking or analytics.")),
            ("location", tr("Your location is only used on your phone, to suggest clubs near you, and is never sent anywhere.")),
            ("iphone", tr("Your settings, clubs, boats, photos and your acceptance of the safety notice stay on your phone.")),
            ("server.rack", tr("Forecasts come from api.rowfrog.com (Cloudflare and GitHub). We only count per day how often each club and lake is loaded, never who loaded it.")),
            ("cloud.rain", tr("The rain radar loads map pictures directly from the Deutscher Wetterdienst; maps come from Apple.")),
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(points, id: \.text) { point in
                    Label {
                        Text(point.text)
                    } icon: {
                        Image(systemName: point.symbol).foregroundStyle(.blue)
                    }
                }
            } footer: {
                Text(tr("Responsible: %@, %@.", LegalInfo.name, LegalInfo.email))
            }
            Section {
                Link(destination: LegalInfo.privacyURL) {
                    Label(tr("Full privacy policy"), systemImage: "safari")
                }
            }
        }
        .navigationTitle(tr("Privacy"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
