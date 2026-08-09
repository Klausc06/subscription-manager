# ADR 0001: Keep application behavior behind SubscriptionWorkspace

- Status: Accepted
- Date: 2026-07-27

## Context

The product has several native surfaces and integrates with SwiftData, private
CloudKit, a preset catalog, exchange-rate snapshots, EventKit, widgets, App
Intents, and a Mac menu-bar extra. Letting each surface coordinate those systems
would produce different behavior and make eventual-consistency bugs difficult
to reproduce.

## Decision

`SubscriptionWorkspace` is the primary application seam. A UI or system
extension sends a command or query to the workspace and observes its public
state. It does not fetch or reconcile an integration directly.

The workspace receives narrow injected adapters for:

1. subscription persistence;
2. time and application-generated identifiers;
3. the preset catalog;
4. exchange-rate snapshots;
5. Calendar projection;
6. synchronization status and delivery;
7. portable exports.

Each adapter exposes only the functional interface required by its current
consumer. New behavior extends these boundaries only when an approved issue
requires it. This avoids speculative APIs while preserving the dependency
direction.

Production implementations live outside `SubscriptionCore`. Behavioral tests
use in-memory adapters and assert workspace state rather than framework object
layout or private calls. Framework-specific adapters receive separate contract
tests.

## Consequences

- SwiftUI, widgets, App Intents, and the menu-bar extra share one behavior.
- Workspace behavior can be tested without SwiftData.
- SwiftData can be validated independently with an in-memory container.
- CloudKit and Calendar remain independent, replaceable, eventually consistent
  systems.
- New adapter methods must be driven by an externally visible workspace test.
