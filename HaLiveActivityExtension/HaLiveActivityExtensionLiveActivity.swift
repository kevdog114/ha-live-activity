//
//  HaLiveActivityExtensionLiveActivity.swift
//  HaLiveActivityExtension
//
//  Created by Kevin Schaefer on 6/20/25.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct HaLiveActivityExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct HaLiveActivityExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: HaLiveActivityExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension HaLiveActivityExtensionAttributes {
    fileprivate static var preview: HaLiveActivityExtensionAttributes {
        HaLiveActivityExtensionAttributes(name: "World")
    }
}

extension HaLiveActivityExtensionAttributes.ContentState {
    fileprivate static var smiley: HaLiveActivityExtensionAttributes.ContentState {
        HaLiveActivityExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: HaLiveActivityExtensionAttributes.ContentState {
         HaLiveActivityExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: HaLiveActivityExtensionAttributes.preview) {
   HaLiveActivityExtensionLiveActivity()
} contentStates: {
    HaLiveActivityExtensionAttributes.ContentState.smiley
    HaLiveActivityExtensionAttributes.ContentState.starEyes
}
