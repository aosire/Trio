# Fixed Home glucose chart bounds

Base: `2eb1a73354bc10667b5c26bffad170b5206bfd81` after the owner's merge of PR #2. Upstream: `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. Branch: `codex/fixed-glucose-chart`.

In Settings > Features > User Interface, enable **Use fixed glucose chart bounds**, edit the minimum/maximum in the current glucose unit, then select **Apply chart bounds**. Both bounds are committed together. Invalid drafts leave the existing domain unchanged. Disable the option to restore the original automatic scale. Existing installations remain automatic.

Bounds are stored in mg/dL and validated on input and decoding. The Home chart uses the exact fixed domain without automatic padding. Off-scale glucose points and selection highlights are hidden; continuous smoothed/forecast curves are clipped at the plot edge, without replacing their values with a boundary value. Fixed-mode forecast cones use linear interpolation to avoid spline overshoot. Out-of-range threshold/override/temp-target rule marks are omitted. The chart's spoken summary identifies the fixed scale and hidden readings while retaining the actual latest glucose.

This is a display preference. Stored readings, prediction data, current glucose, history, alarms, statistics and dosing inputs are not filtered or rewritten. Watch, Live Activity and the Treatments calculator chart keep their existing scales. Meal/insulin annotations are clipped with the Home plot and may fall outside the visible domain; they remain available in Treatments/history.

Regression tests cover the reported single 30 mmol/L outlier, missing data, original automatic steps, invalid domains, unit conversion including narrow domains, legacy settings, settings round-trip, corrupt imports and locale-aware input. Full iOS and algorithm GitHub Actions results must be inspected on the proposed commit before marking the PR ready. Physical phone layout, Dynamic Type, VoiceOver and plot rendering still require visual/device checks; unit tests do not establish them.

Upstream merges must preserve canonical storage and keep clipping within presentation code. No dependency or driver revision changes. Revert this feature's commits to restore the old behavior; additional persisted keys can be ignored by older code.
