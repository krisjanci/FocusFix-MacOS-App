import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ProfileAvatar: View {
    let profile: UserProfile?
    var size: CGFloat = 44

    private var color: Color {
        switch profile?.color {
        case "blue": return .blue
        case "purple": return .purple
        case "orange": return .orange
        case "pink": return .pink
        default: return Color(red: 0.02, green: 0.60, blue: 0.54)
        }
    }

    var body: some View {
        Group {
            if let photo = profile?.photo, let image = NSImage(data: photo) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    color.opacity(0.13)
                    Image(systemName: profile?.symbol ?? "person.fill")
                        .font(.system(size: size * 0.45, weight: .medium)).foregroundStyle(color)
                }
            }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct ProfileEditor: View {
    @ObservedObject var controller = ProfileController.shared
    @ObservedObject var account = AccountController.shared
    @State private var draft = UserProfile()
    @State private var editing = false
    @State private var photoError: String?
    var onSaved: () -> Void = {}

    private var savedProfile: UserProfile? { account.session == nil ? controller.profile : account.profile }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Button {
                    if !editing {
                        draft = savedProfile ?? UserProfile()
                        photoError = nil
                        editing = true
                    }
                    choosePhoto()
                } label: {
                    ZStack {
                        ProfileAvatar(profile: editing ? draft : savedProfile, size: 62)
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "camera.fill").font(.system(size: 11))
                            if (editing ? draft : savedProfile)?.photo == nil {
                                Image(systemName: "plus").font(.system(size: 7, weight: .bold))
                                    .offset(x: 4, y: -4)
                            }
                        }.padding(6).foregroundStyle(.white).background(Color.accentColor, in: Circle())
                            .offset(x: 14, y: 14)
                    }.frame(width: 62, height: 62).contentShape(Circle())
                }.buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel((editing ? draft : savedProfile)?.photo == nil ? "Add profile photo" : "Change profile photo")
                    .help((editing ? draft : savedProfile)?.photo == nil ? "Add profile photo" : "Change profile photo")
                    .disabled(account.busy || (account.session != nil && !account.profileLoaded))
                VStack(alignment: .leading, spacing: 4) {
                    Text(savedProfile?.name ?? "Make FocusFix yours").font(.headline)
                    Text(account.session == nil ? "Profile on this Mac" : "Private account profile").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !editing {
                    Button(savedProfile == nil ? "Create profile" : "Edit") {
                        draft = savedProfile ?? UserProfile()
                        photoError = nil
                        editing = true
                    }.disabled(account.session != nil && !account.profileLoaded)
                }
            }
            if editing {
                TextField("Display name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                Text("Choose an avatar").font(.caption).foregroundStyle(.secondary)
                HStack {
                    ForEach(UserProfile.symbols, id: \.self) { symbol in
                        Button {
                            draft.symbol = symbol
                            draft.photo = nil
                        } label: {
                            Image(systemName: symbol).frame(width: 28, height: 28)
                        }
                        .tint(draft.symbol == symbol && draft.photo == nil ? .accentColor : .secondary)
                        .accessibilityLabel(avatarLabel(symbol))
                        .accessibilityAddTraits(draft.symbol == symbol && draft.photo == nil ? .isSelected : [])
                    }
                }
                Picker("Avatar color", selection: $draft.color) {
                    ForEach(UserProfile.colors, id: \.self) { Text($0.capitalized).tag($0) }
                }
                HStack {
                    if draft.photo != nil { Button("Remove photo") { draft.photo = nil } }
                }
                Text(account.session == nil ? "Photos stay on this Mac. Choose an image under 10 MB; it is cropped to a square." : "Saving sends this name and avatar to your private account profile. Choose a photo under 10 MB.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = photoError { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("Save profile") {
                        if account.session != nil {
                            Task { if await account.saveProfile(draft) { editing = false; onSaved() } }
                        } else if controller.save(draft) { editing = false; onSaved() }
                    }.buttonStyle(.borderedProminent)
                        .disabled((try? draft.validated()) == nil || account.busy)
                    Button("Cancel") { editing = false; photoError = nil }
                }
            }
            if let notice = controller.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }.disabled(account.busy)
            .onAppear { draft = savedProfile ?? UserProfile() }
            .onChange(of: account.session?.user.id) { _, _ in editing = false; photoError = nil }
    }

    private func avatarLabel(_ symbol: String) -> String {
        switch symbol {
        case "leaf.fill": return "Leaf avatar"
        case "sun.max.fill": return "Sun avatar"
        case "moon.stars.fill": return "Moon avatar"
        case "bolt.fill": return "Lightning avatar"
        case "book.fill": return "Book avatar"
        default: return "Person avatar"
        }
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.title = "Choose profile photo"
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            draft.photo = try ProfileController.photo(from: url)
            photoError = nil
        } catch { photoError = "This photo could not be opened. Choose a PNG, JPEG, HEIC or TIFF under 10 MB." }
    }
}
