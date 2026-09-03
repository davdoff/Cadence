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
        QuickTimerWidget()
        // AlarmKit's countdown UI (iOS 26+). WidgetBundleBuilder supports
        // limited availability, so the bundle still builds against iOS 18.5;
        // the canImport guard keeps it building on pre-26 SDKs too.
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            QuickTimerAlarmActivity()
        }
        #endif
    }
}
