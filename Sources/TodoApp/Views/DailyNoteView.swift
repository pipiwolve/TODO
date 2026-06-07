import SwiftUI

struct DailyNoteView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Daily Review")
                .font(.headline)
            HStack(alignment: .top, spacing: 10) {
                TextField("Blockers", text: $model.dailyNote.blockers, axis: .vertical)
                TextField("Completed", text: $model.dailyNote.completedSummary, axis: .vertical)
                TextField("Tomorrow", text: $model.dailyNote.tomorrowPlan, axis: .vertical)
                Button {
                    model.saveDailyNote()
                } label: {
                    Image(systemName: "tray.and.arrow.down")
                }
                .help("Save daily review")
            }
            .textFieldStyle(.roundedBorder)
        }
    }
}
