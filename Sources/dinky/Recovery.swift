import AppKit
import DinkyLayout
import DinkyPrivate

// Original frames and Spaces are journaled before tiling for disable and crash recovery. Failed restores
// stay journaled for another try unless the window was moved by hand. Normal quit leaves windows in place
// and clears the journal. After a crash, the next launch offers to restore surviving windows. Main thread only.
final class Recovery {
    struct Entry: Codable {
        let id: UInt32
        let pid: pid_t
        let bundleID: String?
        var firstSeen: Date
        let frame: CGRect
        let spaceID: UInt64

        var identity: Window.Identity { .init(id: id, pid: pid, firstSeen: firstSeen) }
    }

    struct Journal: Codable {
        let pid: pid_t
        let launched: Date
        let windows: [Entry]
    }

    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/dinky/journal.json")

    /// How long a restore waits for apps to take their frames. A hung app must not hold up quitting for long.
    private static let answerTimeout: TimeInterval = 3

    /// Windows left behind by a session that crashed, still journaled.
    var recoverable: Int { carried.filter { entries[$0] != nil }.count }

    private let launched = Date()
    private var entries: [UInt32: Entry] = [:]
    private var carried: Set<UInt32> = []
    private var failed = FailedRestores()
    private var model: WindowModel?
    private var recording = false
    private var saveScheduled = false
    private var applier: FrameApplier!

    /// Carries over a crashed session's journal and follows the model, so once `resume()` turns journaling on,
    /// each frame is the one the model read before dinky wrote any. Restores write through the coordinator's
    /// applier, so the minimum sizes it learns have one owner.
    func start(model: WindowModel, applier: FrameApplier) {
        self.model = model
        self.applier = applier
        carryOver()
        model.observe { [weak self] _ in self?.record() }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in self?.record() }
    }

    /// Journals windows from now on. Call before tiling (re)starts. A window a restore could not put back and
    /// that was moved by hand since is journaled again from where it is now.
    func resume() {
        recording = true
        for id in failed.ids where failed.movedByHand(id, now: position(of: id)) { entries[id] = nil }
        failed.clear()
        record()
    }

    /// Complete a normal session without changing any window's frame or Space.
    func finish() {
        recording = false
        entries = [:]
        carried = []
        save()
    }

    /// Stops journaling, moves every journaled window back to its Space, writes its frame, and forgets the
    /// windows put back or that no retry would help (`RestoreProblem.retries`). The rest stay journaled, on disk
    /// too, so the next restore or a `dinky recover` after relaunching tries them again. Blocks until the frames
    /// are written. Returns a summary; what could not be restored is logged.
    @discardableResult
    func restore() -> String {
        recording = false
        guard let model, !entries.isEmpty else { return "nothing to restore" }
        let displays = AppState.shared.displays
        displays.reconcile()
        var problems: [UInt32: RestoreProblem] = [:]  // by window id
        let live = entries.values.sorted { $0.id < $1.id }.filter { entry in
            guard model.windows[entry.id]?.identity == entry.identity else {
                problems[entry.id] = .closed
                return false
            }
            let now = position(of: entry.id)
            // Already in place, possibly on a Space AX cannot reach; or a late answer from an app a try gave up on.
            if now == WindowPosition(frame: entry.frame, spaceID: entry.spaceID) { return false }
            if failed.movedByHand(entry.id, now: now) {
                problems[entry.id] = .movedByHand
                return false
            }
            guard displays.displays.contains(where: { $0.frame.intersects(entry.frame) }) else {
                problems[entry.id] = .displayGone
                return false
            }
            return true
        }
        // Frames first while windows are on screen, then Spaces, then frames again for windows that
        // came back onto a visible Space: AX only reaches windows on a Space that is on screen.
        var results = writeFrames(live)
        let moved = moveBack(live, problems: &problems)
        for (id, result) in writeFrames(live.filter { moved.contains($0.id) }) { results[id] = result }
        for entry in live where results[entry.id]?.matched != true && problems[entry.id] == nil {
            problems[entry.id] = switch results[entry.id] {
            case nil: .noAnswer(seconds: Int(Self.answerTimeout))
            case let result?: result.got.map { .wrongFrame(got: $0, wanted: entry.frame) } ?? .unreadable(wanted: entry.frame)
            }
        }
        let retry = problems.filter(\.value.retries)
        for (id, problem) in problems.sorted(by: { $0.key < $1.key }) {
            fputs("recovery: window \(id): \(problem)\(retry[id] == nil ? "" : ", kept to try again")\n", stderr)
        }
        let summary = "restored \(entries.count - problems.count) of \(entries.count) windows"
            + (problems.isEmpty ? "" : ", see the log for the rest")
        entries = entries.filter { retry[$0.key] != nil }
        carried.formIntersection(entries.keys)
        failed.keep(Set(retry.keys))
        for id in retry.keys { failed.remember(id, at: position(of: id)) }
        save()
        print("recovery: \(summary)")
        fflush(stdout)
        return summary
    }

    // MARK: Journal

    /// Keeps the crashed session's entries whose window still exists, owned by the same app, and first seen
    /// after that app launched. Anything else is a reused window ID and is never touched.
    private func carryOver() {
        guard let model, let data = try? Data(contentsOf: Self.url),
              let journal = try? decoder.decode(Journal.self, from: data), journal.pid != getpid() else { return }
        for var entry in journal.windows {
            guard let window = model.windows[entry.id] else { continue }
            let launched = NSRunningApplication(processIdentifier: entry.pid)?.launchDate ?? .distantPast
            guard window.pid == entry.pid, window.bundleID == entry.bundleID, launched <= entry.firstSeen else {
                fputs("recovery: window \(entry.id) is now another window, not restoring it\n", stderr)
                continue
            }
            // From here on the live model's identity is the one to match.
            entry.firstSeen = window.identity.firstSeen
            entries[entry.id] = entry
            carried.insert(entry.id)
        }
        print("recovery: \(carried.count) windows from the previous session (pid \(journal.pid)) can be restored")
        save()
    }

    /// Journals every normal window not journaled yet, and drops entries whose window is gone.
    private func record() {
        guard recording, let model else { return }
        let before = entries.count
        entries = entries.filter { model.windows[$0.key]?.identity == $0.value.identity }
        var changed = entries.count != before
        for window in model.windows.values where window.isNormal && entries[window.id] == nil {
            entries[window.id] = Entry(id: window.id, pid: window.pid, bundleID: window.bundleID,
                                       firstSeen: window.identity.firstSeen, frame: window.frame, spaceID: window.spaceID)
            changed = true
        }
        if changed { saveSoon() }
    }

    private func saveSoon() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.saveScheduled = false
            self?.save()
        }
    }

    /// Writes the journal, or removes the file when nothing is journaled.
    private func save() {
        guard !entries.isEmpty else {
            try? FileManager.default.removeItem(at: Self.url)
            return
        }
        let journal = Journal(pid: getpid(), launched: launched, windows: entries.values.sorted { $0.id < $1.id })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        try? FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(journal).write(to: Self.url, options: .atomic)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }

    // MARK: Restoring

    /// Where the window server has a window now.
    private func position(of id: UInt32) -> WindowPosition {
        WindowPosition(frame: dinky_window_info(id).frame, spaceID: dinky_window_space_id(id))
    }

    /// Writes the entries' frames, in the current stacking order so nothing is raised. Waits for the results, up
    /// to `answerTimeout`; an app that has not answered by then has no results, and the other apps still do.
    private func writeFrames(_ entries: [Entry]) -> [UInt32: FrameResult] {
        guard !entries.isEmpty else { return [:] }
        let stacking = Dictionary(onScreenOrder().enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let layout = Layout(frames: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.frame) }),
                            order: entries.map(\.id).sorted { (stacking[$0] ?? .max) < (stacking[$1] ?? .max) })
        let results = Results()
        let done = DispatchSemaphore(value: 0)
        applier.apply(layout, pids: Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.pid) }),
                      progress: results.add) { _ in done.signal() }
        _ = done.wait(timeout: .now() + Self.answerTimeout)
        return results.byID
    }

    /// Readbacks as each app reports them. They arrive on background queues, a hung app's possibly after the
    /// restore stopped waiting, so they are only touched under the lock.
    private final class Results: @unchecked Sendable {
        private let lock = NSLock()
        private var results: [UInt32: FrameResult] = [:]

        func add(_ new: [FrameResult]) { lock.withLock { for result in new { results[result.job.id] = result } } }
        var byID: [UInt32: FrameResult] { lock.withLock { results } }
    }

    /// Moves windows that are off their original Space back onto it, if it still exists. Returns the ids that arrived.
    private func moveBack(_ entries: [Entry], problems: inout [UInt32: RestoreProblem]) -> Set<UInt32> {
        let displays = AppState.shared.displays
        var targets: [UInt32: UInt64] = [:]
        for entry in entries where entry.spaceID != 0 && dinky_window_space_id(entry.id) != entry.spaceID {
            var ids = [entry.id]
            if displays.display(containingSpace: entry.spaceID) == nil {
                problems[entry.id] = .spaceGone
            } else if dinky_move_windows_to_space(&ids, 1, entry.spaceID) {
                targets[entry.id] = entry.spaceID
            } else {
                problems[entry.id] = .spaceMoveFailed
            }
        }
        // The bridged move is asynchronous.
        let arrived = { Set(targets.filter { dinky_window_space_id($0.key) == $0.value }.keys) }
        _ = waitUntil(1) { arrived().count == targets.count }
        let done = arrived()
        for id in targets.keys where !done.contains(id) { problems[id] = .didNotArrive }
        return done
    }
}

/// `dinky recover`: asks the running app to restore the windows a crashed session left tiled.
func runRecover() -> Int32 { sendAndPrint("recover") }
