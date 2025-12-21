# MetaVisScheduler Data Dictionary

## 1. Enums

### `JobStatus`
*   `pending`: Ready to run, waiting for a worker.
*   `blocked`: Waiting for dependencies to complete.
*   `running`: Currently executing.
*   `completed`: Successfully finished.
*   `failed`: Execution failed (may retry).
*   `cancelled`: User cancelled.

### `JobType`
*   `ingest`: File import.
*   `generate`: AI Service call.
*   `render`: Metal rendering.
*   `export`: Video encoding.
*   `analysis`: Computer vision / Metadata extraction.

## 2. Structs

### `Job`
*   `id`: UUID (Primary Key).
*   `type`: JobType.
*   `status`: JobStatus.
*   `priority`: Int (Higher = sooner).
*   `createdAt`: Date.
*   `updatedAt`: Date.
*   `payload`: Data (JSON encoded parameters).
*   `result`: Data? (JSON encoded output).
*   `error`: String? (Error message if failed).

### `JobDependency`
*   `jobId`: UUID (Foreign Key to Job).
*   `dependsOnId`: UUID (Foreign Key to Job).

## 3. Database Schema (SQLite)

### Table: `jobs`
| Column | Type | Constraints |
|--------|------|-------------|
| id | TEXT | PRIMARY KEY |
| type | TEXT | NOT NULL |
| status | TEXT | NOT NULL |
| priority | INTEGER | DEFAULT 0 |
| created_at | DATETIME | NOT NULL |
| updated_at | DATETIME | NOT NULL |
| payload | BLOB | |
| result | BLOB | |
| error | TEXT | |

### Table: `job_dependencies`
| Column | Type | Constraints |
|--------|------|-------------|
| job_id | TEXT | FK(jobs.id) |
| depends_on_id | TEXT | FK(jobs.id) |
| PRIMARY KEY (job_id, depends_on_id) |
