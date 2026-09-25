import SwiftUI

struct ContentView: View {
    @State private var secondsRemaining = 60
    @State private var isRunning = false
    @State private var timerTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Text("Recovery Timer")
                .font(.title2)
                .fontWeight(.semibold)

            Text("\(secondsRemaining) seconds")
                .font(.system(size: 32, weight: .bold, design: .rounded))

            Button(isRunning ? "Pause" : "Start") {
                if isRunning {
                    pauseTimer()
                } else {
                    startTimer()
                }
            }
            .buttonStyle(.borderedProminent)

            Button("Reset") {
                pauseTimer()
                secondsRemaining = 60
            }
        }
        .padding(30)
        .frame(width: 320, height: 220)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue.opacity(0.12))
                .stroke(Color.blue, lineWidth: 2)
        }
        .padding()
        .onDisappear {
            timerTask?.cancel()
        }
    }

    private func startTimer() {
        guard secondsRemaining > 0 else {
            return
        }

        isRunning = true

        timerTask = Task {
            while !Task.isCancelled && secondsRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))

                guard !Task.isCancelled else {
                    break
                }

                secondsRemaining -= 1
            }

            isRunning = false
        }
    }

    private func pauseTimer() {
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }
}

#Preview {
    ContentView()
}
