# NEXT_STEPS — THOR v0.1.0 Release

## Last Updated: 2026-04-04

## Status: v0.1.0 release ready; OCI registry trust foundation implemented for Shenzhen showcase

## Stats
- 100+ files, 19,800+ lines
- 74 tests, 9 suites, 0 failures
- 50 agent endpoints, 27 CLI commands
- Registry trust foundation now present in app, CLI, database, and tests

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
- Verified the implementation against Docker sims:
  - `make docker-up`
  - `thorctl health 8470`
  - `make test` → 74 tests passing across 9 suites

## Current Milestone
- M2 — OCI registry trust foundation on macOS complete; Jetson-side rollout next

## Shenzhen Showcase Track — 2026-04-23
- [x] Feature PRD for OCI Registry Trust Manager
- [ ] Review and approve v1 scope
- [x] Add registry profile data model + persistence
- [x] Add macOS certificate import/trust workflow
- [x] Add registry management workspace UI
- [ ] Add Jetson trust/auth application workflow
- [x] Add registry validation and demo-ready checks
- [ ] Add registry-aware Docker pull and ANIMA deploy preflight
- [ ] Add registry browser UI (catalog/tags/repository inspection)
- [x] Add thorctl support for registry inspection/validation
- [ ] Add end-to-end tests for secure registry flows across macOS + Jetson
- [ ] Run Shenzhen demo rehearsal on Docker Registry v2
- [ ] Run Shenzhen demo rehearsal on Zot

## Blockers / Decisions
- Need final product decision on whether v1 device-side readiness covers Docker only or Docker plus other OCI clients used in the showcase environment.
- Need confirmation on acceptable service disruption when applying trust to a live device runtime.

## Shenzhen Feature Readiness: 45%
