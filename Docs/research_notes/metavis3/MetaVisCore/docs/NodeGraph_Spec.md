# Node Graph Architecture Specification

## 1. Overview
The `NodeGraph` is the core data structure for MetaVis Render. It replaces the legacy "Layer" and "Element" system with a pure, directed acyclic graph (DAG) model. This structure supports non-linear compositing, procedural generation, and hierarchical organization (Graphs within Graphs).

## 2. Architecture Principles

### 2.1. Value Semantics
All graph data structures (`Node`, `Edge`, `Graph`) are Swift `structs`. This enables:
- **Thread Safety**: No shared mutable state.
- **Undo/Redo**: Instant state snapshots via Copy-on-Write.
- **Serialization**: Trivial `Codable` conformance.

### 2.2. Hierarchical Composition
- A **Project** contains a pool of **Graphs**.
- A **Node** inside a graph can reference another **Graph** (Sub-graph).
- This allows for "Movie -> Scene -> Shot" organization or "Effect Group" encapsulation.

### 2.3. Data vs. Runtime
- **MetaVisCore** defines the *Data Model* (The Blueprint).
- **MetaVisSimulation** defines the *Runtime Engine* (The Execution).
- The Data Model contains no logic for rendering, only for structure and validation.

---

## 3. Data Dictionary

### 3.1. `PortID` (Type Alias: String)
A unique identifier for a connection point on a node (e.g., "input_main", "output_alpha").

### 3.2. `PortType` (Enum)
Defines the data contract for a connection.
- `image` (Texture/Buffer)
- `audio` (PCM Buffer)
- `float` (Scalar)
- `vector3` (Position/Color)
- `string` (Text)
- `event` (Trigger)

### 3.3. `NodePort` (Struct)
Defines a specific input or output on a node.
- `id`: PortID
- `name`: String (Display name)
- `type`: PortType

### 3.4. `Node` (Struct)
A functional unit in the graph.
- `id`: UUID
- `type`: String (e.g., "com.metavis.blur", "com.metavis.source")
- `position`: SIMD2<Float> (UI coordinates)
- `properties`: [String: AnyCodable] (Parameters like "radius", "opacity")
- `inputs`: [NodePort]
- `outputs`: [NodePort]
- `subGraphId`: UUID? (Optional reference to a child graph)

### 3.5. `Edge` (Struct)
A connection between two nodes.
- `id`: UUID
- `fromNode`: UUID
- `fromPort`: PortID
- `toNode`: UUID
- `toPort`: PortID

### 3.6. `NodeGraph` (Struct)
A container for nodes and edges.
- `id`: UUID
- `name`: String
- `nodes`: [UUID: Node] (Dictionary for O(1) lookup)
- `edges`: [Edge]
- `inputs`: [NodePort] (Exposed ports for the graph itself)
- `outputs`: [NodePort] (Exposed ports for the graph itself)

---

## 4. TDD Plan (Test Driven Development)

We will implement `MetaVisCoreTests` to validate these requirements before integrating with the Engine.

### Phase 1: Basic Structure
- [ ] **`testNodeCreation`**: Verify a Node can be initialized with properties and ports.
- [ ] **`testGraphAddNode`**: Verify adding a node to a graph updates the lookup dictionary.
- [ ] **`testGraphRemoveNode`**: Verify removing a node also removes connected edges.

### Phase 2: Connectivity
- [ ] **`testEdgeCreation`**: Verify connecting two valid nodes.
- [ ] **`testSelfConnection`**: Ensure a node cannot connect to itself (A -> A).
- [ ] **`testDuplicateEdge`**: Ensure the same connection cannot be added twice.
- [ ] **`testPortValidation`**: Ensure edges connect to existing ports.

### Phase 3: Advanced Validation
- [ ] **`testCycleDetection`**: **CRITICAL**. Ensure A -> B -> C -> A is rejected.
- [ ] **`testTypeSafety`**: (Optional for V1) Warning if connecting Float -> Image.

### Phase 4: Serialization
- [ ] **`testJSONEncoding`**: Verify the graph saves to JSON correctly.
- [ ] **`testJSONDecoding`**: Verify the graph loads from JSON and restores structure.

---

## 5. Implementation Roadmap

1. Define `PortType` and `NodePort`.
2. Define `Node` and `Edge`.
3. Define `NodeGraph`.
4. Implement `GraphValidator` (Cycle detection logic).
5. Update `RenderManifest` to include `graphs: [UUID: NodeGraph]`.
