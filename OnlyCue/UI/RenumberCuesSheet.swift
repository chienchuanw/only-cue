import SwiftUI

/// Modal sheet for resequencing the selected cues' numbers (#535). Hosted by
/// `CueListPane`. "Renumber" calls `onRenumber(start, interval)`; "Cancel"
/// calls `onCancel()`. Numbers are assigned to the selected cues in time order.
struct RenumberCuesSheet: View {

    let cueCount: Int
    let onRenumber: (Double, Double) -> Void
    let onCancel: () -> Void

    @State private var start: Double
    @State private var interval: Double

    init(
        cueCount: Int,
        initialStart: Double = 1,
        initialInterval: Double = 1,
        onRenumber: @escaping (Double, Double) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.cueCount = cueCount
        self.onRenumber = onRenumber
        self.onCancel = onCancel
        self._start = State(initialValue: initialStart)
        self._interval = State(initialValue: initialInterval)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Renumber \(cueCount) Cues")
                .font(.headline)
            Text("Numbers are assigned to the selected cues in time order.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Start")
                    TextField("Start", value: $start, format: .number)
                        .frame(width: 90)
                        .accessibilityIdentifier("renumberCuesStart")
                    Stepper("", value: $start, in: 0.001...9999, step: 1)
                        .labelsHidden()
                }
                GridRow {
                    Text("Interval")
                    TextField("Interval", value: $interval, format: .number)
                        .frame(width: 90)
                        .accessibilityIdentifier("renumberCuesInterval")
                    Stepper("", value: $interval, in: 0.001...1000, step: 1)
                        .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("renumberCuesCancel")
                Button("Renumber") { onRenumber(start, interval) }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("renumberCuesConfirm")
            }
        }
        .padding(20)
        .frame(minWidth: 360)
        .accessibilityIdentifier("renumberCuesSheet")
    }

    // MARK: - Test hooks (see CueNotesSheet for why @State can't be set pre-hosting)
    var testStart: Double { start }
    var testInterval: Double { interval }
    func testConfirm() { onRenumber(start, interval) }
    func testCancel() { onCancel() }
}
