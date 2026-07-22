//
//  SpatiumApp.swift
//  Spatium
//
//  Created by Dongha Ryu on 6/26/26.
//

import SwiftUI

@main
struct SpatiumApp: App {
    @StateObject private var userFurnitureStore = UserFurnitureStore()

    var body: some Scene {
        WindowGroup {
            ContentView(userFurnitureStore: userFurnitureStore)
                .environmentObject(userFurnitureStore)
        }
    }
}
