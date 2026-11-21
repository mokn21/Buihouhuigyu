import SwiftUI

/// Stream settings, shared by the main settings sheet and the in-stream menu.
struct StreamSettingsForm: View {
	@Binding var settings: StreamSettings

	var body: some View {
		Section {
			Picker("Resolution", selection: $settings.resolution) {
				ForEach(StreamResolution.allCases) { Text($0.label).tag($0) }
			}
			Picker("Frame rate", selection: $settings.fps) {
				Text("60 fps").tag(60)
				Text("30 fps").tag(30)
			}
			VStack(alignment: .leading) {
				HStack {
					Text("Bitrate")
					Spacer()
					Text("\(settings.bitrateMbps) Mbps").foregroundStyle(.secondary).monospacedDigit()
				}
				Slider(value: Binding(get: { Double(settings.bitrateMbps) }, set: { settings.bitrateMbps = Int($0) }), in: 5...100, step: 5)
			}
			Picker("Codec", selection: $settings.codec) {
				ForEach(VideoCodecChoice.allCases) { Text($0.label).tag($0) }
			}
			.disabled(settings.hdr)
			Toggle("HDR", isOn: $settings.hdr)
		} header: {
			Text("Video")
		} footer: {
			Text("PS5 Remote Play tops out at 1080p60. The PS5 may cap the bitrate below what you ask for, so watch the stats overlay. HDR needs H.265 and HDR turned on in the PS5's video output settings. Changing these reconnects the stream.")
		}

		Section {
			Picker("Picture", selection: $settings.displayMode) {
				ForEach(DisplayMode.allCases) { Text($0.label).tag($0) }
			}
			Toggle("Sharp upscaling", isOn: $settings.sharpUpscaling)
			if UIScreen.main.maximumFramesPerSecond > 60 {
				Toggle("120 Hz screen", isOn: $settings.highRefreshDisplay)
			}
			Toggle("Show stats", isOn: $settings.showStats)
		} header: {
			Text("Display")
		} footer: {
			Text("Fit shows the whole picture, with black bars where the screen is a different shape to 16:9. Zoom fills the screen and crops the overflow. 120 Hz screen gets each frame on screen sooner, for a little more battery.")
		}

		Section {
			Toggle("Rumble", isOn: $settings.rumble)
			Toggle("Phone gyro for motion controls", isOn: $settings.phoneMotion)
			Toggle("Select button is touchpad click", isOn: $settings.selectIsTouchpad)
		} header: {
			Text("Controller")
		} footer: {
			Text("Phone gyro is used when the controller has no motion sensors, like a GameSir G8+. Hold Select + Start for a second during a stream to open the menu.")
		}
	}
}

struct SettingsView: View {
	@Environment(SettingsStore.self) private var store
	@Environment(ConsoleStore.self) private var consoles
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		@Bindable var store = store
		NavigationStack {
			Form {
					StreamSettingsForm(settings: $store.settings)
					TranslationSettingsForm(settings: $store.settings)

				Section {
					ShareLink(
						item: DiagnosticsReport(consoleNames: consoles.consoles.map(\.name), settings: store.settings),
						preview: SharePreview("Orion Subtitles diagnostics")
					) {
						Label("Share diagnostics", systemImage: "ladybug")
					}
					Link(destination: URL(string: "https://github.com/orion-subtitles/orion-subtitles/issues/new")!) {
						Label("Report a problem on GitHub", systemImage: "exclamationmark.bubble")
					}
				} header: {
					Text("Help")
				} footer: {
					Text("The report has your phone model, screen details, settings and the app's logs since it was opened. IP addresses, keys, account IDs and console names are removed. Share it before closing the app, so the logs still cover the problem.")
				}
			}
			.navigationTitle("Settings")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
			}
		}
	}
}

private struct TranslationSettingsForm: View {
	@Binding var settings: StreamSettings

	var body: some View {
		Section {
			Picker("لغة النص الأصلي", selection: $settings.translationSourceLanguage) {
				Text("الكشف التلقائي").tag("auto")
				Text("الإنجليزية").tag("en-US")
				Text("الإنجليزية البريطانية").tag("en-GB")
			}
			Picker("لغة الترجمة", selection: $settings.translationTargetLanguage) {
				Text("العربية").tag("ar")
			}
			VStack(alignment: .leading) {
				HStack { Text("حجم الخط"); Spacer(); Text("\(Int(settings.translationFontSize))") }
				Slider(value: $settings.translationFontSize, in: 16...64, step: 1)
			}
			VStack(alignment: .leading) {
				HStack { Text("مكان الترجمة العمودي"); Spacer(); Text("\(Int(settings.translationPositionY * 100))٪") }
				Slider(value: $settings.translationPositionY, in: 0.15...0.92)
			}
			VStack(alignment: .leading) {
				HStack { Text("الفاصل بين فحوص OCR"); Spacer(); Text("\(settings.translationIntervalMs) مللي ثانية") }
				Slider(value: Binding(get: { Double(settings.translationIntervalMs) }, set: { settings.translationIntervalMs = Int($0) }), in: 150...1000, step: 50)
			}
			Text("منطقة الالتقاط — اسحب القيم لتحديد المستطيل داخل إطار Remote Play")
			RegionSlider(title: "أفقيًا", value: $settings.translationRegion.x, range: 0...0.9)
			RegionSlider(title: "عموديًا", value: $settings.translationRegion.y, range: 0...0.9)
			RegionSlider(title: "العرض", value: $settings.translationRegion.width, range: 0.1...1)
			RegionSlider(title: "الارتفاع", value: $settings.translationRegion.height, range: 0.1...1)
		} header: {
			Text("الترجمة")
		} footer: {
			Text("تُحفظ هذه الإعدادات وتُطبق على OCR والبث التالي. الترجمة العربية تستخدم Apple Translation عندما يدعمها إصدار iPadOS.")
		}
	}
}

private struct RegionSlider: View {
	let title: String
	@Binding var value: Double
	let range: ClosedRange<Double>

	var body: some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack { Text(title); Spacer(); Text(String(format: "%.0f%%", value * 100)).foregroundStyle(.secondary) }
			Slider(value: $value, in: range)
		}
	}
}
