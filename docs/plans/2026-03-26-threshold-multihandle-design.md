# Threshold Multi-Handle Control Design

**Date:** 2026-03-26
**Status:** Approved

## Goal

Replace the temporary stack of native sliders with a single threshold control that behaves like ordered set points on one curve.

## Approved Behavior

- show all thresholds on a single horizontal track
- each threshold has its own handle
- dragging a handle stops at neighboring handles
- handles never cross
- the threshold ordering remains stable

## Implementation Notes

- reuse the existing threshold data model as ordered `Double` values in `0...1`
- clamp each dragged value between `previous + minimumGap` and `next - minimumGap`
- keep the control in `ThresholdSliderView.swift`
- expose each handle as an adjustable accessibility element with a percentage value
