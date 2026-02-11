# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FlexiPageRecordForm is a Salesforce Lightning Web Component suite that dynamically renders record forms based on FlexiPage metadata. It supports both Record Pages and Flow Screens, with features including dynamic field visibility rules, conditional formatting, default values, field history tracking, and full Flow Builder integration via a Custom Property Editor (CPE).

## Build and Deployment Commands

```bash
# Deploy specific LWC to default org
sf project deploy start --source-dir force-app/main/default/lwc/flexiPageRecordForm
sf project deploy start --source-dir force-app/main/default/lwc/flexipageRecordFormCPE

# Deploy Apex classes
sf project deploy start --source-dir force-app/main/default/classes/FlexiPageToolingService.cls
sf project deploy start --source-dir force-app/main/default/classes/FlexiPageMetadataService.cls
sf project deploy start --source-dir force-app/main/default/classes/FlexiPageCacheService.cls

# Deploy static resources
sf project deploy start --source-dir force-app/main/default/staticresources

# Deploy all project files
sf project deploy start --source-dir force-app

# Run all Apex tests
sf apex run test --test-level RunLocalTests --wait 10

# Run specific test class
sf apex run test --class-names FlexiPageToolingServiceTest --wait 10

# Run LWC Jest tests
npm run test:unit

# Run tests with coverage
npm run test:unit:coverage

# Lint JavaScript
npm run lint

# Format code
npm run prettier
```

## Architecture

### Component Structure

**flexipageRecordForm LWC** (`force-app/main/default/lwc/flexiPageRecordForm/`)
- Main component for rendering dynamic forms from FlexiPage metadata
- Supports targets: `lightning__RecordPage`, `lightning__FlowScreen`
- Uses `NavigationMixin` for record navigation after save
- Wire adapters: `getFieldValues`, `getObjectInfo`
- Key @api properties:
  - `recordId` - Record ID for edit mode
  - `objectApiName` - SObject API name
  - `flexiPageName` - FlexiPage developer name
  - `fieldPageName` - Field-based dynamic page selection
  - `defaultValues` - Format: `Field1__c:Value1;Field2__c:Value2`
  - `excludedFields` - Comma-separated field API names to hide
  - `varRecord` - Output variable for Flow context (generic SObject type T)
  - `isReadOnly` - Display in read-only mode
  - `flowContext` - Boolean indicating Flow context (set automatically by CPE)
  - `cardTitle` - Card header title
  - `showIcon` - Show object icon in header
  - `useFieldHistory` - Enable field history tracking
  - `enableVisibilityRules` - Enable/disable visibility rule evaluation
  - `enableCollapsibleSections` - Make sections collapsible
  - `showSectionHeaders` - Display section header labels
  - `showEditButtons` - Show inline edit buttons
  - `enableConditionalFormatting` - Apply conditional formatting rules
  - `highlightRequiredFields` - Visual highlight for required fields
  - `saveLabel` / `cancelLabel` - Custom button labels (Record Page only)
  - `debugMode` - Enable debug logging

**Key computed properties:**
- `allExcludedFields` - Merges user-specified excluded fields with system read-only fields (`CreatedById`, `LastModifiedById`, `Id`, `SystemModstamp`, `CreatedDate`, `LastModifiedDate`, `OwnerId`) which are auto-excluded in edit mode
- `showActionButtons` - Returns `false` when `flowContext` is truthy; Save/Cancel buttons are hidden in all Flow contexts (Flow navigation handles record submission)

**flexipageRecordFormCPE LWC** (`force-app/main/default/lwc/flexipageRecordFormCPE/`)
- Custom Property Editor for Flow Builder integration
- Handles generic type mapping (propertyType T extends SObject)
- Modal-based UI for configuring default values and excluded fields
- Displays KAPerficientBadge footer via static resource
- On initialization, dispatches `flowContext = true` to ensure the main component knows it's in a Flow context (workaround for unreliable Boolean `default` in meta.xml)
- Dispatches Flow Builder events:
  - `configuration_editor_input_value_changed`
  - `configuration_editor_generic_type_mapping_changed`
- Uses Apex methods: `getFlexiPageFields`, `getObjectFields`, `getAllSObjects`

**stencil LWC** (`force-app/main/default/lwc/stencil/`)
- Loading skeleton component used as a placeholder while data loads
- Supports configurable iterations and column counts

### Apex Services

**FlexiPageToolingService** (`force-app/main/default/classes/FlexiPageToolingService.cls`)
- Facade service that delegates to `FlexiPageMetadataService`
- AuraEnabled methods:
  - `getFlexiPageMetadata(developerName)` - Returns FlexiPage JSON configuration
  - `getFieldValues(recordId, objectApiName)` - Returns all field values for a record
  - `getUiFormatSpecificationSet(uiFormatSpecSetName)` - Returns conditional formatting rules
  - `getAvailableFlexiPages(objectApiName)` - Returns FlexiPages for an object
  - `getObjectFields(objectApiName)` - Returns field metadata for an object
  - `getAllSObjects()` - Returns list of accessible SObjects
- Includes custom comparators for sorting (`FlexiPageComparator`, `FieldComparator`, `SObjectComparator`)

**FlexiPageMetadataService** (`force-app/main/default/classes/FlexiPageMetadataService.cls`)
- Core metadata service using session-based Metadata API calls
- Handles FlexiPage metadata retrieval and parsing
- Provides `getFlexiPageFields` and `getObjectFields` for CPE field selection
- Uses `MetadataService` for HTTP callouts

**FlexiPageCacheService** (`force-app/main/default/classes/FlexiPageCacheService.cls`)
- Caching layer using `FlexiPage_Cache__c` custom object
- 60-minute default cache timeout (configurable)
- Transaction-level caching via static maps
- Methods:
  - `getCachedMetadata(cacheKey)` - Retrieve cached data
  - `setCachedMetadata(cacheKey, metadataJson)` - Store data in cache
  - `invalidateCache(cacheKey)` - Clear specific cache entry
  - `invalidateAllCache()` - Clear all cached data

**MetadataService** (`force-app/main/default/classes/MetadataService.cls`)
- HTTP service for Salesforce Metadata API callouts
- Session-based authentication

### Key Data Flow

1. Component initializes -> `connectedCallback` determines new vs existing record
2. If `flowContext` is set, dispatches initial default values via `FlowAttributeChangeEvent`
3. If `fieldPageName` is set, reads FlexiPage name from field value
4. Calls `getFlexiPageMetadata()` via `FlexiPageMetadataService`
5. Cache layer checks `FlexiPage_Cache__c` for existing data
6. Parses FlexiPage JSON via `utils.js:parseFlexiPageJson()`
7. If `enableConditionalFormatting`, fetches `UiFormatSpecificationSet`
8. Evaluates visibility rules against record data
9. Renders sections/fields with `lightning-record-edit-form`
10. In edit mode, read-only system fields are auto-excluded from rendering
11. On Record Pages: Save/Cancel buttons shown; on Flow: buttons hidden (rely on Flow navigation)
12. On save, dispatches Flow events via `FlowAttributeChangeEvent` and navigates as needed

### Flow Context Behavior

- `flowContext` is set to `true` by the CPE on initialization via `configuration_editor_input_value_changed`
- When `flowContext` is true, Save/Cancel buttons are hidden in all cases (new and existing records)
- Flow navigation (Next/Finish) handles record submission; the component outputs `varRecord` for downstream Flow usage
- For existing Flows: re-open the screen element in Flow Builder and save to ensure `flowContext` is persisted

### Read-Only System Fields

The following fields are automatically excluded from rendering in edit mode (they remain visible in read-only mode):
- `CreatedById`, `LastModifiedById`, `Id`, `SystemModstamp`, `CreatedDate`, `LastModifiedDate`, `OwnerId`

These are also stripped from save payloads as a safety measure.

### Visibility Rules Evaluation

The component evaluates FlexiPage visibility rules client-side:
- Supported operators: CONTAINS, EQUAL, NE, GT, GE, LE, LT
- Boolean filters with AND/OR logic
- Field references use `{!Record.FieldName}` format
- Rules evaluated against current record field values

### Conditional Formatting

Supports `UiFormatSpecificationSet` for field styling:
- Text colors: success, error, warning, blue, purple, yellow
- Text styles: bold, italic, underline, line-through
- Icons: utility icons with color classes
- Border styles: success, error, warning

## Dependencies

- **Custom Object**: `FlexiPage_Cache__c` - Required for metadata caching
  - Fields: `Cache_Key__c`, `Metadata_JSON__c`, `Last_Updated__c`
- **Custom Object**: `Strategic_Interaction__c` - Used in test classes
- **Static Resource**: `KAPerficientBadge` - PNG badge displayed in CPE footer
- **LWC Dependency**: `c-fsc_flow-combobox` - Flow combobox component used in CPE for variable selection
- **LWC Dependency**: `c-stencil` - Loading skeleton component
- **Remote Site Settings**: Required for Metadata API callouts

## File Structure

```
force-app/main/default/
├── lwc/
│   ├── flexiPageRecordForm/          # Main component
│   │   ├── flexiPageRecordForm.js
│   │   ├── flexiPageRecordForm.html
│   │   ├── flexiPageRecordForm.css
│   │   ├── flexiPageRecordForm.js-meta.xml
│   │   └── utils.js                  # FlexiPage JSON parser
│   ├── flexipageRecordFormCPE/       # Flow Builder CPE
│   │   ├── flexipageRecordFormCPE.js
│   │   ├── flexipageRecordFormCPE.html
│   │   ├── flexipageRecordFormCPE.css
│   │   └── flexipageRecordFormCPE.js-meta.xml
│   └── stencil/                      # Loading skeleton component
│       ├── stencil.js
│       ├── stencil.html
│       ├── stencil.css
│       ├── stencil.js-meta.xml
│       ├── stencilFeedType.html
│       ├── stencilListType.html
│       └── stencilListType.css
├── classes/
│   ├── FlexiPageToolingService.cls        # Facade service
│   ├── FlexiPageToolingServiceTest.cls    # Test class
│   ├── FlexiPageMetadataService.cls       # Core metadata service
│   ├── FlexiPageMetadataServiceTest.cls   # Test class
│   ├── FlexiPageCacheService.cls          # Caching layer
│   ├── FlexiPageCacheServiceTest.cls      # Test class
│   ├── MetadataService.cls                # HTTP callout service
│   └── MetadataServiceTest.cls            # Test class
├── objects/
│   └── FlexiPage_Cache__c/               # Cache custom object
└── staticresources/
    ├── KAPerficientBadge.png              # CPE footer badge image
    └── KAPerficientBadge.resource-meta.xml
```

## Salesforce Development Notes

- Minimum Apex code coverage: 90%
- Deploy only files being worked on directly
- Do NOT delete files - move to `archived_files/` directory instead
- Always deploy then test Apex changes iteratively
- Current default org: GS0
