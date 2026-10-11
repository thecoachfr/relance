import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct TaskLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TaskActivityAttributes.self) { context in
            LockScreenView(state: context.state, isStale: context.isStale)
                .padding()
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let state = context.state
            let late = context.isStale || state.due < .now
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: late ? "exclamationmark.circle.fill" : "clock")
                        .font(.title2).foregroundStyle(late ? .red : .orange)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        StatusLine(state: state, late: late)
                        ActionButtons(taskID: state.taskID)
                    }
                }
            } compactLeading: {
                Image(systemName: late ? "exclamationmark.circle.fill" : "clock")
                    .foregroundStyle(late ? .red : .orange)
            } compactTrailing: {
                Text(state.title).font(.caption).lineLimit(1).frame(maxWidth: 64)
            } minimal: {
                Image(systemName: late ? "exclamationmark.circle.fill" : "clock")
                    .foregroundStyle(late ? .red : .orange)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: TaskActivityAttributes.ContentState
    let isStale: Bool

    var body: some View {
        let late = isStale || state.due < .now
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: late ? "exclamationmark.circle.fill" : "clock")
                    .foregroundStyle(late ? .red : .orange)
                Text(state.title).font(.headline).lineLimit(2)
                Spacer()
                if state.otherOverdue > 0 {
                    Text("+\(state.otherOverdue)").font(.subheadline.bold()).foregroundStyle(.red)
                        .accessibilityLabel("\(state.otherOverdue) autres en retard")
                }
            }
            StatusLine(state: state, late: late)
            ActionButtons(taskID: state.taskID)
        }
    }
}

private struct StatusLine: View {
    let state: TaskActivityAttributes.ContentState
    let late: Bool

    var body: some View {
        Group {
            if late && state.hasTime {
                Text("En retard de \(Text(state.due, style: .relative))")
            } else if late {
                Text("Échéance passée, toujours pas fait")
            } else if state.hasTime {
                Text("Prévu à \(state.due.formatted(date: .omitted, time: .shortened)), dans \(Text(state.due, style: .relative))")
            } else {
                Text("Prévu aujourd'hui")
            }
        }
        .font(.subheadline)
        .foregroundStyle(late ? .red : .secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActionButtons: View {
    let taskID: String

    var body: some View {
        HStack {
            Button(intent: CompleteTaskIntent(taskID: taskID)) {
                Label("Fait", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .tint(.green)
            Button(intent: SnoozeTaskIntent(taskID: taskID)) {
                Label("Dans 1 h", systemImage: "clock").frame(maxWidth: .infinity)
            }
            .tint(.orange)
        }
        .buttonStyle(.borderedProminent)
        .font(.subheadline.weight(.semibold))
    }
}
