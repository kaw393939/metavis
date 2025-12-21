import XCTest
@testable import MetaVisScheduler
import GRDB

final class JobQueueTests: XCTestCase {
    
    var queue: JobQueue!
    
    override func setUpWithError() throws {
        // Use in-memory DB for tests
        queue = try JobQueue()
    }
    
    func testAddJob() throws {
        let job = Job(type: .ingest, payload: Data())
        try queue.add(job: job)
        
        let fetched = try queue.getJob(id: job.id)
        XCTAssertNotNil(fetched)
        XCTAssertEqual(fetched?.status, .pending)
    }
    
    func testGetNextPendingJob_Priority() throws {
        let lowPrio = Job(type: .ingest, priority: 0, payload: Data())
        let highPrio = Job(type: .ingest, priority: 10, payload: Data())
        
        try queue.add(job: lowPrio)
        try queue.add(job: highPrio)
        
        let next = try queue.getNextPendingJob()
        XCTAssertEqual(next?.id, highPrio.id)
    }
    
    func testDependencies_Blocking() throws {
        let parent = Job(type: .ingest, payload: Data())
        let child = Job(type: .analysis, payload: Data())
        
        try queue.add(job: parent)
        try queue.add(job: child, dependencies: [parent.id])
        
        // Child should be blocked
        let fetchedChild = try queue.getJob(id: child.id)
        XCTAssertEqual(fetchedChild?.status, .blocked)
        
        // Parent should be pending
        let fetchedParent = try queue.getJob(id: parent.id)
        XCTAssertEqual(fetchedParent?.status, .pending)
    }
    
    func testDependencies_Unblocking() throws {
        var parent = Job(type: .ingest, payload: Data())
        let child = Job(type: .analysis, payload: Data())
        
        try queue.add(job: parent)
        try queue.add(job: child, dependencies: [parent.id])
        
        // Complete parent
        parent.status = .completed
        try queue.update(job: parent)
        
        // Child should now be pending
        let fetchedChild = try queue.getJob(id: child.id)
        XCTAssertEqual(fetchedChild?.status, .pending)
    }
    
    func testDependencies_MultipleParents() throws {
        var p1 = Job(type: .ingest, payload: Data())
        var p2 = Job(type: .ingest, payload: Data())
        let child = Job(type: .render, payload: Data())
        
        try queue.add(job: p1)
        try queue.add(job: p2)
        try queue.add(job: child, dependencies: [p1.id, p2.id])
        
        // Complete p1 only
        p1.status = .completed
        try queue.update(job: p1)
        
        // Child should still be blocked
        var fetchedChild = try queue.getJob(id: child.id)
        XCTAssertEqual(fetchedChild?.status, .blocked)
        
        // Complete p2
        p2.status = .completed
        try queue.update(job: p2)
        
        // Child should now be pending
        fetchedChild = try queue.getJob(id: child.id)
        XCTAssertEqual(fetchedChild?.status, .pending)
    }
    
    func testPerformance_QueueOperations() {
        measure {
            do {
                let q = try JobQueue()
                for i in 0..<100 {
                    let job = Job(type: .ingest, payload: Data())
                    try q.add(job: job)
                }
                
                for _ in 0..<100 {
                    _ = try q.getNextPendingJob()
                }
            } catch {
                XCTFail("Queue perf failed: \(error)")
            }
        }
    }
}
