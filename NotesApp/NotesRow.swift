//
//  NotesRow.swift
//  NotesApp
//
//  Created by Khan, Owais on 6/8/24.
//

import SwiftUI

struct NotesRow: View {
    let note: Note
    var body: some View {
        VStack(alignment: .leading) {
            HStack{
                Text(note.title)
                    .font(.headline)
                Spacer()
                Image(systemName: "note.text")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 30)
                    .foregroundColor(Color.red)
                    .shadow(color: Color.gray, radius: 100)
                    
            }
            .padding()
            Text(note.content)
                .font(.body)
                .lineLimit(1)
                .padding(.horizontal)
                .padding(.bottom)
        }
        .frame(maxWidth: /*@START_MENU_TOKEN@*/.infinity/*@END_MENU_TOKEN@*/)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white))
        .shadow(radius: 2)
        .padding(.horizontal)
    }
}

#Preview {
    NotesRow(note: Note(title: "TEST", description: "TESTING ABCD  ", createdAt: Date()))
}
