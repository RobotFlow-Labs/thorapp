# NEXT_STEPS — THOR v0.1.0 Release

## Last Updated: 2026-04-04

## Status: v0.1.0 release ready; OCI registry trust now spans macOS foundation plus Jetson rollout/preflight for Shenzhen showcase

## Stats
- 100+ files, 19,800+ lines
- 76 tests, 9 suites, 0 failures
- 53 agent endpoints, 30 CLI commands
- Registry trust workflow now present across app, agent, CLI, database, and tests

## v0.1.0 Release Checklist
- [x] All features implemented and tested
- [x] README with install instructions
- [x] CHANGELOG.md
- [x] CONTRIBUTING.md
- [x] LICENSE (MIT)
- [x] Homebrew formula
- [x] Install script (curl)
- [x] GitHub Actions CI/CD
- [x] Issue templates
- [x] PR template
- [x] CLAUDE.md with development rules
- [x] .claude/ settings and rules
- [x] Repo description and topics set
- [ ] Code review (/code-review)
- [ ] Security review (/security-review)
- [ ] Git tag v0.1.0
- [ ] GitHub Release

## MVP Readiness: 95%

## This Session — 2026-04-04
- Reviewed the live THOR codebase for Docker, ANIMA deploy, Keychain, settings, trust, and simulator behavior.
- Confirmed current gaps for secure local OCI registry workflows:
  - no registry profiles
  - no TLS certificate import/trust management
  - no registry auth in THOR
  - no Jetson-side registry trust distribution
  - no deploy-time registry preflight
- Created a repo-grounded PRD for the Shenzhen feature track:
  - `docs/PRD-OCI-Registry-Trust-Manager.md`
- Implemented the first shipping slice of OCI Registry Trust Manager:
  - `registry_profiles` persistence + migration
  - Keychain-backed registry password storage
  - macOS certificate import, parsing, and trust install service
  - registry validation service for config, trust, and `/v2/` reachability
  - new registry workspace in the app shell
  - `thorctl registries` and `thorctl registry-validate`
  - registry-focused regression tests
- Extended the feature from foundation to end-to-end Jetson rollout:
  - new agent registry router for device status, apply, and preflight
  - simulator-backed registry trust/auth state
  - `AgentClient` device registry models + methods
  - `AppState` helpers to apply/validate registry profiles on selected Jetsons
  - ANIMA deploy preflight against saved registry profiles
  - `thorctl registry-device-status`, `registry-device-apply`, and `registry-device-preflight`
  - upgraded registry workspace with setup checklist, Jetson rollout, and preflight visibility
  - additional integration tests for device-side registry apply + preflight
- Created a separate robotics-facing product PRD:
  - `docs/PRD-Robot-Sensor-Cockpit.md`
  - defines THOR’s next differentiation track around live sensor streaming, ROS2 bring-up, and robot readiness
- Verified the implementation against Docker sims:
  - `make docker-up`
  - `thorctl health 8470`
  - `thorctl registry-device-apply 8470 registry.demo.local:5443 /tmp/thor-demo-registry.crt demo secret`
  - `thorctl registry-device-preflight 8470 registry.demo.local:5443 registry.demo.local:5443/hello-world:latest`
  - `make test` → 76 tests passing across 9 suites
  - rebuilt and relaunched local `THORApp.app` for UI inspection

## Current Milestone
- M3 — OCI registry trust integrated through Jetson rollout and deploy preflight; wizard/browser hardening next

## Shenzhen Showcase Track — 2026-04-23
- [x] Feature PRD for OCI Registry Trust Manager
- [x] Expand PRD with wizard, preflight board, recovery UX, and demo-safe flow
- [ ] Review and approve v1 scope
- [x] Add registry profile data model + persistence
- [x] Add macOS certificate import/trust workflow
- [x] Add registry management workspace UI
- [x] Add Jetson trust/auth application workflow
- [x] Add registry validation and demo-ready checks
- [ ] Add registry-aware Docker pull and ANIMA deploy preflight
- [ ] Add registry browser UI (catalog/tags/repository inspection)
- [x] Add thorctl support for registry inspection/validation
- [x] Add simulator-backed tests for secure registry flows across macOS + Jetson
- [ ] Run Shenzhen demo rehearsal on Docker Registry v2
- [ ] Run Shenzhen demo rehearsal on Zot

## Blockers / Decisions
- Need final product decision on whether v1 device-side readiness covers Docker only or Docker plus other OCI clients used in the showcase environment.
- Need confirmation on acceptable service disruption when applying trust to a live device runtime.

## Shenzhen Feature Readiness: 65%

## Post-Shenzhen Product Track — Robotics Developer Cockpit
- [x] Separate PRD for robotics-facing differentiation
- [ ] Review and approve Sensor Cockpit v1 scope
- [ ] Add live camera preview workspace
- [ ] Add ROS2 LaserScan visualization
- [ ] Add stream health overlays and bounded bag capture
- [ ] Expand ROS2 UI beyond list-only inspection
- [ ] Add robot readiness board tying sensors, ROS2, deploy, and runtime together
