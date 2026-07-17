import SwiftUI

struct JarvisView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var speech = SpeechRecognitionService()
    @State private var previewPromptIndex = 0

    private let suggestions = [
        "TURN OFF GAMING ROOM",
        "HOW DID I SLEEP?",
        "GLUCOSE TODAY",
        "WARM UP BEDROOM",
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Circle()
                    .fill(VokrrTheme.emerald)
                    .frame(width: 5, height: 5)
                    .shadow(color: VokrrTheme.emerald.opacity(0.9), radius: 6)
                Text("JARVIS")
                    .font(VokrrTheme.mono(11, medium: true))
                    .tracking(5)
                    .foregroundStyle(VokrrTheme.champagne)
                Text("· VOKRR CORE")
                    .font(VokrrTheme.mono(7.5))
                    .tracking(2)
                    .foregroundStyle(VokrrTheme.tertiaryText)
            }
            .padding(.top, 20)

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.jarvisChat) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }
                        if appState.jarvisStatus == "processing" {
                            ProcessingBubble()
                                .id("processing")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 20)
                }
                .onChange(of: appState.jarvisChat.count) { _, _ in
                    if let id = appState.jarvisChat.last?.id {
                        withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
                    }
                }
            }

            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                Task { await appState.sendJarvisCommand(suggestion.lowercased()) }
                            } label: {
                                Text(suggestion)
                                    .font(VokrrTheme.mono(8))
                                    .tracking(1.5)
                                    .foregroundStyle(VokrrTheme.secondaryText)
                                    .padding(.horizontal, 13)
                                    .frame(height: 34)
                                    .overlay(Capsule().stroke(VokrrTheme.champagne.opacity(0.15)))
                            }
                            .buttonStyle(VokrrPressStyle())
                        }
                    }
                    .padding(.horizontal, 22)
                }
                .scrollClipDisabled()

                Group {
                    if speech.isListening {
                        ListeningBars()
                    } else {
                        Text(speech.errorMessage.isEmpty ? "TAP TO SPEAK" : speech.errorMessage.uppercased())
                            .font(VokrrTheme.mono(8))
                            .tracking(2)
                            .foregroundStyle(speech.errorMessage.isEmpty ? VokrrTheme.tertiaryText : VokrrTheme.champagne)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                }
                .frame(height: 20)

                Button {
                    if appState.isPreviewMode {
                        let prompt = suggestions[previewPromptIndex % suggestions.count]
                        previewPromptIndex += 1
                        Task { await appState.sendJarvisCommand(prompt.lowercased()) }
                    } else {
                        Task { await speech.toggle() }
                    }
                } label: {
                    Circle()
                        .fill(speech.isListening ? VokrrTheme.emerald.opacity(0.16) : VokrrTheme.champagne.opacity(0.05))
                        .frame(width: 62, height: 62)
                        .overlay(
                            Circle().stroke(
                                speech.isListening ? VokrrTheme.emerald.opacity(0.80) : VokrrTheme.champagne.opacity(0.30)
                            )
                        )
                        .overlay {
                            Image(systemName: speech.isListening ? "stop.fill" : "mic")
                                .font(.system(size: 23, weight: .light))
                                .foregroundStyle(speech.isListening ? VokrrTheme.emerald : VokrrTheme.champagne)
                        }
                        .shadow(
                            color: speech.isListening ? VokrrTheme.emerald.opacity(0.35) : .clear,
                            radius: 17
                        )
                }
                .buttonStyle(VokrrPressStyle())
                .animation(VokrrTheme.tab, value: speech.isListening)
                .accessibilityLabel(speech.isListening ? "Stop listening" : "Speak to Jarvis")
            }
            .padding(.bottom, 106)
        }
        .background(
            RadialGradient(
                colors: [VokrrTheme.emerald.opacity(0.06), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 320
            )
        )
        .background(VokrrTheme.background)
        .onAppear {
            speech.onFinalTranscript = { transcript in
                Task { await appState.sendJarvisCommand(transcript) }
            }
        }
        .onDisappear {
            speech.finishListening(submit: false)
        }
    }
}

private struct ChatBubble: View {
    let message: JarvisChatMessage

    var body: some View {
        HStack {
            if message.speaker == .user { Spacer(minLength: 60) }
            Text(message.text)
                .font(VokrrTheme.jost(15))
                .lineSpacing(3)
                .foregroundStyle(message.speaker == .user ? VokrrTheme.primaryText : Color(red: 217 / 255, green: 217 / 255, blue: 207 / 255))
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(
                    message.speaker == .user
                        ? VokrrTheme.emerald.opacity(0.14)
                        : VokrrTheme.champagne.opacity(0.06)
                )
                .clipShape(BubbleShape(isUser: message.speaker == .user))
                .overlay(
                    BubbleShape(isUser: message.speaker == .user)
                        .stroke(
                            message.speaker == .user
                                ? VokrrTheme.emerald.opacity(0.30)
                                : VokrrTheme.champagne.opacity(0.16)
                        )
                )
            if message.speaker == .jarvis { Spacer(minLength: 44) }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let radii = RectangleCornerRadii(
            topLeading: 20,
            bottomLeading: isUser ? 20 : 5,
            bottomTrailing: isUser ? 5 : 20,
            topTrailing: 20
        )
        return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: rect)
    }
}

private struct ProcessingBubble: View {
    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0 ..< 3) { index in
                    Circle()
                        .fill(VokrrTheme.champagne.opacity(0.55 + Double(index) * 0.15))
                        .frame(width: 4, height: 4)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 40)
            .background(VokrrTheme.champagne.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Spacer()
        }
    }
}

private struct ListeningBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0 ..< 5) { index in
                    let phase = (time + Double(index) * 0.15) / 0.9 * .pi * 2
                    let scale = reduceMotion ? 0.65 : 0.25 + abs(sin(phase)) * 0.75
                    Capsule()
                        .fill(VokrrTheme.emerald)
                        .frame(width: 3, height: 18)
                        .scaleEffect(y: scale)
                }
            }
        }
    }
}
