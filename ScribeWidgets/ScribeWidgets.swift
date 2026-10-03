import WidgetKit
import SwiftUI
import AppIntents

@main
struct ScribeWidgetBundle: WidgetBundle {
    var body: some Widget {
        ContinueWritingWidget()
        WritingWeekWidget()
        TodayPageWidget()
        QuickNoteWidget()
        QuickNoteControl()
        TodayPageControl()
    }
}

// MARK: Controls

/// A button for Control Center, the Lock Screen or the Action button: a new note, ready to write.
struct QuickNoteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.owais.NotesApp.control.quicknote") {
            ControlWidgetButton(action: QuickNoteControlIntent()) {
                Label("Quick Note", systemImage: "square.and.pencil")
            }
        }
        .displayName("Quick Note")
        .description("Starts a new note in Swift Scribe, ready to write.")
    }
}

struct TodayPageControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.owais.NotesApp.control.today") {
            ControlWidgetButton(action: TodayPageControlIntent()) {
                Label("Today's Page", systemImage: "calendar")
            }
        }
        .displayName("Today's Page")
        .description("Opens today's page in your daily journal.")
    }
}

struct ScribeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let cover: UIImage?

    static let sample = ScribeEntry(
        date: .now,
        snapshot: WidgetSnapshot(notebook: .init(id: UUID(), title: "Cell Biology", page: 12, pageCount: 34, clothHex: 0x3D5A40),
                                 pagesByDay: Dictionary(uniqueKeysWithValues: [0, 1, 3].compactMap { offset in
                                     Calendar.current.date(byAdding: .day, value: -offset, to: .now).map { (WidgetSnapshot.dayKey(for: $0), 2 + offset) }
                                 }),
                                 hasJournal: true),
        cover: nil)
}

/// Reads what the app last wrote. The timeline turns over at midnight so the week and the date stay right.
struct ScribeProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScribeEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (ScribeEntry) -> Void) {
        completion(context.isPreview ? .sample : entry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<ScribeEntry>) -> Void) {
        let now = Date.now, calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(entries: [entry(at: now), entry(at: midnight)], policy: .after(midnight)))
    }

    private func entry(at date: Date) -> ScribeEntry {
        let cover = WidgetSnapshot.directory.flatMap { UIImage(contentsOfFile: $0.appending(path: WidgetSnapshot.coverFile).path(percentEncoded: false)) }
        return ScribeEntry(date: date, snapshot: WidgetSnapshot.read() ?? WidgetSnapshot(), cover: cover)
    }
}

// MARK: Widgets

struct ContinueWritingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueWriting", provider: ScribeProvider()) { entry in
            ContinueWritingView(entry: entry)
                .containerBackground(Color.widgetPaper, for: .widget)
        }
        .configurationDisplayName("Continue Writing")
        .description("The notebook you last wrote in, open at your page.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WritingWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WritingWeek", provider: ScribeProvider()) { entry in
            WritingWeekView(entry: entry)
                .containerBackground(Color.widgetPaper, for: .widget)
        }
        .configurationDisplayName("This Week")
        .description("The days you wrote this week. Your writing history stays on this device.")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

struct TodayPageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayPage", provider: ScribeProvider()) { entry in
            TodayPageView(entry: entry)
                .containerBackground(Color.widgetPaper, for: .widget)
        }
        .configurationDisplayName("Today's Page")
        .description("Opens today's page in your daily journal.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

struct QuickNoteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickNote", provider: ScribeProvider()) { _ in
            QuickNoteView()
                .containerBackground(Color.widgetPaper, for: .widget)
        }
        .configurationDisplayName("Quick Note")
        .description("Starts a new note in Swift Scribe, ready to write.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline])
    }
}

// MARK: Views

struct QuickNoteView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "square.and.pencil").font(.title2).widgetAccentable()
                }
            case .accessoryInline:
                Label("Quick Note", systemImage: "square.and.pencil")
            default:
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "square.and.pencil").font(.title).foregroundStyle(Color.widgetAccent).widgetAccentable()
                    Spacer(minLength: 0)
                    Text("Quick Note").font(.system(.headline, design: .serif)).foregroundStyle(Color.widgetInk)
                    Text("A new note, ready to write.").font(.caption).foregroundStyle(Color.widgetSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "swiftscribe://quicknote"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Quick Note"))
    }
}

struct ContinueWritingView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScribeEntry

    var body: some View {
        if let notebook = entry.snapshot.notebook {
            Group {
                if family == .systemMedium { medium(notebook) } else { small(notebook) }
            }
            .widgetURL(URL(string: "swiftscribe://notebook/\(notebook.id.uuidString)"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "square.and.pencil").font(.title2).foregroundStyle(Color.widgetAccent).widgetAccentable()
                Spacer(minLength: 0)
                Text("Start a notebook").font(.system(.headline, design: .serif)).foregroundStyle(Color.widgetInk)
                Text("Tap to write a quick note.").font(.caption).foregroundStyle(Color.widgetSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(URL(string: "swiftscribe://quicknote"))
        }
    }

    private func small(_ notebook: WidgetSnapshot.Notebook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            WidgetCover(image: entry.cover, clothHex: notebook.clothHex).frame(height: 72)
            Spacer(minLength: 0)
            Text(notebook.title).font(.system(.subheadline, design: .serif).weight(.semibold)).foregroundStyle(Color.widgetInk).lineLimit(2)
            Text("Page \(notebook.page) of \(notebook.pageCount)").widgetMeta()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func medium(_ notebook: WidgetSnapshot.Notebook) -> some View {
        HStack(alignment: .top, spacing: 14) {
            WidgetCover(image: entry.cover, clothHex: notebook.clothHex)
            VStack(alignment: .leading, spacing: 3) {
                Text("Continue writing").widgetMeta(.widgetAccent).widgetAccentable()
                Text(notebook.title).font(.system(.title3, design: .serif).weight(.semibold)).foregroundStyle(Color.widgetInk).lineLimit(2)
                Text("Page \(notebook.page) of \(notebook.pageCount)").widgetMeta()
                Spacer(minLength: 4)
                WeekStrip(days: entry.snapshot.week(containing: entry.date))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WritingWeekView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScribeEntry

    var body: some View {
        let days = entry.snapshot.week(containing: entry.date)
        let pages = days.reduce(0) { $0 + $1.pages }, written = days.count { $0.pages > 0 }
        let run = entry.snapshot.run(endingAt: entry.date)
        Group {
            if family == .accessoryRectangular {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week").font(.headline).widgetAccentable()
                    Text("\(pages) pages")
                    Text("\(written) days").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text("This week").widgetMeta()
                    Text(pages, format: .number).font(.system(size: 40, weight: .semibold, design: .serif)).foregroundStyle(Color.widgetInk)
                        .minimumScaleFactor(0.6).lineLimit(1)
                    Text(String(localized: "widget.pagesCaption", defaultValue: "\(pages) pages")).font(.caption).foregroundStyle(Color.widgetSecondary)
                    Spacer(minLength: 2)
                    WeekStrip(days: days)
                    if run > 1 { Text("\(run) days in a row").widgetMeta() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "swiftscribe://continue"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("This week: \(pages) pages on \(written) days"))
    }
}

struct TodayPageView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScribeEntry

    var body: some View {
        let written = entry.snapshot.pagesByDay[WidgetSnapshot.dayKey(for: entry.date)] ?? 0
        Group {
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Image(systemName: "pencil.line").font(.caption)
                        Text(entry.date, format: .dateTime.day()).font(.system(.title3, design: .serif).weight(.semibold))
                    }
                    .widgetAccentable()
                }
            case .accessoryInline:
                Label("Write today's page", systemImage: "pencil.line")
            default:
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.date, format: .dateTime.weekday(.wide)).widgetMeta(.widgetAccent).widgetAccentable()
                    Text(entry.date, format: .dateTime.day()).font(.system(size: 46, weight: .semibold, design: .serif)).foregroundStyle(Color.widgetInk)
                    Text(entry.date, format: .dateTime.month(.wide)).font(.system(.subheadline, design: .serif)).foregroundStyle(Color.widgetInk)
                    Spacer(minLength: 4)
                    Label(written > 0 ? "Written today" : "Write today's page", systemImage: written > 0 ? "checkmark" : "pencil.line")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.widgetSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: "swiftscribe://today"))
    }
}

/// The notebook's cover as the app drew it, or its cloth colour until one has been written.
struct WidgetCover: View {
    let image: UIImage?
    let clothHex: UInt32

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().widgetAccentedRenderingMode(.fullColor).aspectRatio(3 / 4, contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: clothHex))
                    .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.18)).frame(width: 5) }
                    .aspectRatio(3 / 4, contentMode: .fit)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Seven leaves, one a day: filled when something was written, underlined for today.
struct WeekStrip: View {
    let days: [WidgetSnapshot.Day]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(day.pages > 0 ? Color.widgetInk : Color.widgetInk.opacity(0.12))
                        .frame(height: 14)
                        .widgetAccentable(day.pages > 0)
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 8, weight: day.isToday ? .heavy : .medium))
                        .foregroundStyle(day.isToday ? Color.widgetInk : Color.widgetSecondary)
                }
                .frame(maxWidth: 16)
            }
        }
        .accessibilityHidden(true)
    }
}

extension View {
    func widgetMeta(_ color: Color = .widgetSecondary) -> some View {
        font(.system(.caption2, weight: .semibold).smallCaps()).tracking(0.5).foregroundStyle(color)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }

    static let widgetPaper = adaptive(light: 0xF1EDE4, dark: 0x181613)
    static let widgetInk = adaptive(light: 0x1B2230, dark: 0xECE6DA)
    static let widgetSecondary = adaptive(light: 0x5A6070, dark: 0xA8A194)
    static let widgetAccent = adaptive(light: 0x2747B8, dark: 0x8FA8FF)
}
