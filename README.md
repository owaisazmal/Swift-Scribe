# Swift Scribe - Notes App

## Overview
Swift Scribe is a sleek, powerful, and intuitive text editor designed to elevate your writing experience. This app allows users to create, view, and delete notes with a user-friendly interface. The app utilizes SwiftUI for the interface and SwiftData for data management, ensuring a smooth and efficient experience.

## Features
- **Create Notes:** Easily add new notes with the "plus" button.
- **View Notes:** Scroll through your list of notes, sorted by title.
- **Delete Notes:** Long press on a note to reveal a context menu for deletion.
- **Responsive Design:** Adapts seamlessly to different screen sizes with a dynamic layout.

## Screenshots
<img width="1595" alt="Screenshot 2024-06-15 at 3 54 28 PM" src="https://github.com/owaisazmal/Swift-Scribe/assets/87142612/ca4f3d3c-71f7-4ceb-9e29-504543427430">


https://github.com/owaisazmal/Swift-Scribe/assets/87142612/09531bd6-888d-472c-8681-ce7ff83ed8ed



## Installation
To get started with Swift Scribe, follow these steps:

1. Clone the repository:
    ```sh
    git clone https://github.com/yourusername/SwiftScribe.git
    ```

2. Open the project in Xcode:
    ```sh
    cd SwiftScribe
    open SwiftScribe.xcodeproj
    ```

3. Build and run the project on your preferred device or simulator.

## Code Structure
### `ContentView.swift`
The main view of the app. It contains:
- A gradient welcome banner.
- A list of notes fetched from SwiftData.
- A sheet for adding or editing notes.
- A button for creating new notes.

### `NotesRow.swift`
A custom view representing each note in the list.

### `NotesSheet.swift`
A sheet view that appears when adding or editing a note.

### `Note.swift`
A SwiftData model representing a note, with properties for the title and description.

## Usage
### Adding a Note
1. Tap the "+" button at the bottom right corner.
2. Fill in the title and description in the sheet that appears.
3. Save the note.

### Viewing Notes
- Notes are displayed in a scrollable list. Tap on a note to view or edit it in a sheet.

### Deleting a Note
1. Long press on the note you wish to delete.
2. Select "Delete" from the context menu.

## Contributing
Contributions are welcome! Please fork the repository and submit a pull request for any changes or improvements.

---

Thank you for using Swift Scribe! We hope it enhances your writing experience.
