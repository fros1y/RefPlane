# Simplification Cancellation & Restart Design

## Goal

When simplification settings change (method or parameters), cancel any in-flight simplification job and immediately restart with the newest config.

## Problem

Current behavior uses request IDs to ignore stale results, but the previous simplify computation still runs to completion in the worker. On large images this wastes CPU and delays responsiveness.

## Design

1. Keep queued worker processing model for ordering.
2. Add cooperative cancellation to simplify algorithms:
   - Pass `AbortSignal` from worker into simplify dispatcher and algorithm implementations.
   - Check cancellation at row/iteration boundaries.
   - Periodically yield to event loop (`setTimeout(0)`) so worker can receive newer messages and trigger abort.
3. In worker `onmessage`, when a new `simplify` request arrives:
   - Abort currently running simplify request (if any).
   - Queue new request normally.
4. For canceled simplify jobs, return an `AbortError` worker error payload so app decrements in-flight request counters without applying stale output.
5. In app message handler, suppress console noise for `AbortError` while preserving existing stale-result guards.

## Why this approach

- Avoids terminating/recreating the whole worker.
- Preserves non-simplify pipeline behavior and ordering.
- Provides fast restart semantics with minimal API surface changes.

## Validation

- Update simplify dispatcher unit tests to await async execution.
- Add cancellation test: aborted signal causes `runSimplify` to reject with `AbortError`.
