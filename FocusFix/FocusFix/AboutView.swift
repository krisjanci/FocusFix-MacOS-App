// MARK: - FF: RELEASE
// Public support and offline license access, available without recording or permissions.
import SwiftUI

enum AppLinks {
    static let support = URL(string: "https://github.com/krisjanci/FocusFix-MacOS-App/issues")!
    static var source: URL {
        let root = "https://github.com/krisjanci/FocusFix-MacOS-App"
        let revision = Bundle.main.object(forInfoDictionaryKey: "FocusFixSourceRevision") as? String ?? ""
        let isCommit = revision.count == 40 && revision.allSatisfy { $0.isHexDigit }
        return URL(string: isCommit ? "\(root)/tree/\(revision)" : root)!
    }
}

struct AboutView: View {
    @State private var showLicense = false
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "\(info["CFBundleShortVersionString"] as? String ?? "") (\(info["CFBundleVersion"] as? String ?? ""))"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("FocusFix").font(.largeTitle.bold())
                Text("Version \(version)").foregroundStyle(.secondary)
                Text("Record activity patterns on your Mac, plan breaks, and reflect with optional check-ins. FocusFix does not diagnose fatigue or measure objective productivity.")
                Divider()
                PrivacyNoticeDetails()
                Divider()
                Link("Get support on GitHub", destination: AppLinks.support)
                Text("GitHub Issues are public. Do not post recordings, participant IDs, credentials, or personal information. You can report a problem without sharing session files.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Copyright © 2026 Kristian Janci").font(.headline)
                Text("Licensed under the GNU General Public License, version 3 only. You may copy, modify and redistribute this software under that license. It comes without warranty, including merchantability or fitness for a particular purpose. Third-party material retains its own notices.")
                HStack {
                    Button("Read GPL v3") { showLicense = true }
                    Link("Source code", destination: AppLinks.source)
                }
            }.padding(26).textSelection(.enabled)
        }.frame(minWidth: 500, idealWidth: 560, minHeight: 480, idealHeight: 650)
        .sheet(isPresented: $showLicense) { LicenseView() }
    }
}

private struct LicenseView: View {
    @Environment(\.dismiss) private var dismiss
    private var license: String {
        guard let url = Bundle.main.url(forResource: "GPL-3.0", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "License could not be loaded. See https://www.gnu.org/licenses/gpl-3.0.html."
        }
        return text
    }
    var body: some View {
        VStack(alignment: .trailing) {
            Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            ScrollView { Text(license).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding() }
        }.padding().frame(width: 640, height: 560)
    }
}
