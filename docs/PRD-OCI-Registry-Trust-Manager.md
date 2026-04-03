# PRD — OCI Registry Trust Manager for THOR

- Mode: CREATE
- Product: THOR — Jetson Control Center for macOS
- Date: 2026-04-04
- Target demo date: 2026-04-23
- Status: Draft for engineering review
- Authoring basis: repo review of THORApp, THORShared, THORctl, agent routers, database schema, and current simulator behavior on 2026-04-04

## 0. Product Context

THOR is a native macOS app for managing NVIDIA Jetson devices. It already covers SSH-based enrollment, Docker container control, ANIMA pipeline deployment, ROS2 inspection, file transfer, and system operations.

### Current THOR baseline from code review

- THOR stores SSH credentials in macOS Keychain, but only for SSH auth material.
- THOR verifies SSH host keys on first use, but it does not manage TLS certificates for OCI registries.
- The agent already supports Docker container listing, image listing, and image pull.
- ANIMA deployment already composes and deploys `docker compose` pipelines whose services reference container image strings.
- The app has no concept of registry profiles, registry authentication, registry browsing, certificate import, trust status, or deploy-time registry preflight.
- The database has no registry, certificate, or registry-auth entities today.
- Settings are minimal and not designed for artifact or trust management.

### Assumptions used in this PRD

- The primary near-term goal is a polished Shenzhen showcase on 2026-04-23.
- The target users are robotics founders, demo operators, ML/robotics engineers, and lab operators managing Jetson fleets.
- THOR should own the full secure-registry workflow for both the Mac operator environment and the target Jetson devices.
- MVP support should work with generic OCI Distribution API registries, explicitly validated against Docker Registry v2 and Zot.
- v1 will support anonymous access and username/password authentication. Token-only and SSO flows are deferred.
- v1 should feel guided and low-friction, not like a thin wrapper over manual PKI and Docker tasks.

## 1. Problem Statement & Motivation

THOR can deploy and manage containerized workloads on Jetson devices, but it cannot set up or validate the secure OCI registry trust chain those deployments depend on. In real robotics labs, teams frequently use a local registry backed by a private CA or self-signed certificate. Today, users must manually install CA certificates, configure trust on macOS, configure trust on each Jetson, verify credentials, and then hope image pulls succeed during demos or bring-up. This creates a fragile, terminal-heavy workflow that undermines THOR’s value proposition as a no-terminal control center.

### Who has this problem?

- Founder/demo operator preparing a stable live demo
- Robotics/ML engineer deploying models and pipelines to Jetson devices
- Lab operator maintaining a local artifact registry for images and packages

### How they solve it today

- Import CA certs manually into macOS Keychain
- Hand-configure trust on each Jetson/container runtime
- Store registry credentials outside THOR
- Use `docker pull`, `curl`, `oras`, or shell scripts to validate access
- Retry deployment after opaque TLS or auth failures

### Why the status quo is unacceptable

- It breaks the “no terminal needed” promise of THOR
- Secure local registries are common in robotics labs and demos
- Failures often occur late, during deploy, when time pressure is highest
- There is no single source of truth for trust, auth, and image source readiness

### Why now

- THOR is already release-ready as a Jetson manager, so registry trust is the next leverage point that makes the product feel complete
- The Shenzhen showcase on 2026-04-23 needs a demo-safe artifact workflow
- Existing ANIMA and Docker surfaces already provide a natural place to integrate registry functionality

### Cost of inaction

- Demo risk remains high for any secure local registry workflow
- Users continue dropping to terminal and bypassing THOR
- THOR appears incomplete for real-world robotics deployment environments

### Problem validation

| Problem statement | Clear? | Specific? | Measurable? | Validated by repo review? |
|---|---|---:|---:|---:|
| THOR lacks end-to-end secure OCI registry trust and access management for macOS + Jetson workflows | Yes | Yes | Yes | Yes |

## 2. Personas, User Stories & Acceptance Criteria

### Persona A — Demo Operator

- Context: Needs a flawless live workflow for a local secure registry and Jetson deployment demo
- Goal: Get from “new registry cert” to “successful secure image pull and deploy” without terminal work
- Pain: TLS/auth failures surface too late and break momentum

### Persona B — Robotics/ML Engineer

- Context: Iterates on container images, ANIMA modules, and model artifacts
- Goal: Browse, validate, and deploy registry-backed artifacts directly from THOR
- Pain: Current deploy flow assumes image references exist but does not help make them reachable

### Persona C — Lab/Fleet Operator

- Context: Maintains multiple Jetsons and a private local registry
- Goal: Push trust and auth to a set of devices consistently
- Pain: Device-by-device manual setup is error-prone and hard to audit

### US-1 — Registry Profile Management

As a THOR operator, I want to create and manage OCI registry profiles so that THOR knows which secure registries my Mac and Jetsons should use.

- Priority: P0
- Effort: M
- Dependencies: new THOR data model, Keychain-backed secret handling, registry connectivity checks

Acceptance criteria:

- AC-1.1: GIVEN a new registry hostname, port, and display name WHEN I save a registry profile THEN THOR stores the non-secret profile metadata and shows the profile in a registry list.
- AC-1.2: GIVEN a profile with missing required fields WHEN I attempt to save it THEN THOR blocks the save and identifies which fields must be fixed.
- AC-1.3: GIVEN an existing registry profile WHEN I edit or delete it THEN THOR updates the visible state and warns if the profile is referenced by device trust, Docker pull, or deployment flows.

### US-2 — macOS Certificate Import & Trust

As a THOR operator, I want THOR to import a registry CA certificate into macOS trust so that local tools can securely access the registry.

- Priority: P0
- Effort: M
- Dependencies: macOS Security framework, certificate parsing, admin/user permission prompts

Acceptance criteria:

- AC-2.1: GIVEN a PEM, CRT, CER, or DER certificate file WHEN I import it into a registry profile THEN THOR parses the certificate and displays subject, issuer, fingerprint, and expiry before trust is changed.
- AC-2.2: GIVEN a valid certificate not yet trusted on the Mac WHEN I choose “Trust on this Mac” THEN THOR completes the trust action or shows a precise failure message if permission is denied.
- AC-2.3: GIVEN a certificate already trusted or later removed/changed WHEN I open the registry profile THEN THOR shows the current trust state and whether action is required.

### US-3 — Jetson Trust Distribution

As a fleet operator, I want THOR to install registry trust on selected Jetson devices so that device-side pulls and deployments succeed over TLS.

- Priority: P0
- Effort: L
- Dependencies: Jetson-side trust management, elevated device actions, device capability detection

Acceptance criteria:

- AC-3.1: GIVEN one or more selected devices and a registry profile with a CA certificate WHEN I apply trust to those devices THEN THOR reports success or failure per device.
- AC-3.2: GIVEN a device whose runtime needs a trust refresh or service restart WHEN trust is applied THEN THOR clearly communicates the required follow-up action before the device is marked ready.
- AC-3.3: GIVEN a device that cannot accept the certificate or validate the registry WHEN distribution fails THEN THOR preserves the failure reason and does not mark the device as registry-ready.

### US-4 — Registry Authentication Management

As a THOR operator, I want registry credentials stored securely and reusable across flows so that I do not have to re-enter auth during every pull or deploy.

- Priority: P0
- Effort: M
- Dependencies: macOS Keychain secret storage, agent auth application, profile-to-device mapping

Acceptance criteria:

- AC-4.1: GIVEN a registry profile using username/password auth WHEN I save credentials THEN THOR stores secrets in Keychain and never exposes plaintext in the main UI.
- AC-4.2: GIVEN saved credentials WHEN I run registry validation or a device pull THEN THOR uses the saved auth without requiring a second prompt unless the credentials are invalid.
- AC-4.3: GIVEN invalid or expired credentials WHEN a validation or pull fails THEN THOR attributes the failure to auth and prompts for credential repair instead of surfacing a generic connection error.

### US-5 — Registry Validation & Demo Readiness

As a demo operator, I want a single readiness check so that I know whether the registry is truly usable before I start a live demo or deployment.

- Priority: P0
- Effort: M
- Dependencies: macOS trust checks, registry API probe, device trust checks, device auth checks, sample pull test

Acceptance criteria:

- AC-5.1: GIVEN a configured registry profile WHEN I run validation on my Mac THEN THOR checks certificate trust, registry reachability, and auth validity and returns pass/fail with actionable diagnostics.
- AC-5.2: GIVEN one or more selected Jetson devices WHEN I run validation for those devices THEN THOR shows per-device readiness for trust, auth, and pull capability.
- AC-5.3: GIVEN a failing validation WHEN I view the result THEN THOR shows the specific failing stage and the next corrective action instead of a generic “registry unavailable” state.

### US-6 — Registry Browsing

As a robotics engineer, I want to browse repositories, tags, and digests from the registry inside THOR so that I can choose the correct artifact without leaving the app.

- Priority: P1
- Effort: L
- Dependencies: OCI catalog/tag APIs, pagination, auth reuse, error-state handling

Acceptance criteria:

- AC-6.1: GIVEN a reachable authenticated registry WHEN I open the registry browser THEN THOR lists repositories and supports search/filter.
- AC-6.2: GIVEN a selected repository WHEN I view tags THEN THOR shows available tags and, where available, digest and metadata.
- AC-6.3: GIVEN a registry that does not expose catalog/tag endpoints as expected WHEN I browse it THEN THOR explains the limitation and preserves the ability to validate by explicit image reference.

### US-7 — Pull & Deployment Integration

As a THOR operator, I want Docker and ANIMA flows to understand registry profiles so that secure image pulls and pipeline deploys work without hidden TLS surprises.

- Priority: P0
- Effort: L
- Dependencies: Docker pull UI integration, ANIMA deploy preflight, profile/image selection UI

Acceptance criteria:

- AC-7.1: GIVEN a selected registry profile and image reference WHEN I initiate a pull from THOR THEN THOR performs the pull against the intended device or local runtime and reports progress and final status.
- AC-7.2: GIVEN an ANIMA deployment whose images come from a registry profile WHEN I start deployment THEN THOR runs registry preflight before the deploy begins.
- AC-7.3: GIVEN missing trust, missing auth, or an unreachable registry WHEN I attempt a pull or deploy THEN THOR blocks or warns before runtime failure, based on the severity of the issue.

### US-8 — Certificate Drift, Rotation & Auditability

As a fleet operator, I want THOR to detect certificate drift and rotation events so that I can maintain trust safely over time.

- Priority: P1
- Effort: M
- Dependencies: stored fingerprint history, trust-state polling, profile/device status model

Acceptance criteria:

- AC-8.1: GIVEN a registry certificate whose fingerprint or expiry has changed WHEN THOR next validates the profile THEN THOR flags the change and marks the profile as requiring review.
- AC-8.2: GIVEN a certificate rotation event WHEN I approve the new certificate THEN THOR updates the trusted certificate state without forcing profile re-creation.
- AC-8.3: GIVEN a team member reviewing a registry profile WHEN they inspect its status THEN THOR shows when trust was last validated on the Mac and on each assigned device.

### US-9 — Guided Setup Wizard

As a THOR operator, I want a guided registry setup wizard so that I can complete trust, auth, and Jetson rollout without understanding low-level PKI or Docker configuration details.

- Priority: P0
- Effort: M
- Dependencies: registry profile model, certificate parsing, trust install, device rollout actions, validation pipeline

Acceptance criteria:

- AC-9.1: GIVEN no registry profile exists WHEN I open the Registry workspace THEN THOR offers a primary “Set Up Registry” guided flow instead of dropping me into a blank detail form.
- AC-9.2: GIVEN I use the wizard WHEN I move through registry type, certificate import, credentials, device selection, and validation THEN THOR preserves progress and clearly shows what remains.
- AC-9.3: GIVEN the wizard completes successfully WHEN I reach the final step THEN THOR shows a ready state with next actions such as browse, test pull, or deploy.

### US-10 — Smart Defaults, Templates & Test Pull

As a robotics engineer, I want registry templates, autofill defaults, and a dedicated test pull action so that I can get to a working artifact quickly and confirm it before deployment.

- Priority: P0
- Effort: M
- Dependencies: profile presets, image-reference validation, device-side pull preflight, cached operator preferences

Acceptance criteria:

- AC-10.1: GIVEN I create a new profile WHEN I choose Docker Registry, Zot, Harbor, or GHCR THEN THOR pre-fills sensible defaults such as scheme, common port, and suggested display name.
- AC-10.2: GIVEN prior registry usage or connected devices exist WHEN I create or edit a profile THEN THOR suggests the last used device set and the most likely namespace or host values where appropriate.
- AC-10.3: GIVEN a saved registry profile WHEN I click “Test Pull” on a selected Jetson or on the Mac THEN THOR performs a pull smoke test with a visible result and actionable failure reason.

### US-11 — Friendly Error Translation & Recovery Actions

As a THOR operator, I want failures translated into plain language with one-click recovery actions so that I can fix problems quickly instead of deciphering TLS, auth, or Docker errors.

- Priority: P0
- Effort: M
- Dependencies: normalized validation stages, error mapping layer, UI action routing for trust/auth/retry workflows

Acceptance criteria:

- AC-11.1: GIVEN a validation, apply, or pull failure WHEN THOR surfaces the error THEN it maps raw runtime output into a user-facing explanation such as “Mac trusted, Jetson not trusted” or “registry reachable, password rejected.”
- AC-11.2: GIVEN a recoverable failure WHEN THOR shows the result THEN the result includes a direct next action such as “Trust on This Mac,” “Apply to Jetsons,” “Update Password,” or “Retry Validation.”
- AC-11.3: GIVEN detailed logs are still needed WHEN an advanced operator asks for them THEN THOR provides the raw diagnostic output without making it the default presentation.

### US-12 — Demo Preflight Board & 60-Second Showcase Path

As a demo operator, I want a single preflight board and sample path so that I can prove the system is green before a live demo and get from cold start to deploy in under a minute.

- Priority: P0
- Effort: M
- Dependencies: staged validation model, device readiness checks, sample/test artifact support, history logging

Acceptance criteria:

- AC-12.1: GIVEN a configured registry and selected Jetsons WHEN I open the preflight board THEN THOR shows green/yellow/red status for Mac trust, registry reachability, credentials, device trust, and pull readiness.
- AC-12.2: GIVEN all required stages pass WHEN I start the showcase path THEN THOR can drive the operator from profile ready state to test pull or deploy without opening separate unrelated screens.
- AC-12.3: GIVEN a THOR build intended for showcase rehearsal WHEN the operator needs a known-good path THEN THOR supports a sample/test image workflow or equivalent canned verification path.

## 3. Scope & Non-Goals

### In scope for v1

- Global OCI registry profiles in THOR
- Guided registry setup wizard
- Importing and trusting a registry CA certificate on macOS
- Secure storage of registry credentials in macOS Keychain
- Applying trust/auth to selected Jetson devices
- Batch “Apply to Jetsons” flow with per-device status
- Registry validation and readiness checks for Mac + device
- Preflight board summarizing Mac + device readiness in one view
- Docker and ANIMA deploy preflight integration
- Test pull action from the registry workspace
- Explicit image pull flow from THOR using a chosen registry/image reference
- Registry browser for repositories/tags/digests where the registry supports it
- Registry templates and smart defaults for common registry types
- Friendly error translation with direct recovery actions
- Clear error states for TLS, auth, reachability, expiry, and drift

### Explicitly out of scope

- Running a registry server from THOR
- Building or pushing images from THOR
- Full package-manager support beyond OCI artifacts/images
- SSO/OIDC device-code auth flows
- Cosign signing/verification, SBOM validation, or provenance policy enforcement
- Registry replication, garbage collection, retention policy management

### Future considerations (v2+)

- Multi-registry routing and fallback
- Per-project or per-pipeline registry selection policies
- Artifact push/publish from Mac to registry
- OCI artifact browsing beyond container images
- Signature and provenance workflows
- Team sharing/export of registry profiles
- Fleet-wide policy automation and scheduled drift audits

### Scope decision log

| Item | In/Out | Rationale | Revisit? |
|---|---|---|---|
| Registry profile management | IN | Foundation for all trust and deploy flows | No |
| Mac certificate trust management | IN | Direct user request; core demo value | No |
| Jetson trust distribution | IN | Required for actual secure device deploys | No |
| Registry browsing | IN | Important demo and operator usability surface | At beta |
| Guided setup wizard | IN | Highest leverage UX improvement for Shenzhen | No |
| Test pull + preflight board | IN | Reduces demo risk and operator uncertainty | No |
| Image build/push pipeline | OUT | High scope, not required for secure pull/deploy | v2 |
| SSO/OIDC registry auth | OUT | Too much auth complexity for Shenzhen timeline | Post-demo |
| Registry hosting inside THOR | OUT | Not aligned with THOR’s device-manager role | No |

## 4. Technical Constraints & Dependencies

### Product and platform constraints

- THOR is a macOS 14+ SwiftUI app and already uses macOS Keychain for secrets.
- THOR deploys workloads to Jetsons through an agent plus Docker-based runtime flows.
- ANIMA deployments currently rely on image references embedded in module manifests and composed into `docker compose` YAML.
- Any new registry feature must not break existing public-image workflows.

### Security constraints

- Registry secrets must be stored in Keychain, not plaintext app storage.
- THOR must show certificate identity before trust is changed.
- THOR must support explicit removal or revocation of trust.
- THOR must not assume OS trust alone guarantees every client is ready; it must validate effective readiness through smoke tests.

### Runtime constraints

- Device-side registry trust may require privileged operations and, depending on runtime behavior, a container runtime refresh or restart.
- Different clients may surface TLS failures differently; THOR needs normalized diagnostics.
- Some registries may not expose full catalog APIs, so explicit image-reference validation must remain available even when browsing is limited.

### Integration dependencies

| Dependency | Owner | Status | Risk | Mitigation |
|---|---|---|---|---|
| macOS certificate trust APIs | THOR app | Available | Medium | Build validation + fallback diagnostics |
| Jetson-side trust/auth application | THOR agent | Not implemented | High | Ship as explicit v1 backend surface |
| Docker pull execution path | THOR agent | Partially available | Medium | Add trust/auth-aware preflight |
| Registry catalog/tag APIs | External registry | Variable | Medium | Support degraded mode by image reference |
| Secure secret storage | THOR app | Available | Low | Reuse Keychain pattern already in product |
| Device status persistence | THOR app/db | Available but incomplete | Low | Extend existing state model |

### Data requirements

THOR will need persistent models for:

- Registry profile metadata
- Certificate metadata and trust state
- Registry-to-device assignment state
- Last validation results for Mac and devices
- Optional cached browse results and image selections

### Performance requirements

- Mac trust validation should return within 5 seconds for a reachable local registry
- Device readiness validation should return first results within 10 seconds per device
- Image pull/deploy preflight should complete before deployment begins, not during container failure handling

## 5. Success Metrics & Measurement

| Metric | Type | Baseline | Target | Measurement |
|---|---|---:|---:|---|
| Successful end-to-end secure registry onboarding inside THOR | Primary | 0% of flows supported in-app today | 90% of internal dogfood attempts succeed without terminal usage | Internal dogfood checklist + local validation event log |
| Time from new cert import to first successful secure pull on a Jetson | Secondary | 15-20 min manual workflow estimate | < 5 min median in dogfood sessions | Timed QA script + job timestamps |
| Time from opening the Registry workspace to first green preflight board | Secondary | Not measurable today | < 90 seconds for known template-based setups | Rehearsal stopwatch + event timestamps |
| Number of terminal commands required for secure registry setup | Secondary | 8+ manual commands | 0 required for supported v1 flows | Demo runbook audit |
| Deploy failures caused by missing trust/auth discovered after deploy starts | Guardrail | Common/manual today | 0 in validated THOR flows | Preflight logs + failure categorization |
| Existing public image workflows that regress after feature launch | Guardrail | 0 regressions today | 0 regressions allowed | Regression test plan + simulator smoke tests |

### Measurement plan

- Track local validation runs, pass/fail reason, and duration in THOR job/event history
- Run a scripted internal demo checklist on at least one Docker Registry v2 instance and one Zot instance
- Require one “green path” demo rehearsal on or before 2026-04-20
- Treat any post-preflight TLS/auth failure in a supported flow as a P0 defect before showcase freeze

## 6. UX Flow

### Proposed product surface

- A new global **Registry** workspace in THOR for profiles, certs, trust, auth, and browsing
- A primary **Setup Wizard** entry point for first-run and recovery flows
- A **Preflight Board** that compresses readiness into one demo-safe view
- Lightweight registry-aware actions in **Docker**, **Deploy**, and **ANIMA** surfaces
- Device-level readiness visibility within each registry profile
- Optional quick access from **Settings** for default registry behavior

### Core flow

`Open Registry workspace`
→ `Start Setup Wizard`
→ `Choose template or generic registry`
→ `Create registry profile`
→ `Import CA certificate`
→ `Review cert identity`
→ `Trust on this Mac`
→ `Add auth (optional)`
→ `Select one or more Jetsons`
→ `Apply trust/auth to devices`
→ `Run preflight board`
→ `Browse repo/tag or enter image reference`
→ `Test pull`
→ `Pull image or start deploy`
→ `See ready / failed state`

### Failure branch

`Validation fails`
→ `Show stage: cert / auth / reachability / device trust / pull test`
→ `Present corrective action`
→ `Retry validation`

### Screen/state requirements

#### Registry List

- Shows all registry profiles
- Shows trust state, validation state, and affected device count
- Empty state explains why registry profiles matter for secure local artifact workflows

#### Registry Detail

- Certificate panel: subject, issuer, fingerprint, expiry, trust state
- Auth panel: auth mode, last verified time, credential status
- Device panel: assigned devices and per-device readiness
- Validation panel: latest pass/fail results
- Repository browser: repositories, tags, digests when available

#### Setup Wizard

- Template selection for Docker Registry, Zot, Harbor, GHCR, and generic OCI
- Smart defaults for scheme, port, and display naming
- Step-by-step flow with progress persistence
- Final completion state that routes to test pull or deploy

#### Preflight Board

- Staged readiness rows for Mac trust, registry reachability, credentials, device trust, and pull test
- Green/yellow/red summary suitable for rehearsals and demos
- Inline recovery actions for each failed stage
- Ability to rerun preflight without reopening the profile editor

#### Pull/Deploy Integration

- Registry-aware image selector or explicit image reference entry
- Preflight banner with green/yellow/red readiness
- Blocking state for missing trust/auth on required flows

#### Required non-happy states

- Invalid certificate format
- Trust permission denied on Mac
- Device trust push failed
- Registry reachable but auth invalid
- Registry browsing unsupported
- Certificate expired
- Certificate fingerprint changed
- Pull test timed out
- Mac trusted but Jetson not trusted
- Jetson trusted but credentials not applied
- Registry ready, but selected image reference missing or unauthorized

## 7. Release & Rollout Plan

### Rollout strategy

Use a phased rollout with feature gating inside THOR. Ship the vertical slice required for internal dogfood first, then harden for the showcase.

### Launch criteria

- Mac trust import/remove works on a real certificate
- At least one secure local registry profile works end-to-end with Docker Registry v2
- At least one secure local registry profile works end-to-end with Zot
- One or more Jetson devices can be marked registry-ready from THOR
- Pull preflight correctly blocks invalid trust/auth cases
- Existing Docker and ANIMA public-image flows still work

### Rollback plan

- Hide registry UI behind a feature flag or equivalent launch guard if the flow is unstable
- Preserve existing Docker/ANIMA behavior when registry features are disabled
- Allow operators to remove trust entries and return to manual workflows if needed

### Communication plan

- Internal: engineering + demo stakeholders get a rehearsal checklist and known-limits note
- External/demo: present THOR as the secure artifact control surface for local Jetson labs and demos

### Rollout phases

| Phase | Audience | Criteria to proceed | Target date |
|---|---|---|---|
| PRD sign-off | Internal | Scope accepted, no P0 ambiguity | 2026-04-06 |
| Alpha vertical slice | Internal | Mac trust + one-device validation works | 2026-04-12 |
| Beta dogfood | Internal demo team | Wizard + multi-device trust/auth + pull preflight works | 2026-04-16 |
| Showcase hardening | Internal | Docker Registry + Zot both pass demo runbook | 2026-04-20 |
| Demo freeze | Internal | No P0/P1 issues open for demo path | 2026-04-22 |
| Shenzhen showcase | External/demo | Feature rehearsed and frozen | 2026-04-23 |

## Open Questions Resolved for v1

- Support only anonymous and username/password auth in v1: yes
- Support Docker Registry v2 and Zot explicitly in v1: yes
- Require device-side validation, not just Mac-side trust: yes
- Treat registry browsing as part of the product surface, but allow degraded mode by explicit image reference: yes

## Completion Summary

| Field | Value |
|---|---|
| Mode selected | CREATE |
| Product | THOR |
| User stories | 12 total |
| P0 stories | 10 |
| P1 stories | 2 |
| Acceptance criteria | 36 |
| Dependencies mapped | 6 |
| High-risk dependencies | 1 |
