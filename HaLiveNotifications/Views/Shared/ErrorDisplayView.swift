// In HaLiveNotifications/Views/Shared/ErrorDisplayView.swift
import SwiftUI

struct ErrorDisplayView: View {
    let error: Error? // More general, or use HAErrors specifically

    var body: some View {
        if let error = error {
            VStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.largeTitle)
                Text("Error")
                    .font(.headline)
                    .padding(.bottom, 2)
                Text(error.localizedDescription)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.red)
            }
            .padding()
            .background(Color.red.opacity(0.1))
            .cornerRadius(10)
        } else {
            EmptyView()
        }
    }
}

struct ErrorDisplayView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ErrorDisplayView(error: HAErrors.networkError("Could not connect to server."))
            ErrorDisplayView(error: HAErrors.authenticationError("Invalid token."))
            ErrorDisplayView(error: nil) // No error
        }
        .padding()
    }
}
