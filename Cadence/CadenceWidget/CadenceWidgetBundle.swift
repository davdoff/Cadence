import WidgetKit
import SwiftUI

@main
struct CadenceWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextEventsWidget()
        TodayScheduleWidget()
        DailyProgressWidget()
        NextMealWidget()
        HabitWidget()
        HabitGridWidget()
        EventLiveActivity()
    }
}
