# MetaVisScheduler TDD Plan

## Phase 1: Core Models & Persistence
**Goal:** Ensure we can save and retrieve jobs from SQLite.
1.  [ ] **Test:** `JobQueueTests` - Create, Read, Update, Delete jobs.
2.  [ ] **Implement:** `Job` struct and `JobQueue` class (GRDB).
3.  [ ] **Test:** `JobQueueTests` - Verify dependency constraints (fetching only unblocked jobs).

## Phase 2: The Scheduler Logic
**Goal:** Ensure the scheduler picks the right jobs.
1.  [ ] **Test:** `SchedulerTests` - Submit job, verify it enters queue.
2.  [ ] **Implement:** `Scheduler` actor.
3.  [ ] **Test:** `SchedulerTests` - Verify `tick()` picks up pending jobs.
4.  [ ] **Test:** `SchedulerTests` - Verify dependency resolution (Job B doesn't run until Job A finishes).

## Phase 3: Worker Integration
**Goal:** Execute actual work.
1.  [ ] **Test:** `WorkerTests` - Mock worker execution.
2.  [ ] **Implement:** `Worker` protocol and `WorkerPool`.
3.  [ ] **Test:** `IntegrationTests` - Run a full DAG of mock jobs.

## Phase 4: Module Integration (Later)
**Goal:** Connect to Services/Simulation.
1.  [ ] Implement `ServiceWorker` (wraps `MetaVisServices`).
2.  [ ] Implement `RenderWorker` (wraps `MetaVisSimulation`).
