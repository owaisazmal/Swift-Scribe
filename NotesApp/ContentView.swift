//
//  ContentView.swift
//  NotesApp
//
//  Created by Khan, Owais on 6/7/24.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var notes = Note.emptyList
    @State private var isShowingSheet = false
    @Query(sort: \Note.title) var swiftDataNotes: [Note]
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack {
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
                    ForEach(swiftDataNotes){note in
                        NotesRow(note: note)
                    }
                }
            }
            .sheet(isPresented: $isShowingSheet) {
                NotesSheet()
                    .presentationDetents([.fraction(0.70), .large])
            }
            .background(Color.gray.opacity(0.2))
            .overlay{
                if swiftDataNotes.isEmpty{
                    ContentUnavailableView(
                        label: {
                        Label {
                            Text("No Notes")
                        }
                        icon: {
                            Image(systemName: "doc.plaintext")
                                .foregroundColor(.red.opacity(0.8))
                            }
                        }
                    )
                    .offset(y: 120)
                }
                
            }
            .overlay(
                HStack {
                    Spacer()
                    Button(action: {isShowingSheet = true}){
                    Image(systemName: "plus")
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .clipShape(/*@START_MENU_TOKEN@*/Circle()/*@END_MENU_TOKEN@*/)
                        .shadow(color: Color.red, radius: 15)
                    }
                }.padding(),
                alignment: .bottomTrailing
            )
        }
        .edgesIgnoringSafeArea(.top)
    }
}

#Preview {
    ContentView()
}
