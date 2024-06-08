//
//  NotesRow.swift
//  NotesApp
//
//  Created by Khan, Owais on 6/8/24.
//

import SwiftUI

struct NotesRow: View {
    var body: some View {
        VStack {
            HStack{
                Text("Test test")
                Spacer()
                Image(systemName: "note.text")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 25, height: 30)
                    .foregroundColor(Color.red)
                    .shadow(color: Color.gray, radius: 100)
                    
            }
            .padding()
            Text("testing abds abdjabd testing abds abdjabd testing abds abdjabd")
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
    NotesRow()
}
