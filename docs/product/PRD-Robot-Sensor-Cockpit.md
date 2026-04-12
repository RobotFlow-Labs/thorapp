# PRD — Robot Sensor Cockpit & Bring-Up Center for THOR

- Mode: CREATE
- Product: THOR — Jetson Control Center for macOS
- Date: 2026-04-04
- Target planning milestone: THOR v0.2 candidate on 2026-05-15
- Status: Draft for engineering + GTM review
- Authoring basis: repo review of THORApp, THORShared, THORctl, agent routers, simulator behavior, and current UX surfaces on 2026-04-04

## 0. Product Context

THOR already makes Jetson administration dramatically easier: it connects over SSH, surfaces power/runtime/system information, manages Docker and ANIMA deployments, and exposes a basic ROS2 inspector. It is already credible as a Jetson manager. It is not yet compelling as a robotics developer cockpit.

### Current THOR baseline from code review

- The app exposes device-level workspaces for Overview, System, Power, Hardware, Docker, ROS2, ANIMA, Files, Deploy, GPU, Logs, and History.
- Hardware support in the current app detects cameras, GPIO, I2C, USB, and serial devices, but only as inventory. There is no live camera preview, depth view, lidar view, or stream diagnostics.
- The ROS2 UI lists nodes, topics, and services in [ROS2InspectorView.swift](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Sources/THORApp/Views/ROS2InspectorView.swift), but it does not expose launch control, topic publish, lifecycle transitions, bag recording, parameter editing, or graph-level observability in the app.
- The agent already supports a richer ROS2 backend in [ros2.py](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Agent/routers/ros2.py): launch, lifecycle, topic pub/echo, bag record/stop/list/play. The UI does not yet surface most of that capability.
- THOR has camera detection in [hardware.py](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Agent/routers/hardware.py) and [HardwareView.swift](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Sources/THORApp/Views/HardwareView.swift), but no actual streaming transport or visualization layer.
- THOR has ANIMA module composition and deployment in [ANIMAModuleListView.swift](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Sources/THORApp/Views/ANIMAModuleListView.swift), [PipelineComposerView.swift](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Sources/THORApp/Views/PipelineComposerView.swift), and [PipelineComposer.swift](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Sources/THORShared/Services/PipelineComposer.swift), but no operator-facing sensor readiness view before deployment.
- Fleet support exists in [FleetView.swift](/Users/ilessio/Development/AIFLOWLABS/projects/tools/jetson/THOR/Sources/THORApp/Views/FleetView.swift), but it is limited to connection health and a few batch operations.
- Repo search shows no support today for lidar, LaserScan, PointCloud2, TF visualization, camera calibration, Foxglove-like monitoring, or RViz-style visual debugging.

### Product thesis

The next step is not “more Jetson admin.” The next step is a robotics-native cockpit:

- See what the robot sees
- Verify that the robot is alive before a demo or field run
- Bring up perception and runtime pipelines without opening RViz, Foxglove, or a terminal

### Assumptions used in this PRD

- The right differentiation for THOR is robotics workflow ownership, not generic infra management.
- The first implementation must be ROS2-native rather than tied to a specific sensor vendor SDK.
- v1 should prioritize live camera preview, LaserScan visualization, stream health, bag capture, and ROS2 bring-up actions before broader 3D visualization.
- The macOS app should not require a full ROS desktop installation to be useful.
- The feature must be marketable in one sentence: `THOR lets you see what the robot sees, from your Mac.`

## 1. Problem Statement & Motivation

THOR can manage the Jetson, but robotics developers still leave THOR the moment they need to verify a real robot. The current workflow for bring-up and debugging still depends on terminal commands, ad hoc ROS2 tooling, RViz/Foxglove, vendor camera viewers, and bag scripts. That means THOR owns the machine, but not the robot.

### Who has this problem?

- Robotics integration engineers bringing up new hardware stacks
- Perception engineers validating live sensor feeds on Jetson
- Demo operators who need a clean live “robot is ready” workflow
- Field robotics developers debugging cameras, lidars, and deployed pipelines remotely

### How they solve it today

- `ros2 topic list`, `ros2 topic echo`, and launch commands over SSH
- RViz2 or Foxglove for visual verification
- Vendor-specific camera and lidar viewers
- Rosbag capture scripts for debugging
- Slack screenshots and terminal paste for support workflows

### Why the status quo is unacceptable

- It breaks THOR’s promise of “no terminal needed”
- It forces a multi-tool workflow across SSH, ROS2 CLI, and separate visualization apps
- It weakens the product story; today THOR feels like a strong Jetson admin tool, not an indispensable robotics tool
- Demos fail because there is no single “robot readiness” surface that proves sensors, ROS2, deployment, and hardware are all good

### Why now

- THOR already has the base ingredients: device connection, metrics, hardware discovery, ROS2 endpoints, Docker, ANIMA deploy, and fleet views
- A sensor/bring-up cockpit creates the clearest product and marketing leap beyond infrastructure management
- This feature track can reuse current agent and app architecture rather than requiring a separate product

### Cost of inaction

- THOR remains an operations tool rather than the default daily app for robotics developers
- Robotics teams still leave the product for the workflows that matter most during bring-up and debugging
- Marketing remains abstract instead of showing a visible, differentiated workflow

### Problem validation

| Problem statement | Clear? | Specific? | Measurable? | Validated by repo review? |
|---|---|---:|---:|---:|
| THOR manages Jetsons but does not yet own the live robot bring-up and sensor-debug workflow | Yes | Yes | Yes | Yes |

## 2. Personas, User Stories & Acceptance Criteria

### Persona A — Robot Integration Engineer

- Context: Bringing up cameras, lidar, ROS2 nodes, and deployment pipelines on a new robot or Jetson image
- Goal: Verify that sensors and runtime are alive from one app
- Pain: Too many tools and no single truth source

### Persona B — Perception Engineer

- Context: Needs to validate image streams, LaserScan, and inference health on-device
- Goal: Inspect live streams and measure latency or FPS without rebuilding the whole workflow
- Pain: Device-side debugging is fragmented and fragile

### Persona C — Demo / Field Operator

- Context: Needs a clean green/red readiness view before a showcase or field session
- Goal: Know the robot is ready before pressing deploy
- Pain: Current failures surface only after launch or during runtime

### US-1 — Live Camera Preview

As a robotics developer, I want to preview camera streams directly in THOR so that I can confirm that sensors and image pipelines are alive without leaving the app.

- Priority: P0
- Effort: L
- Dependencies: new streaming transport, camera/topic discovery, image decoding, app rendering pipeline

Acceptance criteria:

- AC-1.1: GIVEN a detected camera or ROS2 image topic WHEN I open the Sensors workspace THEN THOR can show a live preview or an explicit “no frames received” state.
- AC-1.2: GIVEN a live stream WHEN I inspect it THEN THOR shows stream metadata such as resolution, encoding, FPS, and last frame timestamp.
- AC-1.3: GIVEN a stream failure WHEN frames stop or timestamps go stale THEN THOR surfaces a degraded state instead of silently freezing the preview.

### US-2 — Lidar / LaserScan Visualization

As a robotics developer, I want to visualize lidar scan data in THOR so that I can validate that range data is present, sane, and updating in real time.

- Priority: P0
- Effort: L
- Dependencies: ROS2 LaserScan topic support, stream transport, 2D scan renderer, topic selection

Acceptance criteria:

- AC-2.1: GIVEN a `sensor_msgs/msg/LaserScan` topic WHEN I select it THEN THOR renders a live 2D scan visualization.
- AC-2.2: GIVEN scan data is delayed, empty, or malformed WHEN I inspect the stream THEN THOR shows that as a health issue with the failing stage.
- AC-2.3: GIVEN multiple scan topics exist WHEN I switch topics THEN THOR updates quickly without needing a full reconnect.

### US-3 — Stream Health & Debug Capture

As a perception or field engineer, I want stream health diagnostics and one-click debug capture so that I can prove what the robot was seeing when something went wrong.

- Priority: P0
- Effort: M
- Dependencies: stream session model, bag capture, screenshot/snapshot export, event history

Acceptance criteria:

- AC-3.1: GIVEN a live camera or lidar stream WHEN I inspect it THEN THOR shows health metrics such as FPS, dropped frames, timestamp skew, and transport status.
- AC-3.2: GIVEN a debugging session WHEN I click “Capture Debug Snapshot” THEN THOR stores a still image or scan frame plus metadata.
- AC-3.3: GIVEN a live issue WHEN I click “Record 30s Bag” THEN THOR starts a bounded bag capture and reports completion in the app history.

### US-4 — ROS2 Bring-Up Center

As a robot integration engineer, I want a proper bring-up center in THOR so that I can start launches, inspect lifecycle nodes, publish quick test messages, and manage recording without opening a terminal.

- Priority: P0
- Effort: L
- Dependencies: existing ROS2 agent endpoints, new UI coverage, validation guards for topic/service names

Acceptance criteria:

- AC-4.1: GIVEN a connected Jetson WHEN I open the Bring-Up Center THEN THOR lists nodes, topics, services, launch processes, and bag recordings in one place.
- AC-4.2: GIVEN a launchable package and launch file WHEN I start or stop a launch THEN THOR shows process state and failure output.
- AC-4.3: GIVEN lifecycle nodes or bag operations exist WHEN I act on them THEN THOR executes the transition or recording flow and preserves the result in app state.

### US-5 — Robot Readiness Board

As a demo or field operator, I want a single robot readiness board so that I know whether the robot is actually ready before I run the mission or demo.

- Priority: P0
- Effort: M
- Dependencies: health checks across sensors, ROS2, runtime, GPU, deployment state, registry readiness

Acceptance criteria:

- AC-5.1: GIVEN a configured robot profile WHEN I open the readiness board THEN THOR shows green/yellow/red state for camera, lidar, ROS2, ANIMA pipeline, GPU thermals, storage, and registry/deploy readiness.
- AC-5.2: GIVEN a failed readiness stage WHEN I inspect it THEN THOR shows the likely cause and the next corrective action.
- AC-5.3: GIVEN all required stages pass WHEN I start the demo path THEN THOR allows a clean handoff into deploy or live monitoring.

### US-6 — Model + Sensor Benchmark Lab

As a perception engineer, I want to benchmark model pipelines against live sensors on-device so that I can compare performance under realistic conditions.

- Priority: P1
- Effort: L
- Dependencies: ANIMA deployment, live stream selection, metrics correlation, result storage

Acceptance criteria:

- AC-6.1: GIVEN a selected module or pipeline WHEN I run a benchmark THEN THOR records FPS, latency, GPU memory, power, and temperature during the session.
- AC-6.2: GIVEN multiple backends or model variants WHEN I compare runs THEN THOR can present simple side-by-side result summaries.
- AC-6.3: GIVEN a degraded or overheated run WHEN the benchmark completes THEN THOR clearly marks the run as unhealthy rather than just fast.

### US-7 — Calibration & Hardware Lab Tools

As a robotics developer, I want calibration-adjacent hardware tools in THOR so that I can validate that connected devices are physically usable, not merely present.

- Priority: P1
- Effort: L
- Dependencies: hardware router expansion, serial/CAN/GPIO actions, calibration file workflows

Acceptance criteria:

- AC-7.1: GIVEN cameras or serial-connected hardware WHEN I inspect the device THEN THOR shows operational details beyond raw presence, such as current mode or active port status.
- AC-7.2: GIVEN a supported calibration file workflow WHEN I import or export calibration data THEN THOR associates it with the device and preserves history.
- AC-7.3: GIVEN a low-level debug session WHEN I need to poke GPIO or inspect serial output THEN THOR can expose the relevant safe controls without requiring shell access.

### US-8 — Fleet Sensor Wall

As a lab operator, I want a fleet-level sensor wall so that I can quickly identify which robots are visually healthy and which ones need attention.

- Priority: P1
- Effort: M
- Dependencies: per-device readiness summaries, stream thumbnails, fleet filtering

Acceptance criteria:

- AC-8.1: GIVEN multiple connected devices WHEN I open the fleet sensor wall THEN THOR shows a compact readiness card for each robot.
- AC-8.2: GIVEN one or more devices are degraded WHEN I sort or filter the fleet THEN the unhealthy devices are easy to isolate.
- AC-8.3: GIVEN a known-good fleet state WHEN a sensor stream later goes stale THEN THOR reflects the regression without a manual refresh ritual.

## 3. Scope & Non-Goals

### In scope for v1 of this feature track

- New **Sensors** workspace in THOR
- Live camera preview for detected cameras and ROS2 image topics
- Live 2D lidar visualization for `sensor_msgs/msg/LaserScan`
- Stream health overlays: FPS, timestamps, stale-state detection
- One-click debug snapshot and bounded rosbag capture
- Expanded ROS2 Bring-Up Center covering launches, lifecycle, and bag operations in the UI
- Robot readiness board joining sensors + ROS2 + runtime + deploy readiness

### Explicitly out of scope for v1

- Full RViz replacement
- Full Foxglove replacement
- Full 3D point-cloud visualization for large `PointCloud2` streams
- SLAM map editing, path planning, or mission authoring
- Vendor-specific lidar SDK integrations as the primary path
- URDF editing or full TF tree 3D visualization

### Future considerations (v2+)

- Decimated `PointCloud2` and depth-cloud views
- TF / frame-tree graph view
- Camera calibration workflows
- Fleet-wide sensor wall
- Benchmark comparison history
- Vendor-specific enrichments for popular robotics sensors where they add real value

### Scope decision log

| Item | In/Out | Rationale | Revisit? |
|---|---|---|---|
| Live camera preview | IN | Highest immediate user and demo value | No |
| LaserScan viewer | IN | Strong robotics signal without 3D complexity | No |
| ROS2 bring-up actions in UI | IN | Existing backend already supports much of it | No |
| Robot readiness board | IN | Core differentiation and demo safety | No |
| Full PointCloud2 3D viewer | OUT | High rendering and transport complexity | v2 |
| Full RViz/Foxglove parity | OUT | Wrong scope for first pass | No |
| Vendor-native lidar integrations | OUT | ROS2-first path gives broader coverage | Later |

## 4. Technical Constraints & Dependencies

### Product and platform constraints

- THOR is a native macOS SwiftUI app and currently uses HTTP/JSON over SSH tunnels to communicate with the Jetson agent.
- The agent today is request/response oriented; it does not yet expose a streaming transport for live sensor media.
- The Mac app should remain useful without requiring the user to install full ROS desktop tooling locally.

### Key technical constraints

- Live streams need a transport layer suitable for image and scan data over the existing Mac-to-Jetson pattern.
- Camera preview likely needs server-side conversion to preview-friendly encodings rather than raw ROS image transport end-to-end.
- LaserScan support is a cleaner first target than full point clouds because bandwidth, rendering, and UX are much simpler.
- Sensor visualization must not starve the Jetson or interfere with the robot’s primary runtime workload.
- Preview quality and frame rate may need adaptive throttling depending on Jetson load and network quality.

### Integration dependencies

| Dependency | Owner | Status | Risk | Mitigation |
|---|---|---|---|---|
| Camera/topic discovery | THOR agent + app | Partial | Low | Reuse current camera and ROS2 topic enumeration |
| Streaming transport | THOR agent + app | Not implemented | High | Add explicit v1 media/scan session endpoints |
| ROS2 bring-up actions | THOR agent | Mostly implemented | Medium | Surface existing endpoints in the UI |
| Readiness aggregation | THOR app | Not implemented | Medium | Reuse metrics, hardware, ROS2, registry, and deploy state |
| Debug capture/history | THOR app/db | Partial | Medium | Extend job/event tracking and file export flows |

### Data requirements

THOR will need persistent or semi-persistent models for:

- Sensor stream session metadata
- Last readiness results per robot
- Debug snapshot and bounded bag capture records
- Optional robot profiles defining required streams and readiness gates

### Performance requirements

- First preview frame within 2 seconds for a healthy local stream
- Preview mode should support at least 5-15 FPS for camera verification workflows
- LaserScan visualization should update at near-live cadence for common robotics use
- Readiness board should return first useful results within 10 seconds

## 5. Success Metrics & Measurement

| Metric | Type | Baseline | Target | Measurement |
|---|---|---:|---:|---|
| Time to verify that cameras and lidar are alive on a new robot | Primary | 5-15 min across SSH + ROS2 + external tools | < 2 min in THOR | Internal bring-up checklist timing |
| Number of external tools required for basic sensor bring-up | Primary | 2-4 tools common today | 0 required for supported v1 flows | Workflow audit |
| Fraction of internal demo/field checks completed without terminal usage | Secondary | Low today | 80%+ | Dogfood session logs |
| Time to capture a useful sensor debug artifact | Secondary | Manual scripts and ad hoc bag capture | < 30 seconds | QA script + event timestamps |
| Post-deploy issues caused by missing/stale sensor streams discovered too late | Guardrail | Common/manual today | Reduced to near zero in validated flows | Readiness history + incident notes |

### Measurement plan

- Add app-side event logging for stream sessions, readiness checks, and debug captures
- Run scripted internal bring-up rehearsals on at least one real camera source and one simulated ROS2 topic source
- Require at least one internal “show the robot sees the world” demo before public launch of this feature track

## 6. UX Flow

### Proposed product surface

- A new **Sensors** workspace in THOR
- An expanded **ROS2 Bring-Up Center** replacing the current inspector-only posture
- A **Robot Readiness Board** that compresses the health of the whole robot into one view
- Lightweight handoff into **Deploy** and **ANIMA** once readiness is green

### Core flow

`Open Sensors workspace`
→ `Auto-discover cameras and ROS2 sensor topics`
→ `Select camera or lidar stream`
→ `See live preview + stream health`
→ `Capture snapshot or record 30s bag if needed`
→ `Open readiness board`
→ `Fix any failing stage`
→ `Launch/activate pipeline`
→ `Monitor live robot state during demo or bring-up`

### Screen/state requirements

#### Sensors Workspace

- Camera preview panel
- LaserScan panel
- Topic/source selector
- Health overlay with FPS, timestamps, and degraded-state indicators
- Snapshot / bag capture actions

#### ROS2 Bring-Up Center

- Nodes, topics, services, launches, lifecycle, and bag state
- Launch start/stop
- Lifecycle transitions
- Topic echo / publish where appropriate
- Quick handoff to sensor topics from the same screen

#### Robot Readiness Board

- Green/yellow/red status for required cameras, lidar, ROS2, ANIMA runtime, GPU thermal headroom, storage, and deploy prerequisites
- Inline remediation actions
- Demo-safe “all green” summary state

#### Required non-happy states

- Topic exists but no messages are arriving
- Stream timestamps are stale
- Unsupported or unknown image encoding
- LaserScan topic available but empty or malformed
- Launch process started but node graph did not stabilize
- Bag capture failed due to path, disk, or permissions
- Preview auto-throttled due to device load

## 7. Release & Rollout Plan

### Rollout strategy

Start with a vertical slice that proves the product thesis: live camera preview, LaserScan visualization, and readiness checks. Add broader ROS2 bring-up and benchmark functionality after the core visual workflow is solid.

### Launch criteria

- Live preview works on at least one real or simulated camera source
- LaserScan visualization works on at least one ROS2 scan source
- ROS2 bring-up actions used in the UI can be executed without terminal fallback
- Readiness board catches at least one degraded stream or stale topic failure mode before deployment
- Existing device management and deployment workflows do not regress

### Rollout phases

| Phase | Audience | Criteria to proceed | Target date |
|---|---|---|---|
| PRD sign-off | Internal | Product direction accepted | 2026-04-09 |
| Alpha vertical slice | Internal | Camera preview + basic readiness panel work | 2026-04-18 |
| Beta robotics dogfood | Internal | LaserScan + bring-up actions + bag capture work | 2026-04-29 |
| Marketing/demo pilot | Internal | “See what the robot sees” storyline is demoable | 2026-05-08 |
| v0.2 candidate | Internal | No P0/P1 issues on the core bring-up path | 2026-05-15 |

## Open Questions Resolved for v1

- Should this be ROS2-first or vendor-SDK-first? ROS2-first
- Should camera preview come before lidar visualization? Yes
- Should PointCloud2 be part of the first slice? No
- Should Mac require local ROS tools? No
- Should readiness include deploy/runtime state, not just sensors? Yes

## Completion Summary

| Field | Value |
|---|---|
| Mode selected | CREATE |
| Product | THOR |
| User stories | 8 total |
| P0 stories | 5 |
| P1 stories | 3 |
| Acceptance criteria | 24 |
| Dependencies mapped | 5 |
| High-risk dependencies | 1 |
