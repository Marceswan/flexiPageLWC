# Related-object fields

FlexiPage field items such as `Record.Account.Name`, `Record.Account.Parent.Name`, and `Record.Customer__r.Status__c` retain their complete paths. Related fields display read-only in both view and edit modes, matching Dynamic Forms. They are excluded from base-record defaults, saves, and Flow output.

Apex resolves relationship names through describe metadata, validates each lookup and terminal field's read access, and retrieves values with a user-mode query. Null lookups yield null values. Invalid/inaccessible paths are omitted without invalidating valid paths; inaccessible related fields are not rendered. Lookup display names use relationship selections rather than queries per field. Dynamic Forms supports two parent hops and excludes polymorphic relationship traversal, so the resolver follows those limits.

Related field display preserves zero/false, uses type-aware Lightning formatters, and participates in visibility/conditional formatting. Rule dependencies are fetched even when their controlling fields are not on the layout. New records have no persisted relationship data, so related values remain blank until saved and refreshed. Unsaved lookup changes do not preview different parent values.

Validation: LWC Jest tests cover metadata parsing, rendering in all modes, visibility dependencies, exclusions, and payload isolation. Apex regression tests cover standard/nested paths, null chains, reference labels, malformed paths, and query count. The optional `test-support/related-fields` fixtures verify custom lookups and field permissions in Salesforce without adding production objects.

Source: https://help.salesforce.com/s/articleView?id=sf.dynamic_forms_spanning_fields.htm&language=en_US&type=5

## Validation result — 2026-10-19

- MBP-VST-Full check-only validation `0AfiJ0000007elVSAQ`: succeeded; 33 components compiled; all 118 Apex tests passed; no coverage warnings. FlexiPageToolingService coverage: 230/249 lines (92.4%).
- All seven new Apex tests passed, including custom `__r` chains and a Minimum Access user denied read access to a related field. Fixture permissions are explicitly assigned instead of assuming the deploying user's profile grants access to new fields.
- Local verification: 17 LWC Jest tests, 5 configuration tests, targeted no-undefined/unused-variable lint, and Apex syntax/format checks passed.
- Salesforce Code Analyzer PMD could not run: Java v11+ is not installed.
- No changes were deployed. The check-only package is at `/private/tmp/flexipage-related-validation`; its test fixtures are preserved under `test-support/related-fields`. Machine-readable results: `docs/validation/related-fields-2026-10-19.json`.

## Existing org upgrade constraints

The original source bundle cannot directly replace the org bundle yet. The org uses `flexipageRecordForm` while the checkout uses `flexiPageRecordForm`. Existing Flow versions also require a `fieldsName` output property absent from this checkout. These compatibility issues predate this change. The isolated validation used `flexiPageFormRelatedCheck` with the same component implementation and included missing repository cache/metadata dependencies. Restore the existing Flow API contract and reconcile the bundle name before deploying an upgrade to the existing component.
