# FlexiPageRecordForm

A Salesforce Lightning Web Component suite that dynamically renders record forms based on FlexiPage metadata. Supports both Record Pages and Flow Screens with full Flow Builder integration via a Custom Property Editor.

## Features

- **Dynamic Form Rendering** - Automatically renders fields from FlexiPage layouts
- **Visibility Rules** - Client-side evaluation of FlexiPage visibility rules
- **Conditional Formatting** - Apply styling based on UiFormatSpecificationSet rules
- **Flow Builder Integration** - Custom Property Editor with generic SObject type support
- **Field History Tracking** - Optional tracking of field changes
- **Caching Layer** - FlexiPage metadata caching for improved performance
- **Default Values** - Pre-populate fields in create mode
- **Collapsible Sections** - Optional collapsible section headers
- **Read-Only Mode** - Display fields in read-only format
- **Smart Field Exclusion** - Read-only system fields auto-excluded in edit mode
- **Flow-Aware UI** - Save/Cancel buttons hidden in Flow context; relies on Flow navigation

## Components

### flexipageRecordForm

Main component that renders the dynamic form.

**Targets:**
- `lightning__RecordPage` - Use on record pages
- `lightning__FlowScreen` - Use in Screen Flows

**Key Properties:**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `recordId` | String | | Record ID for edit mode |
| `objectApiName` | String | | SObject API name |
| `flexiPageName` | String | | FlexiPage developer name |
| `fieldPageName` | String | | Field to read FlexiPage name from |
| `defaultValues` | String | | Format: `Field1__c:Value1;Field2__c:Value2` |
| `excludedFields` | String | | Comma-separated field API names to hide |
| `isReadOnly` | Boolean | `false` | Display in read-only mode |
| `showIcon` | Boolean | `false` | Show object icon in header |
| `cardTitle` | String | | Card header title |
| `flowContext` | Boolean | | Set automatically by CPE in Flow context |
| `enableVisibilityRules` | Boolean | `false` | Enable visibility rule evaluation |
| `enableConditionalFormatting` | Boolean | `false` | Apply conditional formatting |
| `enableCollapsibleSections` | Boolean | `false` | Make sections collapsible |
| `showSectionHeaders` | Boolean | `false` | Display section headers |
| `showEditButtons` | Boolean | `false` | Show inline edit buttons |
| `useFieldHistory` | Boolean | `false` | Track field changes |
| `highlightRequiredFields` | Boolean | `false` | Visual highlight for required fields |
| `saveLabel` | String | `Save` | Custom Save button label (Record Page only) |
| `cancelLabel` | String | `Cancel` | Custom Cancel button label (Record Page only) |
| `varRecord` | SObject | | Output variable for Flow (generic type T) |
| `debugMode` | Boolean | `false` | Enable debug logging |

**Auto-Excluded System Fields (Edit Mode):**

The following fields are automatically excluded from the form in edit mode. They remain visible in read-only mode:

`CreatedById`, `LastModifiedById`, `Id`, `SystemModstamp`, `CreatedDate`, `LastModifiedDate`, `OwnerId`

**Flow Context Behavior:**

When used in a Flow Screen, Save/Cancel buttons are suppressed entirely. The component relies on Flow navigation (Next/Finish) for record submission and outputs the record via `varRecord` for downstream Flow usage. The CPE automatically sets `flowContext = true` when configuring the component.

### flexipageRecordFormCPE

Custom Property Editor for Flow Builder configuration.

**Features:**
- SObject selection with searchable dropdown
- FlexiPage developer name input
- Default values configuration via modal with field search
- Record variable mapping for bulk default values
- Excluded fields dual-listbox selector
- Generic type mapping for Flow variables (propertyType T extends SObject)
- Automatically sets `flowContext = true` for the main component
- Footer badge via `KAPerficientBadge` static resource

### stencil

Loading skeleton component used as a placeholder while form data loads.

## Apex Services

| Class | Description |
|-------|-------------|
| `FlexiPageToolingService` | Facade service exposing AuraEnabled methods |
| `FlexiPageMetadataService` | Core service for Metadata API calls and field retrieval |
| `FlexiPageCacheService` | Caching layer using `FlexiPage_Cache__c` custom object |
| `MetadataService` | HTTP callout service for Metadata API |

## Installation

### Prerequisites
- Salesforce org with API version 61.0+
- Remote Site Settings configured for Metadata API
- `FlexiPage_Cache__c` custom object deployed
- `fsc_flow-combobox` LWC available in the org (used by CPE)

### Deploy to Org

```bash
# Clone the repository
git clone https://github.com/Marceswan/flexiPageRecordForm.git
cd flexiPageRecordForm

# Authenticate to your org
sf org login web -a MyOrg

# Deploy all components
sf project deploy start --source-dir force-app
```

### Deploy Specific Components

```bash
# Deploy main LWC only
sf project deploy start --source-dir force-app/main/default/lwc/flexiPageRecordForm

# Deploy CPE
sf project deploy start --source-dir force-app/main/default/lwc/flexipageRecordFormCPE

# Deploy Apex services
sf project deploy start --source-dir force-app/main/default/classes/FlexiPageToolingService.cls
sf project deploy start --source-dir force-app/main/default/classes/FlexiPageMetadataService.cls
sf project deploy start --source-dir force-app/main/default/classes/FlexiPageCacheService.cls

# Deploy static resources
sf project deploy start --source-dir force-app/main/default/staticresources
```

## Usage

### On a Record Page

1. Navigate to a record page in Lightning App Builder
2. Drag the `flexipageRecordForm` component onto the page
3. Configure properties:
   - Select the FlexiPage to render
   - Set card title and display options
   - Configure excluded fields if needed
4. Save/Cancel buttons will appear for inline editing

### In a Flow

1. Add a Screen element to your Flow
2. Add the `flexipageRecordForm` component
3. Use the Custom Property Editor to configure:
   - Select the SObject type (sets generic type T)
   - Enter the FlexiPage developer name
   - Configure default values for new records
   - Configure excluded fields
4. The CPE automatically sets `flowContext = true`
5. Save/Cancel buttons are hidden; use Flow navigation (Next/Finish)
6. Map the `varRecord` output variable to capture the record for downstream use

**Note:** For existing Flows created before the `flowContext` fix, re-open the screen element in Flow Builder and save to ensure the property is persisted.

### Default Values Format

```
Field1__c:Value1;Field2__c:Value2;Status__c:New
```

Supports both `;` and `,` as separators. In the CPE, you can also map Flow variables to individual fields.

### Excluded Fields Format

```
CustomField__c,AnotherField__c,ThirdField__c
```

System read-only fields are auto-excluded in edit mode and do not need to be listed.

## Visibility Rules

The component evaluates FlexiPage visibility rules client-side:

**Supported Operators:**
- `EQUAL` / `NE` - Equality checks
- `GT` / `GE` / `LT` / `LE` - Numeric comparisons
- `CONTAINS` - String contains

**Boolean Logic:**
- `AND` / `OR` filters supported
- Nested conditions evaluated recursively

## Conditional Formatting

When `enableConditionalFormatting` is enabled, the component applies styles from `UiFormatSpecificationSet`:

**Text Colors:** success, error, warning, blue, purple, yellow
**Text Styles:** bold, italic, underline, line-through
**Icons:** Utility icons with color classes
**Borders:** success, error, warning borders

## Caching

FlexiPage metadata is cached in `FlexiPage_Cache__c` custom object:
- Default timeout: 60 minutes
- Transaction-level caching for repeated calls
- Manual invalidation available via `FlexiPageCacheService`

## Development

### Run Tests

```bash
# Run all Apex tests
sf apex run test --test-level RunLocalTests --wait 10

# Run specific test
sf apex run test --class-names FlexiPageToolingServiceTest --wait 10

# Run LWC Jest tests
npm run test:unit
```

### Lint and Format

```bash
npm run lint
npm run prettier
```

## License

MIT License - See LICENSE file for details
