//
//  ContentView.swift
//  NotesApp
//
//  Created by Khan, Owais on 6/7/24.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 25.0)
                .fill(
                LinearGradient(gradient: Gradient(colors: [Color.red.opacity(0.8), Color.black.opacity(0.7), Color.black.opacity(0.6), Color.black.opacity(0.6), Color.red.opacity(0.8)]), startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: geometry.size.height / 2)
                .overlay(
                    RoundedRectangle(cornerRadius:25.0)
                        .fill(Color.white.opacity(0.3))
                        .frame(width: .infinity,height: 200)
                        .overlay(
                            HStack {
                                
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("Welcome to Swift Scribe")
                                        .font(.system(size: 24, weight: .bold))
                                    Text("Elevate your writing experience with our sleek, powerful, and intuitive text editor.")
                                        .font(.subheadline)
                                }
                                Spacer()
                                Image(systemName: "applepencil.and.scribble")
                                    .imageScale(.large)
                                    .font(.system(size: 40))
                            }
                                .padding()
                            )
                        .padding())
                
        }
        .edgesIgnoringSafeArea(.top)
    }
}

#Preview {
    ContentView()
}
