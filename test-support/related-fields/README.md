# Optional integration fixtures

This directory is outside the production package. Copy its `objects` and `classes`
into a temporary Salesforce project alongside the production classes and their
dependencies, then use `sf project deploy start --dry-run --test-level RunSpecifiedTests`
with `--tests FlexiPageCustomRelatedFieldsTest` (plus tests for dependency classes).
Do not deploy these fixtures to production.

The tests verify custom `__r` traversal, nested custom lookups, reference labels,
and related field-level security under a user with the `Minimum Access - Salesforce`
profile. Fixture records are isolated Apex test data. The test object itself is
included only in the temporary validation package.
