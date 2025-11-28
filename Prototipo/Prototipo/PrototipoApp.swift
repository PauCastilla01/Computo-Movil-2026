//
//  PrototipoApp.swift
//  Prototipo
//
//  Created by Paulina Castilla padilla on 02/10/25.
//

//
import SwiftUI
import SwiftData

// MARK: - 🩷 Main App
@main
struct MatchSeguraApp: App {
    @State private var authManager = AuthManager()

    var body: some Scene {
        WindowGroup {
            if authManager.isLoggedIn {
                ContentView()
            } else {
                AuthView(authManager: authManager)
            }
        }
    }
}



