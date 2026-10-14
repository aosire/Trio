# Glucose forecast fifteen minutes from now

Base: chart PR #3 head `7b27e35805df622f3622cf4f180e502430b12d06`, rooted in merged fork `2eb1a73354bc10667b5c26bffad170b5206bfd81`; upstream `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. Branch: `codex/fifteen-minute-glucose`. Stacked after the chart PR to keep shared-file changes mergeable in order.

Home's right header adds **In 15 min**, a value/range in the chosen glucose unit, and the forecast age. Tap it for the explanation. Existing eventual glucose remains visible. This display is initially scoped to Home; Watch and Live Activity do not receive a new serialized field.

The selector captures immutable, explicitly indexed IOB/COB/UAM/ZT samples from one determination, together with its `deliverAt` origin. It targets the current clock plus 900 seconds. Exact five-minute steps use that sample; targets between steps interpolate the two endpoints. Short/missing/duplicate-index/invalid curves are excluded without extrapolation or zero padding. The minimum and maximum across available scenarios form the displayed range, not a statistical confidence interval or a guaranteed outcome. A single available value is shown as one number.

Forecast and latest-glucose ages must both be below twelve minutes, consistent with the existing glucose display freshness window. Missing dates, future/non-finite timestamps or no usable scenarios produce a dash. The existing Home timer refreshes the target and age. Core Data fetches use a captured determination object ID; a superseded/cancelled fetch cannot publish as a newer origin. The header also verifies the snapshot origin still matches the selected determination.

The original low-alarm `ForecastedGlucoseEvaluator` remains unchanged. The display selector does not mutate predictions, dosing inputs, stored readings, alarms or pump commands. Formatting converts canonical mg/dL values only for presentation and includes units and age in VoiceOver.

Fourteen focused tests cover fresh/aged/exact/interpolated targets, scenario reduction, missing/short/gapped/duplicate/out-of-order samples, invalid values, freshness boundaries, invalid/future dates, DST, unit/locale formatting and input immutability. Full algorithm/iOS CI must pass on the proposed commit before readiness. Actual Home layout, large text and VoiceOver have not been visually/device verified.

Preserve the distinction between this scenario range and alarm/dosing prediction selection when merging upstream. Revert the feature commits to remove the display; no settings/data migration or driver rollback is required. No release, signing change or live pump test is part of this work.
