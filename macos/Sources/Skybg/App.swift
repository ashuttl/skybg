import AppKit
import SkyKit
import SwiftUI

struct SkybgApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Skybg", id: "main") {
            ContentView(model: model)
                .onAppear { model.start() }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // The window is the app: nothing stays behind in the Dock or the menu
    // bar. The timer runs on its own.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            timeline
            styles
            settings
            if let problem = model.problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 720)
        .onChange(of: colorScheme) { _ in
            // The built-in palette follows the appearance; give the system a
            // moment to record the new one.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { model.refresh() }
        }
    }

    // MARK: the large preview

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            if let image = model.hero {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .interpolation(.high)
            } else {
                Rectangle().fill(.quaternary)
                if !model.hasLocation {
                    Text("Set a location below to see the sky.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if !model.caption.isEmpty {
                Text(model.caption)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .aspectRatio(model.aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
    }

    // MARK: the hour shown

    private var timeline: some View {
        HStack(spacing: 10) {
            Image(systemName: "sunrise")
                .foregroundStyle(.secondary)
            Slider(value: Binding(
                get: { model.previewHour ?? Moment().localHour },
                set: { model.previewHour = $0; model.refresh() }
            ), in: 0...24)
            .accessibilityLabel("Hour of the day to preview")
            Button("Now") {
                model.previewHour = nil
                model.refresh()
            }
            .disabled(model.previewHour == nil)
        }
    }

    // MARK: the styles

    private var styles: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Style.allCases) { style in
                    StyleButton(style: style, image: model.thumbnails[style], aspect: model.aspect,
                                selected: style == model.style) { model.choose(style) }
                }
            }
            Text(model.style.summary + ".")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: the settings

    private var settings: some View {
        VStack(spacing: 0) {
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep the desktop picture in step with the sky")
                    Text(model.isOn ? "Redrawn every five minutes, whether or not Skybg is open."
                                    : "Off. The desktop picture is left as it is.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Toggle("Keep the desktop picture in step with the sky", isOn: Binding(
                    get: { model.isOn }, set: { model.setOn($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(model.busy || !model.hasLocation)
            }
            Divider().padding(.leading, 12)
            row {
                Text("Location")
                Spacer()
                TextField("Latitude", text: $model.latitude)
                    .frame(width: 90)
                    .onSubmit { model.commitLocation() }
                TextField("Longitude", text: $model.longitude)
                    .frame(width: 90)
                    .onSubmit { model.commitLocation() }
                Button {
                    model.useCurrentLocation()
                } label: {
                    Label("Use Current Location", systemImage: "location")
                }
                .disabled(model.locating)
            }
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            Divider().padding(.leading, 12)
            row {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show the weather")
                    Text("Cloud and fog, in Sky and Window. Sends your coordinates to Open-Meteo.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Show the weather", isOn: Binding(get: { model.weather }, set: { model.setWeather($0) }))
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.separator))
    }

    private func row<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
    }
}

struct StyleButton: View {
    let style: Style
    let image: CGImage?
    let aspect: Double
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if let image {
                        Image(decorative: image, scale: 2).resizable().interpolation(.high)
                    } else {
                        Rectangle().fill(.quaternary)
                    }
                }
                .aspectRatio(aspect, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(3)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3)
                )
                Text(style.name)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.name)
        .accessibilityHint(style.summary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Draws the window to a PNG without showing it: `Skybg snapshot OUT.png`.
/// For the README, and for checking the layout.
@MainActor
func snapshotWindow(to path: String) throws {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let model = AppModel()
    model.start()
    let view = NSHostingView(rootView: ContentView(model: model)
        .background(Color(nsColor: .windowBackgroundColor)))
    let window = NSWindow(contentRect: NSRect(origin: .zero, size: view.fittingSize),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    // Let the previews be drawn.
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    view.setFrameSize(view.fittingSize)
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw SkyError("could not draw the window")
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw SkyError("could not draw the window")
    }
    try png.write(to: URL(fileURLWithPath: path))
}
