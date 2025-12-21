# MetaVisScheduler Architecture

## 1. High-Level Diagram

```mermaid
graph TD
    Client[UI / CLI] --> Scheduler[Scheduler (Orchestrator)]
    
    subgraph "Persistence Layer"
        Scheduler --> DB[(SQLite Database)]
    end
    
    subgraph "Execution Layer"
        Scheduler --> WorkerPool[Worker Pool]
        WorkerPool --> ServiceWorker[ServiceWorker]
        WorkerPool --> RenderWorker[RenderWorker]
        WorkerPool --> IngestWorker[IngestWorker]
    end
    
    subgraph "External Modules"
        ServiceWorker --> MetaVisServices
        RenderWorker --> MetaVisSimulation
        IngestWorker --> MetaVisIngest
    end
```

## 2. Core Components

### 2.1. `Job` (Model)
The fundamental unit of work.
- `id`: UUID
- `type`: JobType (ingest, generate, render)
- `status`: pending, running, completed, failed
- `dependencies`: [UUID] (List of parent Job IDs)
- `payload`: JSON Data (Arguments for the worker)

### 2.2. `Scheduler` (Actor)
The brain of the operation.
- **`submit(job:)`**: Adds a job to the DB.
- **`tick()`**: The run loop. Checks for pending jobs whose dependencies are met and assigns them to workers.
- **`cancel(jobId:)`**: Stops a job.

### 2.3. `JobQueue` (Database)
Wraps GRDB (SQLite).
- Handles atomic transactions.
- Queries for "Next available job".
- Updates job status.

### 2.4. `Worker` (Protocol)
The interface for executing work.
```swift
protocol Worker {
    var jobType: JobType { get }
    func execute(job: Job) async throws -> JobResult
}
```

## 3. The "iPhone Footage" Workflow Example
1.  **Ingest Job:** Created. Status: `pending`.
2.  **Analyze Job:** Created. Dependency: `Ingest Job`. Status: `blocked`.
3.  **Enhance Job:** Created. Dependency: `Analyze Job`. Status: `blocked`.
4.  **Render Job:** Created. Dependency: `Enhance Job`. Status: `blocked`.

*   Scheduler runs `Ingest Job`.
*   Upon completion, `Analyze Job` becomes `pending`.
*   Scheduler runs `Analyze Job`.
*   ...and so on.
