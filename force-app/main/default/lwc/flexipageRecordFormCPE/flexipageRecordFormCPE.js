import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import getFlexiPageFields from "@salesforce/apex/FlexiPageMetadataService.getFlexiPageFields";
import getObjectFields from "@salesforce/apex/FlexiPageMetadataService.getObjectFields";
import getAllSObjects from "@salesforce/apex/FlexiPageMetadataService.getAllSObjects";
export default class FlexipageRecordFormCPE extends LightningElement {
  // Flow Builder interfaces
  _builderContext = {};
  _inputVariables = [];
  _genericTypeMappings = [];
  _automaticOutputVariables = [];

  // UI State
  // Removed isLoadingFlexiPages since we're using direct text input
  @track isLoadingFields = false;
  @track isLoadingObjects = false;
  @track objectOptions = [];
  // Removed flexiPageOptions since we're using direct text input
  @track fieldOptions = [];
  @track showAdvancedSettings = false;
  @track showDefaultValuesModal = false;
  @track showExcludedFieldsModal = false;
  @track defaultValueFields = [];
  @track tempExcludedFields = [];
  @track showIndividualFields = false;
  @track selectedRecordVariable = "";
  @track flexiPageFields = []; // Fields from the selected FlexiPage
  @track searchTerm = ""; // Search term for filtering fields

  // Configuration values
  objectApiName;
  selectedFlexiPage;
  cardTitle;
  showIcon = false;
  recordId;
  isReadOnly = false;
  excludedFields = [];
  defaultFieldValues = {};
  saveLabel = "Save";
  cancelLabel = "Cancel";

  // Temporary storage for default values modal
  tempDefaultValues = {};

  // Connected callback to load sObjects when component is initialized
  connectedCallback() {
    this.loadAllSObjects();
    // Ensure flowContext is always set to true in Flow Builder
    this.dispatchConfigurationChange("flowContext", true, "Boolean");
  }

  // Getters and setters for Flow Builder interfaces
  @api
  get builderContext() {
    return this._builderContext;
  }
  set builderContext(context) {
    this._builderContext = context || {};
  }

  @api
  get inputVariables() {
    return this._inputVariables;
  }
  set inputVariables(variables) {
    this._inputVariables = variables || [];
    this.initializeValues();
  }

  @api
  get genericTypeMappings() {
    return this._genericTypeMappings;
  }
  set genericTypeMappings(mappings) {
    this._genericTypeMappings = mappings || [];
    this.handleGenericTypeMapping();
  }

  @api
  get automaticOutputVariables() {
    return this._automaticOutputVariables;
  }
  set automaticOutputVariables(variables) {
    this._automaticOutputVariables = variables || [];
  }

  // Computed properties
  get advancedSettingsIcon() {
    return this.showAdvancedSettings
      ? "utility:chevrondown"
      : "utility:chevronright";
  }

  get isFlexiPageDisabled() {
    return !this.objectApiName;
  }

  get excludedFieldsCount() {
    return this.excludedFields.length;
  }

  get filteredDefaultValueFields() {
    if (!this.searchTerm) {
      return this.defaultValueFields;
    }
    const searchLower = this.searchTerm.toLowerCase();
    return this.defaultValueFields.filter(
      (field) =>
        field.label.toLowerCase().includes(searchLower) ||
        field.value.toLowerCase().includes(searchLower)
    );
  }

  get individualFieldsIcon() {
    return this.showIndividualFields
      ? "utility:chevrondown"
      : "utility:chevronright";
  }

  get hideIndividualFields() {
    return !this.showIndividualFields;
  }

  get individualFieldsSectionClass() {
    return this.showIndividualFields
      ? "slds-expandable-section slds-is-open"
      : "slds-expandable-section";
  }

  // Initialize values from existing configuration
  initializeValues() {
    if (!this._inputVariables || !Array.isArray(this._inputVariables)) {
      return;
    }

    let pendingFieldLoad = null;
    let pendingExcludedFields = null;
    let pendingDefaultValues = null;

    // Check for generic type mapping first
    let hasGenericMapping = false;
    if (this._genericTypeMappings && this._genericTypeMappings.length > 0) {
      const mapping = this._genericTypeMappings.find((m) => m.typeName === "T");
      if (mapping && mapping.typeValue) {
        hasGenericMapping = true;
        if (!this.objectApiName) {
          this.objectApiName = mapping.typeValue;
        }
      }
    }

    this._inputVariables.forEach((variable) => {
      switch (variable.name) {
        case "objectApiName":
          // Only set if we don't have a generic mapping or if the value is explicitly set
          if (!hasGenericMapping || variable.value) {
            this.objectApiName = variable.value;
          }
          break;
        case "flexiPageName":
          pendingFieldLoad = variable.value;
          break;
        case "cardTitle":
          this.cardTitle = variable.value;
          break;
        case "showIcon":
          this.showIcon = variable.value === true || variable.value === "true";
          break;
        case "recordId":
          this.recordId = variable.value;
          break;
        case "isReadOnly":
          this.isReadOnly =
            variable.value === true || variable.value === "true";
          break;
        case "excludedFields":
          pendingExcludedFields = variable.value;
          break;
        case "defaultValues":
          pendingDefaultValues = variable.value;
          break;
        case "saveLabel":
          this.saveLabel = variable.value || "Save";
          break;
        case "cancelLabel":
          this.cancelLabel = variable.value || "Cancel";
          break;
        default:
          // Ignore unknown variables
          break;
      }
    });

    // Load dependent data
    if (this.objectApiName) {
      // If we have a pending field load (from saved configuration), load the fields
      if (pendingFieldLoad) {
        this.selectedFlexiPage = pendingFieldLoad;
        this.loadFields().then(() => {
          if (pendingExcludedFields) {
            this.excludedFields = pendingExcludedFields
              .split(",")
              .map((f) => f.trim());
          }
          if (pendingDefaultValues) {
            this.parseDefaultValues(pendingDefaultValues);
          }
        });
      }
    }
  }

  // Dispatch configuration changes to Flow Builder
  dispatchConfigurationChange(name, value, dataType = "String") {
    const valueChangeEvent = new CustomEvent(
      "configuration_editor_input_value_changed",
      {
        bubbles: true,
        cancelable: false,
        composed: true,
        detail: {
          name: name,
          newValue: value,
          newValueDataType: dataType
        }
      }
    );
    this.dispatchEvent(valueChangeEvent);
  }

  // Event handlers
  handleObjectChange(event) {
    this.objectApiName = event.detail.value;
    this.dispatchConfigurationChange("objectApiName", this.objectApiName);

    // Reset dependent selections
    this.selectedFlexiPage = null;
    this.excludedFields = [];
    this.defaultFieldValues = {};
    this.dispatchConfigurationChange("flexiPageName", null);
    this.dispatchConfigurationChange("excludedFields", "");
    this.dispatchConfigurationChange("defaultValues", "");

    // Dispatch generic type mapping for Flow
    this.dispatchEvent(
      new CustomEvent("configuration_editor_generic_type_mapping_changed", {
        bubbles: true,
        composed: true,
        detail: {
          typeName: "T",
          typeValue: this.objectApiName
        }
      })
    );

    // No longer loading FlexiPages since user will type the developer name directly
  }

  handleFlexiPageChange(event) {
    this.selectedFlexiPage = event.detail.value;
    this.dispatchConfigurationChange("flexiPageName", this.selectedFlexiPage);

    // Load fields when FlexiPage is selected
    this.loadFields();
  }

  handleCardTitleChange(event) {
    this.cardTitle = event.detail.value;
    this.dispatchConfigurationChange("cardTitle", this.cardTitle);
  }

  handleShowIconChange(event) {
    this.showIcon = event.detail.checked;
    this.dispatchConfigurationChange("showIcon", this.showIcon, "Boolean");
  }

  handleRecordIdChange(event) {
    this.recordId = event.detail.newValue;
    this.dispatchConfigurationChange("recordId", this.recordId);
  }

  handleReadOnlyChange(event) {
    this.isReadOnly = event.detail.checked;
    this.dispatchConfigurationChange("isReadOnly", this.isReadOnly, "Boolean");
  }

  handleSaveLabelChange(event) {
    this.saveLabel = event.detail.value || "Save";
    this.dispatchConfigurationChange("saveLabel", this.saveLabel);
  }

  handleCancelLabelChange(event) {
    this.cancelLabel = event.detail.value || "Cancel";
    this.dispatchConfigurationChange("cancelLabel", this.cancelLabel);
  }

  toggleAdvancedSettings() {
    this.showAdvancedSettings = !this.showAdvancedSettings;

    // Load fields if not already loaded and FlexiPage is selected
    if (
      this.showAdvancedSettings &&
      this.fieldOptions.length === 0 &&
      this.selectedFlexiPage
    ) {
      this.loadFields();
    }
  }

  // Data loading methods
  // Removed loadFlexiPages method since we're using direct text input

  async loadFields() {
    if (!this.objectApiName || !this.selectedFlexiPage) {
      this.fieldOptions = [];
      this.defaultValueFields = [];
      return;
    }

    this.isLoadingFields = true;
    try {
      // First, get all object fields
      console.log("=== STARTING FIELD LOAD ===");
      console.log("Loading fields for object:", this.objectApiName);
      const allObjectFields = await getObjectFields({
        objectApiName: this.objectApiName
      });
      console.log(
        "All object fields count:",
        allObjectFields ? allObjectFields.length : 0
      );
      console.log(
        "All object fields:",
        JSON.stringify(allObjectFields, null, 2)
      );

      // Then, get fields from the FlexiPage
      console.log("Loading FlexiPage fields for:", this.selectedFlexiPage);
      let flexiPageFieldInfo = [];
      try {
        flexiPageFieldInfo = await getFlexiPageFields({
          developerName: this.selectedFlexiPage
        });
        console.log(
          "FlexiPage field info count:",
          flexiPageFieldInfo ? flexiPageFieldInfo.length : 0
        );
        console.log(
          "FlexiPage field info:",
          JSON.stringify(flexiPageFieldInfo, null, 2)
        );
      } catch (flexiPageError) {
        console.warn(
          "Unable to load FlexiPage fields, using all object fields as fallback:",
          flexiPageError
        );
        // Continue with empty flexiPageFieldInfo - will use all object fields
      }

      // Check if flexiPageFieldInfo is valid
      if (!flexiPageFieldInfo || !Array.isArray(flexiPageFieldInfo)) {
        console.warn(
          "Invalid or empty FlexiPage field info, using all object fields"
        );
        flexiPageFieldInfo = [];
      }

      // Extract field names from FlexiPage (convert to lowercase for comparison)
      const flexiPageFieldNames = new Set(
        flexiPageFieldInfo.map((info) => info.fieldName.toLowerCase())
      );
      console.log("FlexiPage field names set size:", flexiPageFieldNames.size);
      console.log("FlexiPage field names:", Array.from(flexiPageFieldNames));
      this.flexiPageFields = flexiPageFieldInfo;

      // If no fields found on FlexiPage, use all object fields as fallback
      let fieldsOnFlexiPage;
      if (flexiPageFieldNames.size === 0) {
        console.log(
          "No fields found on FlexiPage, using all object fields as fallback"
        );
        fieldsOnFlexiPage = allObjectFields;
      } else {
        // Filter to only include fields that are on the FlexiPage
        fieldsOnFlexiPage = allObjectFields.filter((field) => {
          const isIncluded = flexiPageFieldNames.has(
            field.apiName.toLowerCase()
          );
          if (!isIncluded) {
            console.log(`Field ${field.apiName} not found in FlexiPage fields`);
          }
          return isIncluded;
        });
      }
      console.log(
        "Fields on FlexiPage count:",
        fieldsOnFlexiPage ? fieldsOnFlexiPage.length : 0
      );
      console.log(
        "Fields on FlexiPage:",
        JSON.stringify(fieldsOnFlexiPage, null, 2)
      );

      // Filter out system fields that shouldn't be excluded
      const userEditableFields = fieldsOnFlexiPage.filter(
        (field) =>
          ![
            "Id",
            "CreatedDate",
            "CreatedById",
            "LastModifiedDate",
            "LastModifiedById",
            "SystemModstamp"
          ].includes(field.apiName)
      );
      console.log(
        "User editable fields count:",
        userEditableFields ? userEditableFields.length : 0
      );
      console.log(
        "User editable fields:",
        JSON.stringify(userEditableFields, null, 2)
      );

      this.fieldOptions = userEditableFields.map((field) => ({
        label: field.label,
        value: field.apiName
      }));
      console.log("Final field options count:", this.fieldOptions.length);
      console.log(
        "Field options for modal:",
        JSON.stringify(this.fieldOptions, null, 2)
      );

      // Also prepare fields for default values
      this.defaultValueFields = userEditableFields.map((field) => ({
        label: field.label,
        value: field.apiName,
        type: field.type,
        defaultValue: this.defaultFieldValues[field.apiName] || "",
        selectedVariable: this.defaultFieldValues[field.apiName] || ""
      }));

      // Remove any excluded fields that are no longer on the FlexiPage
      const validFieldNames = new Set(userEditableFields.map((f) => f.apiName));
      this.excludedFields = this.excludedFields.filter((field) =>
        validFieldNames.has(field)
      );

      console.log("=== FIELD LOAD COMPLETE ===");
    } catch (error) {
      console.error("Error loading fields:", error);
      console.error("Error details:", error);
      this.showError("Unable to load fields for the selected object");
    } finally {
      this.isLoadingFields = false;
    }
  }

  // Default values modal handlers
  openDefaultValuesModal() {
    // Check if we have a FlexiPage selected
    if (!this.selectedFlexiPage) {
      this.showError("Please select a FlexiPage layout first");
      return;
    }

    this.showDefaultValuesModal = true;
    // Copy current values to temp storage
    this.tempDefaultValues = { ...this.defaultFieldValues };

    // Load fields if not already loaded
    if (this.defaultValueFields.length === 0 && this.selectedFlexiPage) {
      this.loadFields().then(() => {
        // Update default value fields with current values after loading
        this.updateDefaultValueFields();
      });
    } else {
      // Update default value fields with current values
      this.updateDefaultValueFields();
    }

    // Start with accordion expanded
    this.showIndividualFields = true;
  }

  updateDefaultValueFields() {
    // Update default value fields with current values from tempDefaultValues
    this.defaultValueFields = this.defaultValueFields.map((field) => {
      const currentValue =
        this.tempDefaultValues[field.value] || field.defaultValue || "";
      return {
        ...field,
        defaultValue: currentValue,
        selectedVariable: currentValue // For c-fsc_flow-combobox
      };
    });
  }

  toggleIndividualFields() {
    this.showIndividualFields = !this.showIndividualFields;
  }

  handleRecordVariableChange(event) {
    this.selectedRecordVariable = event.detail.newValue;

    if (this.selectedRecordVariable) {
      // When a record variable is selected, populate all fields with the variable reference
      this.defaultValueFields = this.defaultValueFields.map((field) => {
        // In CPE, we store the variable path directly without {!} syntax
        const variablePath = `${this.selectedRecordVariable}.${field.value}`;
        this.tempDefaultValues[field.value] = variablePath;
        return {
          ...field,
          defaultValue: variablePath,
          selectedVariable: variablePath
        };
      });

      // Expand the accordion to show the populated fields
      this.showIndividualFields = true;
    } else {
      // Clear all fields when empty value is selected
      this.defaultValueFields = this.defaultValueFields.map((field) => {
        delete this.tempDefaultValues[field.value];
        return {
          ...field,
          defaultValue: "",
          selectedVariable: ""
        };
      });
    }
  }

  closeDefaultValuesModal() {
    this.showDefaultValuesModal = false;
    // Reset temp values
    this.tempDefaultValues = {};
    // Reset search term
    this.searchTerm = "";
  }

  handleSearch(event) {
    this.searchTerm = event.target.value;
  }

  handleDefaultValueChange(event) {
    const fieldName = event.target.dataset.field;
    const value = event.detail.value;

    if (value) {
      this.tempDefaultValues[fieldName] = value;
      // Update the field's defaultValue in the array
      this.defaultValueFields = this.defaultValueFields.map((field) => {
        if (field.value === fieldName) {
          return { ...field, defaultValue: value, selectedVariable: "" };
        }
        return field;
      });
    } else {
      delete this.tempDefaultValues[fieldName];
      // Clear the field's defaultValue
      this.defaultValueFields = this.defaultValueFields.map((field) => {
        if (field.value === fieldName) {
          return { ...field, defaultValue: "", selectedVariable: "" };
        }
        return field;
      });
    }
  }

  handleFieldVariableChange(event) {
    const fieldName = event.target.dataset.field;
    const selectedVariable = event.detail.newValue;

    if (selectedVariable) {
      // Set the field value to just the variable name (no {!} syntax)
      this.tempDefaultValues[fieldName] = selectedVariable;

      // Update the field in the array
      this.defaultValueFields = this.defaultValueFields.map((field) => {
        if (field.value === fieldName) {
          return {
            ...field,
            defaultValue: selectedVariable,
            selectedVariable: selectedVariable
          };
        }
        return field;
      });
    } else {
      // Clear the value when empty
      delete this.tempDefaultValues[fieldName];
      this.defaultValueFields = this.defaultValueFields.map((field) => {
        if (field.value === fieldName) {
          return { ...field, defaultValue: "", selectedVariable: "" };
        }
        return field;
      });
    }
  }

  saveDefaultValues() {
    this.defaultFieldValues = { ...this.tempDefaultValues };
    const defaultValuesString = this.formatDefaultValuesString();
    this.dispatchConfigurationChange("defaultValues", defaultValuesString);
    this.closeDefaultValuesModal();
  }

  // Excluded fields modal handlers
  openExcludedFieldsModal() {
    // Check if we have a FlexiPage selected
    if (!this.selectedFlexiPage) {
      this.showError("Please select a FlexiPage layout first");
      return;
    }

    this.showExcludedFieldsModal = true;
    // Copy current excluded fields to temp array
    this.tempExcludedFields = [...this.excludedFields];

    // Load fields if not already loaded
    if (this.fieldOptions.length === 0) {
      this.loadFields();
    }
  }

  closeExcludedFieldsModal() {
    this.showExcludedFieldsModal = false;
    // Reset temp values
    this.tempExcludedFields = [];
  }

  handleTempExcludedFieldsChange(event) {
    this.tempExcludedFields = event.detail.value;
  }

  saveExcludedFields() {
    this.excludedFields = [...this.tempExcludedFields];
    const excludedFieldsString = this.excludedFields.join(",");
    this.dispatchConfigurationChange("excludedFields", excludedFieldsString);
    this.closeExcludedFieldsModal();
  }

  // Helper methods
  parseDefaultValues(defaultValuesString) {
    if (!defaultValuesString) {
      this.defaultFieldValues = {};
      return;
    }

    const values = {};
    // Support both comma and semicolon separators
    const pairs = defaultValuesString.split(/[,;]/);

    pairs.forEach((pair) => {
      const [field, value] = pair.split(":").map((s) => s.trim());
      if (field && value) {
        // Store the value directly - no {!} syntax in CPEs
        // Flow will resolve variable references automatically
        values[field] = value;
      }
    });

    this.defaultFieldValues = values;
  }

  formatDefaultValuesString() {
    const pairs = Object.entries(this.defaultFieldValues)
      .filter(([, value]) => value)
      .map(([field, value]) => {
        // Format as field:value - Flow handles variable resolution
        // No {!} syntax needed in CPEs
        return `${field}:${value}`;
      });

    return pairs.join(",");
  }

  handleGenericTypeMapping() {
    // Handle generic type mapping if needed
    if (this._genericTypeMappings && this._genericTypeMappings.length > 0) {
      const mapping = this._genericTypeMappings.find((m) => m.typeName === "T");
      if (mapping && mapping.typeValue) {
        this.objectApiName = mapping.typeValue;
        // Dispatch configuration change to ensure it's saved
        this.dispatchConfigurationChange("objectApiName", this.objectApiName);
      }
    }
  }

  // Load all available sObjects
  async loadAllSObjects() {
    this.isLoadingObjects = true;
    try {
      const sObjects = await getAllSObjects();
      this.objectOptions = sObjects;

      // If we have a generic type mapping, ensure it's selected
      if (this._genericTypeMappings && this._genericTypeMappings.length > 0) {
        const mapping = this._genericTypeMappings.find(
          (m) => m.typeName === "T"
        );
        if (mapping && mapping.typeValue && !this.objectApiName) {
          this.objectApiName = mapping.typeValue;
        }
      }
    } catch (error) {
      console.error("Error loading sObjects:", error);
      this.showError("Unable to load objects");
    } finally {
      this.isLoadingObjects = false;
    }
  }

  showError(message) {
    // Log error to console
    console.error(message);

    // Show toast notification if available
    try {
      this.dispatchEvent(
        new ShowToastEvent({
          title: "Error",
          message: message,
          variant: "error"
        })
      );
    } catch {
      // If toast is not available (e.g., in Flow Builder), use custom event
      this.dispatchEvent(
        new CustomEvent("configuration_editor_error", {
          bubbles: true,
          composed: true,
          detail: { message }
        })
      );
    }
  }

  // Validation method for Flow Builder
  @api
  validate() {
    const errors = [];

    // Validate required fields
    if (!this.objectApiName) {
      errors.push({
        key: "OBJECT_REQUIRED",
        errorString: "Please select an object"
      });
    }

    if (!this.selectedFlexiPage) {
      errors.push({
        key: "FLEXIPAGE_REQUIRED",
        errorString: "Please select a FlexiPage layout"
      });
    }

    // Validate default values format
    if (
      this.defaultFieldValues &&
      Object.keys(this.defaultFieldValues).length > 0
    ) {
      try {
        this.formatDefaultValuesString();
      } catch {
        errors.push({
          key: "INVALID_DEFAULT_VALUES",
          errorString: "Invalid default values format"
        });
      }
    }

    return errors;
  }
}