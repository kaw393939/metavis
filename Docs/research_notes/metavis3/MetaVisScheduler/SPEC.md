# MetaVisScheduler Specification

## 1. Overview
`MetaVisScheduler` is the "Backoffice" of the MetaVis system. It is a standalone module responsible for managing, persisting, and executing asynchronous jobs. It transforms the application from a simple interactive tool into a robust processing server capable of handling complex workflows (DAGs) like "Ingest -> Analyze -> Enhance -> Render".

## 2. Design Philosophy
*   **Persistence First:** All jobs are stored in SQLite immediately. If the app crashes or the power goes out, the queue is preserved.
*   **DAG (Directed Acyclic Graph):** Jobs can have dependencies. A "Render" job will not start until its "Generate Background" dependency is complete.
*   **Worker Abstraction:** The Scheduler doesn't know *how* to render video; it delegates to specialized `Workers` (e.g., `ServiceWorker`, `RenderWorker`) that wrap the underlying modules.
*   **Server-Grade:** Designed to run on high-end hardware (Mac Studio), utilizing available concurrency while respecting system limits.

## 3. Core Features
*   **Job Queue:** Priority-based execution queue.
*   **Dependency Management:** Automatic resolution of job dependencies.
*   **Retry Logic:** Configurable retry policies for failed jobs (e.g., network flakes).
*   **Observability:** Real-time status updates for UI monitoring.

## 4. Supported Job Types
*   **Ingest:** Importing and indexing media.
*   **Generation:** Calling AI services (Veo, Gemini, ElevenLabs).
*   **Render:** Executing Metal-based rendering pipelines.
*   **Export:** Encoding final video files.
