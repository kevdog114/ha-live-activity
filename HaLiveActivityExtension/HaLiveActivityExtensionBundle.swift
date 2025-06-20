//
//  HaLiveActivityExtensionBundle.swift
//  HaLiveActivityExtension
//
//  Created by Kevin Schaefer on 6/20/25.
//

import WidgetKit
import SwiftUI

@main
struct HaLiveActivityExtensionBundle: WidgetBundle {
    var body: some Widget {
        HaLiveActivityExtension()
        HaLiveActivityExtensionControl()
        HaLiveActivityExtensionLiveActivity()
    }
}
