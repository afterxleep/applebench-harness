import Foundation

/// Append-only recorder for the run's event stream.
///
/// An actor so events arriving from concurrent sources (agent output, command
/// streaming, grading) are serialized with monotonically increasing sequence
/// numbers. Events are written to `events.jsonl` immediately so a crashed or
/// killed run still leaves a usable trajectory behind.
public actor EventRecorder {
    public let runID: String

    private let fileHandle: FileHandle?
    private var sequence = 0
    private var events: [BenchmarkEvent] = []
    private let encoder: JSONEncoder
    private let clock: @Sendable () -> Date
    /// Called for every event as it is recorded, for callers that want to show
    /// a run moving rather than read the file afterwards.
    ///
    /// An observer, not a second write path: what it is handed is the event
    /// already written to disk, so a live view and the recorded trajectory can
    /// never disagree. It must not be slow — it runs inside the actor, and a
    /// blocking observer stalls the run it is reporting on.
    private let observer: (@Sendable (BenchmarkEvent) -> Void)?

    /// - Parameters:
    ///   - runID: Identifier stamped on every event.
    ///   - fileURL: Destination for the JSONL stream. Pass `nil` to keep
    ///     events in memory only (tests).
    ///   - clock: Injectable time source for deterministic tests.
    public init(
        runID: String,
        fileURL: URL?,
        clock: @escaping @Sendable () -> Date = { Date() },
        observer: (@Sendable (BenchmarkEvent) -> Void)? = nil
    ) throws {
        self.runID = runID
        self.clock = clock
        self.observer = observer

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.encoder = encoder

        if let fileURL {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
            self.fileHandle = try FileHandle(forWritingTo: fileURL)
        } else {
            self.fileHandle = nil
        }
    }

    @discardableResult
    public func record(_ type: BenchmarkEventType, payload: JSONValue = .object([:])) -> BenchmarkEvent {
        sequence += 1
        let event = BenchmarkEvent(
            sequence: sequence,
            timestamp: clock(),
            runID: runID,
            type: type,
            payload: payload
        )
        events.append(event)
        if let fileHandle, var line = try? encoder.encode(event) {
            line.append(0x0A)
            try? fileHandle.write(contentsOf: line)
        }
        // After the write, so anything shown on screen is already durable.
        observer?(event)
        return event
    }

    public func allEvents() -> [BenchmarkEvent] {
        events
    }

    public func close() {
        try? fileHandle?.close()
    }
}

extension JSONEncoder.DateEncodingStrategy {
    /// ISO-8601 with millisecond precision, e.g. `2026-08-08T10:55:42.234Z`.
    static var iso8601WithFractionalSeconds: JSONEncoder.DateEncodingStrategy {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let style = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            try container.encode(date.formatted(style))
        }
    }
}
