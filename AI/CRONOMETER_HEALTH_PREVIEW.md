# Cronometer source and time qualification

Request: import timed carbs, fat and protein from Cronometer with the existing FPU behavior and an explicit review before dosing. This first PR supplies the read-only phone-side inspection needed to qualify the external data. It does **not** complete meal import or bolus integration.

Base: exercise PR #5 repaired head `061bcd54de0aa7cda72021329eb98d5f607eca3f`, stacked after forecast #4 and chart #3; fork base `2eb1a73354bc10667b5c26bffad170b5206bfd81`; upstream `1bacd86fb19dc325dff044b8cfe52fb7da6c8b98`. Branch `codex/cronometer-inbox`.

## Why qualification is required

The owner reports incorrect Cronometer sample dates while Health's Date Added field is accurate. The connected Health export tool exposes only time/value/unit records, without source, sample UUID, metadata or Date Added. Its uploaded numeric logs cannot establish the raw source format or a universal correction. No personal records, timestamps or quantities from that inspection are copied into this repository.

Apple's public [HKObject](https://developer.apple.com/documentation/healthkit/hkobject), [HKSample](https://developer.apple.com/documentation/healthkit/hksample) and [HKQuantitySample](https://developer.apple.com/documentation/healthkit/hkquantitysample) APIs expose source, UUID, metadata and sample start/end dates, but not the Date Added/creation-date field displayed in Health. Do not use private APIs, parse object debug descriptions for hidden dates, or substitute the first time Trio observes/downloads a sample. Cronometer may have useful custom metadata, but its existence and meaning have not been established. [Cronometer's integration guide](https://support.cronometer.com/hc/en-us/articles/360020734212-Apple-Health-Apple-Watch) does not document stable per-food metadata/grouping guarantees.

## Preview behavior

Settings > Features > Cronometer Health preview requests read access only for dietary carbohydrates, total fat and protein, after an explicit Connect action. The user must select the source; no source is silently trusted by its display name. Trio's own Health source is excluded from discovery and sample selection. Existing Health export behavior/settings are unchanged and need not be disabled for this preview.

The new UI catalog is English-source. The base and English Health read-purpose text explain the preview; other existing purpose-string translations need review before use in those languages.

Refresh reads only that source over a sample-time window from 48 hours ago to 24 hours ahead, including future-dated records for diagnosis. More than 1,000 samples of any macro rejects the read rather than silently truncating it. All three queries must succeed before a new preview is published. Empty results do not establish that permission was granted or denied. No background observers, automatic reads, exports or logs of sample contents are added.

Groups require the exact same source/start/end timestamps. Nearby times are not guessed to be one meal. Missing or invalid macros remain unknown; a recorded zero remains zero. Time spans stay visible with a warning. Raw samples, UUIDs, source and metadata can be inspected. Correction defaults to zero, ranges from -1,440 to +1,440 minutes in five-minute steps, affects only the displayed preview, and never changes source dates, identities or quantities. All displayed times use the phone's time zone. Date Added is explicitly described as unavailable.

## Safety boundary and remaining implementation

The gateway and view have no carb-storage, FPU-generator, algorithm, insulin, authorization-to-bolus or pump-command dependency. No preview data becomes a meal, COB, FPU or calculation input. This is intentionally a qualification step because logging changes dosing inputs even before a bolus is requested.

Before implementing a dosing-connected inbox, establish the real source identity, timestamp meaning/correction, nutrient completeness, total-versus-net carbohydrate basis, and stable IDs for source edits/deletes. Then add durable at-most-once consumption and reconciliation, an atomic multi-meal/receipt/FPU transaction, configured per-macro and batch limits, protection against existing manual logs, revalidation of the source snapshot and settings, and explicit meal review. Reuse the existing FPU policy once per meal when enabled. Preserve raw source identity independently of corrections. Imported meals must not be exported back into Health. Source changes must not automatically revise already-dosed meals or trigger another bolus. A later explicit bolus action must use the existing calculation/confirmation/authentication path.

The current BaseCarbsStorage batch interface persists only the last real entry and converts FPUs from the last entry; it is unsuitable for directly passing a selected multi-meal array. It also swallows some save failures. A separate atomic import operation is required; do not claim calling that interface is a working batch importer.

## Verification and upstream considerations

Seventeen regression tests cover source separation, exact-time grouping, unknown versus zero macros, spans, duplicate IDs, invalid dates/amounts/overflow, bounded corrections, unchanged raw identities/metadata, future dates and quantity type mapping. Fixtures are synthetic. Full exact-head iOS and algorithm CI must pass and logs be inspected before readiness. The actual Cronometer payload, read permission flow, locked-phone errors, display/accessibility and source timing remain unverified until inspected on a phone. Unit tests cannot establish the external source's correctness.

Keep the dedicated gateway, view, catalog and test registrations separate from ordinary Health export. No Core Data migration, dependency change, driver update or release dispatch. Revert the preview commit to remove it; there is no persisted preview data to migrate. Future upstream changes may need conflicts resolved in Features/project registrations, preserving the read-only boundary until import verification exists.
