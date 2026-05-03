import CoreLocation
import Foundation
import MapKit

// MARK: - OrchestratorUpdate

/// A snapshot yielded by `SearchOrchestrator` after each completed batch.
///
/// The `jobID` lets the consumer distinguish the current location (update the UI)
/// from background locations (update the cache only).
struct OrchestratorUpdate {
    /// The job that produced this snapshot.
    let jobID: UUID
    /// The search centre for this job.
    let location: CLLocation
    /// Deduplicated, distance-sorted restaurant list accumulated so far.
    let snapshot: [Restaurant]
    /// `true` when this is the final update for this job — all phases are complete.
    ///
    /// Consumers use this to stop showing the "loading more" indicator and to
    /// write the final snapshot to the search cache.
    let isJobComplete: Bool
}

// MARK: - SearchJob

/// All pending work and accumulated results for a single search location.
///
/// `SearchJob` is a value type whose mutable fields advance through three
/// phases: focused batches → scatter nodes → wide-pass batches.
/// The orchestrator holds an array of jobs and mutates them by index.
struct SearchJob {
    // MARK: Identity

    /// Stable identifier used to correlate updates back to this job.
    let id: UUID
    /// The geographic centre being searched.
    let location: CLLocation
    /// Scatter region radius (≈ user's filter radius).
    let focusRadius: Double
    /// Maximum network search radius; also the distance filter for results.
    let networkRadius: Double

    // MARK: Phase 1 — Focused batches

    /// Index of the next focused batch to run (0-based). Equals
    /// `totalFocusedBatches` when all focused batches are complete.
    var nextFocusedBatchIndex: Int = 0

    /// Whether the POI search (run once per job before focused batch 0) is done.
    var poiSearchDone: Bool = false

    // MARK: Phase 2 — Scatter

    /// Queue of scatter nodes awaiting execution.
    ///
    /// New child nodes produced by `executeScatterNode` are prepended so that
    /// depth-first ordering is maintained within each cuisine query.
    var pendingScatterNodes: [RestaurantSearchService.ScatterNode] = []

    // MARK: Phase 3 — Wide pass

    /// Index of the next wide-pass batch to run.
    ///
    /// - `nil`: wide-pass has never started (and will only start if this is the
    ///   current job when all narrow-pass work across all jobs is exhausted).
    /// - `0 ..< totalFocusedBatches`: in progress.
    /// - `≥ totalFocusedBatches`: finished.
    var widePassBatchIndex: Int?

    // MARK: Background flag

    /// `true` when this job was created by `enqueueBackgroundPrefetch` rather
    /// than a user-driven `enqueueLocation` call.
    ///
    /// Background jobs are never promoted to `currentJobID` by `enqueueLocation`;
    /// their updates are routed to the cache rather than the live UI.
    var isBackgroundPrefetch: Bool = false

    // MARK: Accumulated results

    /// Raw `(Restaurant, label)` pairs collected from every executed batch.
    /// Deduplicated on demand when a snapshot is yielded.
    var accumulated: [(Restaurant, String)] = []

    // MARK: Derived geometry

    /// Focused `MKCoordinateRegion` sized to `focusRadius`.
    var focusedRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: focusRadius * 2,
            longitudinalMeters: focusRadius * 2
        )
    }

    /// Wide `MKCoordinateRegion` sized to `networkRadius`.
    var wideRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: networkRadius * 2,
            longitudinalMeters: networkRadius * 2
        )
    }

    // MARK: Phase state helpers

    /// Pre-split cuisine query batches shared by all jobs (computed once).
    static let allBatches: [[(query: String, label: String)]] = {
        let queries = RestaurantSearchService.cuisineQueries
        let batchSize = 15
        return stride(from: 0, to: queries.count, by: batchSize)
            .map { Array(queries[$0 ..< min($0 + batchSize, queries.count)]) }
    }()

    var totalFocusedBatches: Int { Self.allBatches.count }

    /// `true` once all focused batches, the POI search, and all scatter nodes
    /// have been executed for this job.
    var isNarrowPassComplete: Bool {
        poiSearchDone
            && nextFocusedBatchIndex >= totalFocusedBatches
            && pendingScatterNodes.isEmpty
    }

    // MARK: Initialisation

    init(location: CLLocation, focusRadius: Double, networkRadius: Double) {
        id = UUID()
        self.location = location
        self.focusRadius = focusRadius
        self.networkRadius = networkRadius
    }
}

// MARK: - SearchOrchestrator

/// Schedules and executes `RestaurantSearchService` batch primitives across
/// multiple search locations without cancelling in-flight MapKit requests.
///
/// ## Scheduling Rules (in priority order)
///
/// Between every `withTaskGroup` batch the orchestrator re-evaluates which
/// job to serve next:
///
/// 1. **Focused batches + POI search** — processed for all jobs, highest-priority
///    job first. The current location always has distance 0 (highest priority);
///    other jobs are ordered by ascending distance to the current location.
/// 2. **Scatter nodes** — after all focused batches are exhausted across all jobs,
///    scatter nodes are processed with the same distance-based priority.
/// 3. **Wide-pass batches** — only *started* for the current location once all
///    narrow-pass work (rules 1 + 2) is complete across all jobs. A wide-pass
///    that was already in progress for a demoted job survives the location change
///    and runs after all narrow work is done, ordered by distance to the current
///    location.
///
/// ## Location Changes
///
/// Call `enqueueLocation(_:focusRadius:)` whenever the search location changes.
/// The orchestrator finishes the current in-flight `withTaskGroup` batch (≈ 200 ms),
/// then immediately switches to the new location's work. No in-flight MapKit
/// requests are cancelled.
///
/// ## Consuming Results
///
/// ```swift
/// orchestrator.start()
/// for await update in orchestrator.updates {
///     if update.jobID == currentJobID {
///         restaurants = update.snapshot   // update UI
///     } else {
///         updateCache(for: update.location, restaurants: update.snapshot)
///     }
/// }
/// ```
actor SearchOrchestrator {
    // MARK: - Constants

    /// Network search radius used for all jobs (10 km).
    static let networkRadius: Double = 10_000

    /// Two locations within this distance (metres) are treated as identical.
    static let sameLocationThreshold: Double = 50.0

    /// Pause inserted between consecutive batches.
    ///
    /// This gives MapKit time to breathe and prevents the rate limiter from
    /// throttling the new location's queries when the previous location's
    /// in-flight requests are still completing.
    private static let batchDelayNanoseconds: UInt64 = 200_000_000 // 200 ms

    // MARK: - Dependencies

    private let searchService: RestaurantSearchService

    // MARK: - Job Queue

    /// All active jobs. There is no enforced ordering in this array; priority
    /// is computed dynamically in `jobsSortedByPriority()`.
    ///
    /// Declared `internal` so that `SearchOrchestratorTests` can build scheduling
    /// scenarios without making real MapKit requests.
    var jobs: [SearchJob] = []

    /// ID of the job corresponding to the user's current location.
    private(set) var currentJobID: UUID?

    // MARK: - Run Loop Signalling

    /// Resumed by `enqueueLocation` to wake a suspended run loop.
    private var workAvailableContinuation: CheckedContinuation<Void, Never>?

    // MARK: - Result Stream

    private var updateContinuation: AsyncStream<OrchestratorUpdate>.Continuation?

    /// Stream of deduplicated restaurant snapshots, one update per completed batch.
    ///
    /// Each `OrchestratorUpdate` carries the originating `jobID` so the consumer
    /// can decide whether to refresh the UI or update the cache silently.
    ///
    /// Declared `nonisolated` so it can be iterated from any actor context
    /// (e.g. `@MainActor`) without crossing the actor boundary.
    nonisolated let updates: AsyncStream<OrchestratorUpdate>

    // MARK: - Initialisation

    /// Creates a new orchestrator backed by the given search service.
    ///
    /// Call `start()` once after initialisation to begin the run loop.
    ///
    /// - Parameter searchService: The search service to use for MapKit requests.
    ///   Defaults to a fresh `RestaurantSearchService` instance.
    init(searchService: RestaurantSearchService = RestaurantSearchService()) {
        self.searchService = searchService
        var continuation: AsyncStream<OrchestratorUpdate>.Continuation?
        updates = AsyncStream { continuation = $0 }
        updateContinuation = continuation
    }

    // MARK: - Public Interface

    /// Starts the internal run loop.
    ///
    /// Call exactly once after initialisation. The loop runs indefinitely,
    /// processing one batch at a time and yielding an `OrchestratorUpdate`
    /// to `updates` after each batch.
    func start() {
        Task { await runLoop() }
    }

    /// Enqueues a new location as the highest-priority search job.
    ///
    /// If an existing job is within `sameLocationThreshold` metres of `location`
    /// it is promoted to current (preserving all accumulated state and any
    /// in-progress wide-pass) rather than creating a duplicate entry.
    ///
    /// Wide-pass rule on demotion: the outgoing current job keeps its
    /// `widePassBatchIndex` unchanged.
    /// - If `nil` (wide-pass never started) → it stays `nil`; the wide-pass
    ///   will never start for that job.
    /// - If non-`nil` (wide-pass in progress) → it resumes after all narrow-pass
    ///   work across all jobs is exhausted.
    ///
    /// - Parameters:
    ///   - location: The new search centre.
    ///   - focusRadius: Scatter region radius (typically the user's filter radius).
    /// - Returns: The `UUID` of the new current job.
    @discardableResult
    func enqueueLocation(_ location: CLLocation, focusRadius: Double) -> UUID {
        // Promote an existing *user-driven* job if within the same-location threshold.
        // Background prefetch jobs are intentionally excluded so they are never
        // accidentally promoted to the current UI job.
        if let idx = jobs.firstIndex(where: {
            !$0.isBackgroundPrefetch &&
                $0.location.distance(from: location) < Self.sameLocationThreshold
        }) {
            currentJobID = jobs[idx].id
            signalWorkAvailable()
            return jobs[idx].id
        }

        // Create a fresh job for the new location
        let job = SearchJob(
            location: location,
            focusRadius: focusRadius,
            networkRadius: Self.networkRadius
        )
        jobs.append(job)
        currentJobID = job.id
        signalWorkAvailable()
        return job.id
    }

    /// Enqueues a background prefetch job for the given location and focus radius.
    ///
    /// Background prefetch jobs run after all user-driven (current) narrow-pass
    /// work is exhausted, providing better scatter coverage for radii beyond the
    /// user's current filter. They do **not** update `currentJobID` and their
    /// updates are routed to the cache rather than the live UI.
    ///
    /// Unlike `enqueueLocation`, this method always creates a new job regardless
    /// of whether a nearby job already exists. Callers are responsible for
    /// avoiding redundant enqueues (e.g. by checking the ViewModel's cache first).
    ///
    /// - Parameters:
    ///   - location: The search centre for the background job.
    ///   - focusRadius: Scatter region radius for this background pass.
    func enqueueBackgroundPrefetch(location: CLLocation, focusRadius: Double) {
        var job = SearchJob(
            location: location,
            focusRadius: focusRadius,
            networkRadius: Self.networkRadius
        )
        job.isBackgroundPrefetch = true
        jobs.append(job)
        signalWorkAvailable()
    }

    // MARK: - Test Helpers

    /// Sets `poiSearchDone` on the job with the given ID.
    ///
    /// Intended for use in unit tests only — not called by production code.
    func setJobPoiSearchDone(_ done: Bool, forJobID id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].poiSearchDone = done
    }

    /// Sets `nextFocusedBatchIndex` on the job with the given ID.
    ///
    /// Intended for use in unit tests only — not called by production code.
    func setJobNextFocusedBatchIndex(_ index: Int, forJobID id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].nextFocusedBatchIndex = index
    }

    /// Sets `pendingScatterNodes` on the job with the given ID.
    ///
    /// Intended for use in unit tests only — not called by production code.
    func setJobPendingScatterNodes(
        _ nodes: [RestaurantSearchService.ScatterNode],
        forJobID id: UUID
    ) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].pendingScatterNodes = nodes
    }

    /// Sets `widePassBatchIndex` on the job with the given ID.
    ///
    /// Intended for use in unit tests only — not called by production code.
    func setJobWidePassBatchIndex(_ index: Int?, forJobID id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].widePassBatchIndex = index
    }

    // MARK: - Run Loop

    private func runLoop() async {
        while true {
            guard let work = pickNextWork() else {
                // Nothing to do — suspend until enqueueLocation signals new work
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    workAvailableContinuation = cont
                }
                continue
            }

            await execute(work)
            try? await Task.sleep(nanoseconds: Self.batchDelayNanoseconds)
        }
    }

    private func signalWorkAvailable() {
        workAvailableContinuation?.resume()
        workAvailableContinuation = nil
    }

    // MARK: - Work Scheduling

    /// Work item produced by `pickNextWork` and consumed by `execute`.
    enum BatchWork {
        case poiSearch(jobID: UUID)
        case focusedBatch(jobID: UUID, batchIndex: Int)
        case scatterNode(jobID: UUID)
        case wideBatch(jobID: UUID, batchIndex: Int)
    }

    /// Selects the next unit of work according to the scheduling rules.
    ///
    /// Removes completed jobs first so they never pollute the priority sort.
    /// Returns `nil` only when every job is fully complete.
    ///
    /// Declared `internal` (not `private`) so `SearchOrchestratorTests` can
    /// verify scheduling decisions without starting the real run loop.
    func pickNextWork() -> BatchWork? {
        removeCompletedJobs()
        guard !jobs.isEmpty else { return nil }

        let prioritised = jobsSortedByPriority()

        // Rule 1: POI search (runs before the first focused batch for each job)
        if let job = prioritised.first(where: { !$0.poiSearchDone }) {
            return .poiSearch(jobID: job.id)
        }

        // Rule 1 (continued): focused batches
        if let job = prioritised.first(where: { $0.nextFocusedBatchIndex < $0.totalFocusedBatches }) {
            return .focusedBatch(jobID: job.id, batchIndex: job.nextFocusedBatchIndex)
        }

        // Rule 2: scatter nodes
        if let job = prioritised.first(where: { !$0.pendingScatterNodes.isEmpty }) {
            return .scatterNode(jobID: job.id)
        }

        // Rules 3a/3b only apply when ALL narrow-pass work is done
        guard prioritised.allSatisfy(\.isNarrowPassComplete) else { return nil }

        // Rule 3a: resume an already-started wide-pass (any job, distance-ordered)
        if let job = prioritised.first(where: {
            guard let idx = $0.widePassBatchIndex else { return false }
            return idx < $0.totalFocusedBatches
        }) {
            return .wideBatch(jobID: job.id, batchIndex: job.widePassBatchIndex!)
        }

        // Rule 3b: start the wide-pass for the current job (first time only)
        if let idx = jobs.firstIndex(where: { $0.id == currentJobID }),
           jobs[idx].focusRadius < jobs[idx].networkRadius,
           jobs[idx].widePassBatchIndex == nil
        {
            jobs[idx].widePassBatchIndex = 0
            return .wideBatch(jobID: jobs[idx].id, batchIndex: 0)
        }

        return nil
    }

    /// Returns all jobs sorted by distance to the current job (current = 0).
    private func jobsSortedByPriority() -> [SearchJob] {
        let currentLocation = jobs.first(where: { $0.id == currentJobID })?.location
        return jobs.sorted { lhs, rhs in
            if lhs.id == currentJobID { return true }
            if rhs.id == currentJobID { return false }
            guard let ref = currentLocation else { return false }
            return lhs.location.distance(from: ref) < rhs.location.distance(from: ref)
        }
    }

    /// Removes jobs that have no remaining work to execute.
    ///
    /// A job is removed when:
    /// - Its narrow pass is complete AND no wide pass is applicable
    ///   (`focusRadius >= networkRadius`), OR
    /// - Its narrow pass is complete AND its wide pass has finished, OR
    /// - Its narrow pass is complete AND it is NOT the current job AND its
    ///   wide-pass has never started (it never will — abandon it).
    private func removeCompletedJobs() {
        jobs.removeAll { job in
            guard job.isNarrowPassComplete else { return false }
            if job.focusRadius >= job.networkRadius { return true }
            if let wideIdx = job.widePassBatchIndex, wideIdx >= job.totalFocusedBatches { return true }
            if job.id != currentJobID, job.widePassBatchIndex == nil { return true }
            return false
        }
    }

    // MARK: - Work Execution

    private func execute(_ work: BatchWork) async {
        switch work {
        case let .poiSearch(jobID):
            await executePOISearch(jobID: jobID)
        case let .focusedBatch(jobID, batchIndex):
            await executeFocusedBatch(jobID: jobID, batchIndex: batchIndex)
        case let .scatterNode(jobID):
            await executeNextScatterNode(jobID: jobID)
        case let .wideBatch(jobID, batchIndex):
            await executeWideBatch(jobID: jobID, batchIndex: batchIndex)
        }
    }

    /// Runs the POI-category search for the given job and marks it complete.
    private func executePOISearch(jobID: UUID) async {
        guard let snapshot = jobSnapshot(jobID: jobID) else { return }

        let results = await searchService.executePOISearch(
            region: snapshot.wideRegion,
            location: snapshot.location,
            networkRadius: snapshot.networkRadius
        )

        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].accumulated.append(contentsOf: results)
        jobs[idx].poiSearchDone = true
        yieldSnapshot(jobID: jobID)
    }

    /// Runs one focused-query batch for the given job and advances its batch index.
    ///
    /// Saturated queries from the batch are converted into root scatter nodes
    /// and prepended to the job's `pendingScatterNodes` queue.
    private func executeFocusedBatch(jobID: UUID, batchIndex: Int) async {
        guard let snapshot = jobSnapshot(jobID: jobID) else { return }
        guard batchIndex < snapshot.totalFocusedBatches else { return }

        let batch = SearchJob.allBatches[batchIndex]
        let result = await searchService.executeFocusedBatch(
            queries: batch,
            region: snapshot.focusedRegion,
            location: snapshot.location,
            networkRadius: snapshot.networkRadius
        )

        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].accumulated.append(contentsOf: result.results)
        jobs[idx].nextFocusedBatchIndex = batchIndex + 1

        let newNodes = result.saturatedQueries.map { saturated in
            RestaurantSearchService.ScatterNode(
                query: saturated.query,
                label: saturated.label,
                centre: snapshot.location.coordinate,
                radius: snapshot.focusRadius,
                depth: 0
            )
        }
        jobs[idx].pendingScatterNodes.append(contentsOf: newNodes)
        yieldSnapshot(jobID: jobID)
    }

    /// Dequeues and executes the first pending scatter node for the given job.
    ///
    /// Child nodes returned by the service are prepended to the pending queue
    /// so that depth-first ordering is preserved within each cuisine query.
    private func executeNextScatterNode(jobID: UUID) async {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }),
              !jobs[idx].pendingScatterNodes.isEmpty else { return }

        let node = jobs[idx].pendingScatterNodes.removeFirst()
        let location = jobs[idx].location
        let networkRadius = jobs[idx].networkRadius

        let result = await searchService.executeScatterNode(
            node,
            userLocation: location,
            maxRadius: networkRadius
        )

        guard let currentIdx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[currentIdx].accumulated.append(contentsOf: result.results)
        // Prepend children to maintain depth-first order within this cuisine
        jobs[currentIdx].pendingScatterNodes.insert(contentsOf: result.childNodes, at: 0)
        yieldSnapshot(jobID: jobID)
    }

    /// Runs one wide-pass batch for the given job and advances its wide-pass index.
    private func executeWideBatch(jobID: UUID, batchIndex: Int) async {
        guard let snapshot = jobSnapshot(jobID: jobID) else { return }
        guard batchIndex < snapshot.totalFocusedBatches else { return }

        let batch = SearchJob.allBatches[batchIndex]
        let results = await searchService.executeWideBatch(
            queries: batch,
            region: snapshot.wideRegion,
            location: snapshot.location,
            networkRadius: snapshot.networkRadius
        )

        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].accumulated.append(contentsOf: results)
        jobs[idx].widePassBatchIndex = batchIndex + 1
        yieldSnapshot(jobID: jobID)
    }

    // MARK: - Helpers

    /// Returns a stable copy of the job's current state before an `await`.
    ///
    /// Because actor re-entrancy can cause the `jobs` array to shift after an
    /// `await`, any values needed post-await are re-fetched by index lookup.
    /// Values needed pre-await are captured via this snapshot.
    private func jobSnapshot(jobID: UUID) -> SearchJob? {
        jobs.first(where: { $0.id == jobID })
    }

    /// Deduplicates the job's accumulated results and yields an update.
    private func yieldSnapshot(jobID: UUID) {
        guard let job = jobs.first(where: { $0.id == jobID }) else { return }
        let snapshot = RestaurantSearchService.deduplicateAndSort(job.accumulated)
        updateContinuation?.yield(OrchestratorUpdate(
            jobID: job.id,
            location: job.location,
            snapshot: snapshot,
            isJobComplete: checkIsJobComplete(job)
        ))
    }

    /// Returns `true` when all scheduled work for `job` has been executed.
    private func checkIsJobComplete(_ job: SearchJob) -> Bool {
        guard job.isNarrowPassComplete else { return false }
        if job.focusRadius >= job.networkRadius { return true }
        guard let wideIdx = job.widePassBatchIndex else { return false }
        return wideIdx >= job.totalFocusedBatches
    }
}
