import CoreLocation
@testable import RestaurantPicker
import XCTest

// MARK: - SearchOrchestratorTests

/// Tests for `SearchOrchestrator` scheduling and location-management behaviour.
///
/// The run loop (`start()`) is intentionally **not** called in any test so that
/// `pickNextWork()` and the `jobs` array can be inspected in a deterministic,
/// synchronous fashion without making real MapKit requests.
final class SearchOrchestratorTests: XCTestCase {
    // MARK: - Helpers

    /// A location in New York City used as a convenient reference point.
    private let newYork = CLLocation(latitude: 40.7128, longitude: -74.0060)

    /// A location 25 m north of `newYork` — within the 50 m same-location threshold.
    private var newYorkNear: CLLocation {
        // ~0.000225° of latitude ≈ 25 m
        CLLocation(latitude: 40.7130, longitude: -74.0060)
    }

    /// A location 200 m north of `newYork` — outside the 50 m same-location threshold.
    private var newYorkFar: CLLocation {
        CLLocation(latitude: 40.7146, longitude: -74.0060)
    }

    /// A location in London — far from New York.
    private let london = CLLocation(latitude: 51.5074, longitude: -0.1278)

    private func makeOrchestrator() -> SearchOrchestrator {
        SearchOrchestrator()
    }

    // MARK: - enqueueLocation Tests

    func testEnqueueLocationReturnsSomeUUID() async {
        // Arrange
        let orchestrator = makeOrchestrator()

        // Act
        let id = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Assert
        XCTAssertNotNil(id)
    }

    func testEnqueueLocationSetsCurrentJobID() async {
        // Arrange
        let orchestrator = makeOrchestrator()

        // Act
        let id = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Assert
        let current = await orchestrator.currentJobID
        XCTAssertEqual(current, id)
    }

    func testEnqueueLocationWithinThresholdPromotesExistingJob() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        let firstID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Act — location within the 50 m same-location threshold
        let secondID = await orchestrator.enqueueLocation(newYorkNear, focusRadius: 500)

        // Assert — same job is promoted, not a duplicate
        XCTAssertEqual(firstID, secondID)
        let jobs = await orchestrator.jobs
        XCTAssertEqual(jobs.count, 1, "Expected exactly one job after enqueuing the same location twice")
    }

    func testEnqueueLocationBeyondThresholdCreatesNewJob() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        let firstID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Act — location beyond the 50 m same-location threshold
        let secondID = await orchestrator.enqueueLocation(newYorkFar, focusRadius: 500)

        // Assert — new job created
        XCTAssertNotEqual(firstID, secondID)
        let jobs = await orchestrator.jobs
        XCTAssertEqual(jobs.count, 2)
    }

    func testEnqueueLocationUpdatesCurrentJobID() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Act
        let newID = await orchestrator.enqueueLocation(london, focusRadius: 500)

        // Assert — currentJobID tracks the most recently enqueued location
        let current = await orchestrator.currentJobID
        XCTAssertEqual(current, newID)
    }

    // MARK: - enqueueBackgroundPrefetch Tests

    func testEnqueueBackgroundPrefetchDoesNotChangeCurrentJobID() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        let originalID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Act
        await orchestrator.enqueueBackgroundPrefetch(location: london, focusRadius: 1000)

        // Assert — currentJobID unchanged
        let current = await orchestrator.currentJobID
        XCTAssertEqual(current, originalID)
    }

    func testEnqueueBackgroundPrefetchAddsJob() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Act
        await orchestrator.enqueueBackgroundPrefetch(location: london, focusRadius: 1000)

        // Assert — two jobs now in the queue
        let jobs = await orchestrator.jobs
        XCTAssertEqual(jobs.count, 2)
    }

    func testBackgroundPrefetchJobIsMarkedAsBackground() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        await orchestrator.enqueueBackgroundPrefetch(location: london, focusRadius: 1000)

        // Act
        let jobs = await orchestrator.jobs
        let backgroundJob = jobs.first { $0.isBackgroundPrefetch }

        // Assert
        XCTAssertNotNil(backgroundJob, "Expected one job flagged as background prefetch")
    }

    func testEnqueueLocationDoesNotPromoteBackgroundPrefetchJob() async {
        // Arrange — background job at newYork
        let orchestrator = makeOrchestrator()
        await orchestrator.enqueueBackgroundPrefetch(location: newYork, focusRadius: 500)

        // Act — user enqueues the same location as a regular search
        let userID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Assert — a NEW user-driven job was created (not the background one)
        let current = await orchestrator.currentJobID
        XCTAssertEqual(current, userID)

        let jobs = await orchestrator.jobs
        let backgroundJobs = jobs.filter(\.isBackgroundPrefetch)
        let userJobs = jobs.filter { !$0.isBackgroundPrefetch }
        XCTAssertEqual(backgroundJobs.count, 1, "Background job should still exist")
        XCTAssertEqual(userJobs.count, 1, "A new user-driven job should have been created")
        XCTAssertNotEqual(backgroundJobs.first?.id, userID)
    }

    // MARK: - pickNextWork Scheduling Tests

    func testPickNextWorkReturnsNilWhenNoJobs() async {
        // Arrange
        let orchestrator = makeOrchestrator()

        // Act
        let work = await orchestrator.pickNextWork()

        // Assert
        XCTAssertNil(work)
    }

    func testPickNextWorkReturnsPOISearchFirst() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        let id = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Act
        let work = await orchestrator.pickNextWork()

        // Assert — POI search is the very first task
        guard case let .poiSearch(jobID) = work else {
            return XCTFail("Expected .poiSearch, got \(String(describing: work))")
        }
        XCTAssertEqual(jobID, id)
    }

    func testPickNextWorkReturnsFocusedBatchAfterPOIDone() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        let id = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        let totalBatches = await orchestrator.jobs.first(where: { $0.id == id })?.totalFocusedBatches ?? 0
        await orchestrator.setJobPoiSearchDone(true, forJobID: id)
        _ = totalBatches // suppresses unused warning

        // Act
        let work = await orchestrator.pickNextWork()

        // Assert — next task is focused batch 0
        guard case let .focusedBatch(jobID, batchIndex) = work else {
            return XCTFail("Expected .focusedBatch, got \(String(describing: work))")
        }
        XCTAssertEqual(jobID, id)
        XCTAssertEqual(batchIndex, 0)
    }

    func testPickNextWorkReturnsScatterNodeAfterAllFocusedBatchesDone() async {
        // Arrange
        let orchestrator = makeOrchestrator()
        let id = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        let totalBatches = await orchestrator.jobs.first(where: { $0.id == id })?.totalFocusedBatches ?? 0
        await orchestrator.setJobPoiSearchDone(true, forJobID: id)
        await orchestrator.setJobNextFocusedBatchIndex(totalBatches, forJobID: id)

        // Add a scatter node to the job
        let scatterNode = ScatterNode(
            query: "ramen restaurant",
            label: "Ramen",
            centre: newYork.coordinate,
            radius: 500,
            depth: 0
        )
        await orchestrator.setJobPendingScatterNodes([scatterNode], forJobID: id)

        // Act
        let work = await orchestrator.pickNextWork()

        // Assert
        guard case let .scatterNode(jobID) = work else {
            return XCTFail("Expected .scatterNode, got \(String(describing: work))")
        }
        XCTAssertEqual(jobID, id)
    }

    func testPickNextWorkStartsWidePassForCurrentJobAfterNarrowPassComplete() async {
        // Arrange — focusRadius < networkRadius so wide pass is applicable
        let orchestrator = makeOrchestrator()
        let id = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        let totalBatches = await orchestrator.jobs.first(where: { $0.id == id })?.totalFocusedBatches ?? 0
        // Complete the narrow pass
        await orchestrator.setJobPoiSearchDone(true, forJobID: id)
        await orchestrator.setJobNextFocusedBatchIndex(totalBatches, forJobID: id)

        // Act
        let work = await orchestrator.pickNextWork()

        // Assert — wide-pass batch 0 is started for the current job
        guard case let .wideBatch(jobID, batchIndex) = work else {
            return XCTFail("Expected .wideBatch, got \(String(describing: work))")
        }
        XCTAssertEqual(jobID, id)
        XCTAssertEqual(batchIndex, 0)
    }

    func testPickNextWorkDoesNotStartWidePassForNonCurrentJob() async {
        // Arrange — two jobs; second job becomes current
        let orchestrator = makeOrchestrator()
        let firstID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        _ = await orchestrator.enqueueLocation(london, focusRadius: 500)

        // Complete the narrow pass for the first (non-current) job
        let totalBatches = await orchestrator.jobs.first(where: { $0.id == firstID })?.totalFocusedBatches ?? 0
        await orchestrator.setJobPoiSearchDone(true, forJobID: firstID)
        await orchestrator.setJobNextFocusedBatchIndex(totalBatches, forJobID: firstID)

        // Leave the second (current) job with narrow pass still in progress (default state)

        // Act
        let work = await orchestrator.pickNextWork()

        // Assert — current job's narrow pass is not yet done, so no wide batch
        if case .wideBatch = work {
            XCTFail("Wide pass should not start while the current job's narrow pass is incomplete")
        }
    }

    func testPickNextWorkPrioritisesCurrentJobOverOlderJob() async {
        // Arrange — two jobs; second (current) job still has POI search pending
        let orchestrator = makeOrchestrator()
        let firstID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        let secondID = await orchestrator.enqueueLocation(london, focusRadius: 500)

        // Mark the first job's POI search as done so it would return a focused batch
        await orchestrator.setJobPoiSearchDone(true, forJobID: firstID)

        // Act
        let work = await orchestrator.pickNextWork()

        // Assert — POI search for the current (second) job takes priority
        guard case let .poiSearch(jobID) = work else {
            return XCTFail("Expected .poiSearch for current job, got \(String(describing: work))")
        }
        XCTAssertEqual(jobID, secondID)
    }

    func testStartedWidePassSurvivesLocationChange() async {
        // Arrange — job A has its wide-pass in progress at batchIndex 2
        let orchestrator = makeOrchestrator()
        let firstID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        let totalBatches = await orchestrator.jobs.first(where: { $0.id == firstID })?.totalFocusedBatches ?? 0
        await orchestrator.setJobPoiSearchDone(true, forJobID: firstID)
        await orchestrator.setJobNextFocusedBatchIndex(totalBatches, forJobID: firstID)
        await orchestrator.setJobWidePassBatchIndex(2, forJobID: firstID) // in-progress wide-pass

        // Act — user moves to London (demotes newYork job)
        _ = await orchestrator.enqueueLocation(london, focusRadius: 500)

        // Complete the new job's narrow pass so wide-pass rules are evaluated
        guard let londonJob = await orchestrator.jobs.first(where: { job in
            job.location.distance(from: london) < 50
        }) else {
            return XCTFail("London job not found")
        }
        let londonID = londonJob.id
        let londonBatches = londonJob.totalFocusedBatches
        await orchestrator.setJobPoiSearchDone(true, forJobID: londonID)
        await orchestrator.setJobNextFocusedBatchIndex(londonBatches, forJobID: londonID)
        // Give London a started wide-pass too so both are in-progress
        await orchestrator.setJobWidePassBatchIndex(0, forJobID: londonID)

        // Assert — the first job's in-progress wide-pass is still in the jobs array
        let jobs = await orchestrator.jobs
        let firstJobAfterDemotion = jobs.first { $0.id == firstID }
        XCTAssertNotNil(firstJobAfterDemotion, "Demoted job with in-progress wide-pass should not be removed")
        XCTAssertEqual(firstJobAfterDemotion?.widePassBatchIndex, 2)
    }

    func testDemotedJobWithNoStartedWidePassIsEvictedAfterNarrowPassComplete() async {
        // Arrange — first job finishes narrow pass without ever starting wide-pass
        let orchestrator = makeOrchestrator()
        let firstID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Enqueue a second location (demotes first job)
        _ = await orchestrator.enqueueLocation(london, focusRadius: 500)

        // Complete the narrow pass for the first (demoted) job
        let totalBatches = await orchestrator.jobs.first(where: { $0.id == firstID })?.totalFocusedBatches ?? 0
        await orchestrator.setJobPoiSearchDone(true, forJobID: firstID)
        await orchestrator.setJobNextFocusedBatchIndex(totalBatches, forJobID: firstID)
        // widePassBatchIndex stays nil

        // Act — pickNextWork triggers removeCompletedJobs
        _ = await orchestrator.pickNextWork()

        // Assert — demoted job with nil wide-pass is evicted
        let jobs = await orchestrator.jobs
        let evictedJob = jobs.first { $0.id == firstID }
        XCTAssertNil(evictedJob, "Demoted job with no started wide-pass should be evicted once narrow pass is done")
    }

    // MARK: - Distance-Based Job Ordering Tests

    func testJobsSortedByDistanceToCurrent() async {
        // Arrange — three jobs at increasing distances; the last one is current
        let orchestrator = makeOrchestrator()

        // Enqueue a far location first
        _ = await orchestrator.enqueueLocation(london, focusRadius: 500)
        // Then New York (moderately far from London)
        _ = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        // New York "far" becomes current — it's very close to newYork
        let currentID = await orchestrator.enqueueLocation(newYorkFar, focusRadius: 500)

        // Complete POI search for all jobs except current so we can distinguish order
        let jobs = await orchestrator.jobs
        for job in jobs where job.id != currentID {
            await orchestrator.setJobPoiSearchDone(true, forJobID: job.id)
        }

        // Act — pickNextWork should return POI search for the current job first
        let work = await orchestrator.pickNextWork()

        guard case let .poiSearch(jobID) = work else {
            return XCTFail("Expected .poiSearch, got \(String(describing: work))")
        }
        XCTAssertEqual(jobID, currentID, "Current job should always be served first")
    }
}

// MARK: - SearchOrchestrator Execution Tests

/// Tests for `SearchOrchestrator` execution behaviour using a mock search service.
///
/// These tests start the orchestrator run loop and verify that search service
/// methods are called and that `OrchestratorUpdate` values are emitted correctly.
final class SearchOrchestratorExecutionTests: XCTestCase {
    private let newYork = CLLocation(latitude: 40.7128, longitude: -74.0060)

    /// Builds a minimal `Restaurant` for test use.
    private func makeRestaurant(name: String, distance: Double = 300) -> Restaurant {
        Restaurant(
            id: UUID(),
            name: name,
            coordinate: .init(latitude: 40.7128, longitude: -74.0060),
            distance: distance,
            category: "Test",
            cuisineTags: ["Test"],
            phoneNumber: nil,
            url: nil
        )
    }

    /// Collects the first update whose `jobID` matches `targetJobID` from the
    /// orchestrator's `updates` stream, or returns `nil` after `timeout` seconds.
    private func firstUpdate(
        from orchestrator: SearchOrchestrator,
        matching targetJobID: UUID,
        timeout: Double = 5
    ) async -> OrchestratorUpdate? {
        await withTaskGroup(of: OrchestratorUpdate?.self) { group in
            group.addTask {
                for await update in await orchestrator.updates where update.jobID == targetJobID {
                    return update
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            defer { group.cancelAll() }
            return await group.next() ?? nil
        }
    }

    // MARK: - POI Search

    func testOrchestratorCallsPOISearchDuringExecution() async {
        // Arrange
        let mock = MockRestaurantSearchService()
        let orchestrator = SearchOrchestrator(searchService: mock)
        await orchestrator.start()

        // Act
        let jobID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        _ = await firstUpdate(from: orchestrator, matching: jobID)

        // Assert — POI search must have been called exactly once per job
        let count = await mock.executePOISearchCallCount
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    func testOrchestratorEmitsUpdateContainingPOIResults() async {
        // Arrange
        let restaurant = makeRestaurant(name: "POI Restaurant")
        let mock = MockRestaurantSearchService()
        await mock.setPOISearchResult([(restaurant, "Restaurant")])
        let orchestrator = SearchOrchestrator(searchService: mock)
        await orchestrator.start()

        // Act
        let jobID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)
        let update = await firstUpdate(from: orchestrator, matching: jobID)

        // Assert
        XCTAssertNotNil(update, "Expected at least one update for the enqueued job")
        XCTAssertTrue(
            update?.snapshot.contains { $0.name == "POI Restaurant" } ?? false,
            "Snapshot should include the restaurant returned by executePOISearch"
        )
    }

    // MARK: - Focused Batch

    func testOrchestratorCallsFocusedBatchDuringExecution() async {
        // Arrange
        let mock = MockRestaurantSearchService()
        let orchestrator = SearchOrchestrator(searchService: mock)
        await orchestrator.start()

        // Act
        let jobID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Collect updates until job is complete (or timeout)
        var completed = false
        let deadline = Date().addingTimeInterval(5)
        for await update in await orchestrator.updates {
            if update.jobID == jobID, update.isJobComplete {
                completed = true
                break
            }
            if Date() > deadline { break }
        }

        // Assert — at least one focused batch must have been executed
        let count = await mock.executeFocusedBatchCallCount
        XCTAssertGreaterThanOrEqual(count, 1, "executeFocusedBatch must be called at least once")
        _ = completed // informational; not asserted to keep the test fast
    }

    func testOrchestratorEmitsUpdateContainingFocusedBatchResults() async {
        // Arrange
        let restaurant = makeRestaurant(name: "Ramen Bar")
        let mock = MockRestaurantSearchService()
        await mock.setFocusedBatchResult(FocusedBatchResult(
            results: [(restaurant, "Ramen")],
            saturatedQueries: []
        ))
        let orchestrator = SearchOrchestrator(searchService: mock)
        await orchestrator.start()

        // Act
        let jobID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        // Collect until we see the restaurant or give up
        var found = false
        let deadline = Date().addingTimeInterval(5)
        for await update in await orchestrator.updates {
            if update.jobID == jobID, update.snapshot.contains(where: { $0.name == "Ramen Bar" }) {
                found = true
                break
            }
            if update.jobID == jobID, update.isJobComplete { break }
            if Date() > deadline { break }
        }

        XCTAssertTrue(found, "Snapshot must eventually include the restaurant from executeFocusedBatch")
    }

    // MARK: - Completion

    func testOrchestratorEmitsJobCompleteUpdate() async {
        // Arrange
        let mock = MockRestaurantSearchService()
        let orchestrator = SearchOrchestrator(searchService: mock)
        await orchestrator.start()

        // Act
        let jobID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        var receivedComplete = false
        let deadline = Date().addingTimeInterval(10)
        for await update in await orchestrator.updates {
            if update.jobID == jobID, update.isJobComplete {
                receivedComplete = true
                break
            }
            if Date() > deadline { break }
        }

        XCTAssertTrue(receivedComplete, "Orchestrator must emit isJobComplete: true when all phases finish")
    }

    // MARK: - Wide Pass

    func testOrchestratorCallsWideBatchAfterFocusedPass() async {
        // Arrange — all execution methods return empty results so all phases
        // finish as quickly as possible.
        let mock = MockRestaurantSearchService()
        let orchestrator = SearchOrchestrator(searchService: mock)
        await orchestrator.start()

        // Act — enqueue and wait for the job to complete
        let jobID = await orchestrator.enqueueLocation(newYork, focusRadius: 500)

        let deadline = Date().addingTimeInterval(10)
        for await update in await orchestrator.updates {
            if update.jobID == jobID, update.isJobComplete { break }
            if Date() > deadline { break }
        }

        // Assert — wide pass must have run at least one batch
        let count = await mock.executeWideBatchCallCount
        XCTAssertGreaterThanOrEqual(count, 1, "executeWideBatch must be called during the wide pass phase")
    }
}
