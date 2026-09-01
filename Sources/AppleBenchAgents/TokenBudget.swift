import AppleBenchCore
import Foundation

/// Counts an agent's token spend while it is still running, so a task can be
/// stopped on budget instead of only on the clock.
///
/// The wall clock is a poor proxy for cost. A model can burn a large budget in
/// two minutes or sit nearly idle for twenty, so a timeout generous enough for
/// a hard task is also generous enough for an expensive failure. Over a suite,
/// almost all the spend is in tasks the model will not solve, each running to
/// its full limit.
///
/// Counting reuses the adapter's own parser rather than a second extraction,
/// and sums per-step reports the same way the post-run accounting does, so the
/// number this stops on is the number the run reports.
actor TokenBudget {
    private let cap: Int
    private let parser: any AgentOutputParser
    /// Output arrives in arbitrary chunks, so a line can be split across two
    /// of them. Counting a partial line would read "99" out of "990".
    private var pending = ""
    private var task: Task<ProcessExecutionResult, any Error>?

    private(set) var spent = 0
    private(set) var isExceeded = false

    init(cap: Int, parser: any AgentOutputParser) {
        self.cap = cap
        self.parser = parser
    }

    /// Hands over the process task to cancel when the budget trips. The task
    /// cannot exist before the output handler that feeds this budget, so it is
    /// attached immediately after being created; output arriving in that gap
    /// still counts and trips on the next chunk.
    func attach(_ task: Task<ProcessExecutionResult, any Error>) {
        self.task = task
        if isExceeded { task.cancel() }
    }

    func consume(_ text: String) {
        pending += text
        while let newline = pending.firstIndex(of: "\n") {
            let line = String(pending[pending.startIndex..<newline])
            pending = String(pending[pending.index(after: newline)...])
            guard let event = parser.parse(line: line), let usage = event.usage else { continue }
            spent += usage.totalTokens ?? ((usage.inputTokens ?? 0) + (usage.outputTokens ?? 0))
        }
        guard !isExceeded, spent >= cap else { return }
        isExceeded = true
        // Cancelling tears down the whole process group, the same path the
        // wall-clock timeout uses.
        task?.cancel()
    }
}
