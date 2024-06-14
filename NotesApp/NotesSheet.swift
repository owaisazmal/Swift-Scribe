//
//  NotesSheet.swift
//  NotesApp
//
//  Created by Khan, Owais on 6/13/24.
//
extension View{
    @ViewBuilder public func hidden (_ shouldHide: Bool)-> some View{
        switch shouldHide{
        case true: self.hidden()
        case false: self
        }
    }
}

import SwiftUI

struct NotesSheet: View {
    @State private var title = ""
    @State private var description = ""
    @FocusState private var isDecriptionFocused: Bool
    @Environment(\.modelContext) var context
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack{
                TextField("Title", text: $title)
                    .font(.headline)
                    .padding()
                    
                Divider()
                    .padding()
                
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $description)
                        .padding(.horizontal)
                        .focused($isDecriptionFocused)
                    Text("Description")
                        .fontWeight(.light)
                        .foregroundColor(.black)
                        .opacity(0.25)
                        .padding(.horizontal)
                        .hidden(isDecriptionFocused)
                }
            }
            .toolbar{
                ToolbarItemGroup(placement: .topBarLeading){
                    Button("Cancel"){
                        dismiss()
                    }
                        .frame(width: 100, height: 40)
                        .foregroundColor(.white)
                        .background(Color.red)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .gray, radius: 5)
                }
        }
            .toolbar{
                ToolbarItemGroup(placement: .topBarTrailing){
                    Button(action: {
                        //Save the note in the database using SwiftData
                        if(!title.isEmpty && !description.isEmpty){
                            context.insert(Note(title: title, description: description, createdAt: Date.now))
                        
                        //Dismiss the bottom sheet
                        dismiss()
                        }

                        
                    }){
                        HStack{
                            Spacer()
                            Text("Save")
                            Spacer()
                        }
                    }
                        .frame(width: 100, height: 40)
                        .foregroundColor(.white)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .shadow(color: .gray, radius: 5)
                }
        }
        }
    }
}

#Preview {
    NotesSheet()
}
