export function parseFlexiPageJson(flexiPageJson) {
  const sections = {}; // Object to store sections and their fields

  console.log("Starting to parse flexiPageJson:", flexiPageJson);

  // Validate that flexiPageRegions exists
  if (
    !flexiPageJson ||
    !flexiPageJson.flexiPageRegions ||
    !Array.isArray(flexiPageJson.flexiPageRegions)
  ) {
    console.error(
      "Invalid FlexiPage data - missing flexiPageRegions:",
      flexiPageJson
    );
    return sections;
  }

  // Check if this is a simple region-based layout (no sections/columns)
  const hasSimpleLayout = flexiPageJson.flexiPageRegions.some(
    (region) =>
      region.type === "Region" &&
      region.itemInstances &&
      region.itemInstances.some((item) => item.fieldInstance)
  );

  if (hasSimpleLayout) {
    console.log("Detected simple layout - processing direct field instances");

    // For simple layouts, create a default section
    const defaultSectionId = "defaultSection";
    sections[defaultSectionId] = {
      label: "Information",
      columns: {
        defaultColumn: {
          side: "left",
          fields: {}
        }
      }
    };

    // Process all regions
    flexiPageJson.flexiPageRegions.forEach((region) => {
      if (region.type === "Region" && region.itemInstances) {
        region.itemInstances.forEach((item, index) => {
          if (item.fieldInstance) {
            const fieldApiName = item.fieldInstance.fieldItem.replace(
              "Record.",
              ""
            );
            sections[defaultSectionId].columns.defaultColumn.fields[
              fieldApiName
            ] = {
              value:
                item.fieldInstance?.fieldInstanceProperties?.find(
                  (prop) => prop.name === "value"
                )?.value || "",
              isVisible: true,
              isRequired: false,
              isReadOnly: false,
              visibilityRule: null,
              conditionalFormatRuleset: null,
              order: index
            };
            console.log(`Added field: ${fieldApiName}`);
          }
        });
      }
    });

    console.log("Parsed Sections:", JSON.stringify(sections, null, 2));
    return sections;
  }

  // Original parsing logic for complex layouts
  console.log("Processing complex layout with sections and columns");

  // First pass: Collect sections and their labels
  flexiPageJson.flexiPageRegions.forEach((region) => {
    region.itemInstances.forEach((itemInstance) => {
      if (
        itemInstance.componentInstance &&
        itemInstance.componentInstance.componentName ===
          "flexipage:fieldSection"
      ) {
        const sectionFacetId =
          itemInstance.componentInstance.componentInstanceProperties.find(
            (prop) => prop.name === "columns"
          ).value;
        const sectionLabel =
          itemInstance.componentInstance.componentInstanceProperties.find(
            (prop) => prop.name === "label"
          ).value || "Unnamed Section";

        if (!sections[sectionFacetId]) {
          sections[sectionFacetId] = { label: sectionLabel, columns: {} };
        }
      }
    });
  });

  // Second pass: Collect columns and assign to sections
  flexiPageJson.flexiPageRegions.forEach((region) => {
    if (region.type === "Facet") {
      region.itemInstances.forEach((itemInstance) => {
        if (
          itemInstance.componentInstance &&
          itemInstance.componentInstance.componentName === "flexipage:column"
        ) {
          const columnFacetId =
            itemInstance.componentInstance.componentInstanceProperties.find(
              (prop) => prop.name === "body"
            ).value;
          const sectionFacetId = region.name;
          const side =
            parseInt(
              itemInstance.componentInstance.identifier.replace(
                "flexipage_column",
                ""
              ),
              10
            ) %
              2 ===
            0
              ? "right"
              : "left";

          if (sections[sectionFacetId]) {
            sections[sectionFacetId].columns[columnFacetId] = {
              side: side,
              fields: {}
            };
          }
        }
      });
    }
  });

  // Third pass: Assign fields and spacers to columns
  flexiPageJson.flexiPageRegions.forEach((region) => {
    if (region.type === "Facet") {
      region.itemInstances.forEach((itemInstance, itemIndex) => {
        const columnFacetId = region.name;
        const sectionFacetId = Object.keys(sections).find((sectionId) =>
          Object.keys(sections[sectionId].columns).includes(columnFacetId)
        );

        if (sectionFacetId && sections[sectionFacetId].columns[columnFacetId]) {
          // Handle field instances
          if (itemInstance.fieldInstance) {
            const fieldApiName = itemInstance.fieldInstance.fieldItem.replace(
              "Record.",
              ""
            );
            const fieldValue =
              itemInstance.fieldInstance?.fieldInstanceProperties?.find(
                (prop) => prop.name === "value"
              )?.value || "";
            const isVisible = true; // Initially set all fields to not visible
            const uiBehavior =
              itemInstance.fieldInstance?.fieldInstanceProperties?.find(
                (prop) => prop.name === "uiBehavior"
              )?.value;
            const isRequired = uiBehavior === "required";
            const isReadOnly = uiBehavior === "readonly";
            const visibilityRule = itemInstance.fieldInstance?.visibilityRule;
            // Extract conditionalFormatRuleset from fieldInstanceProperties array
            const conditionalFormatRuleset =
              itemInstance.fieldInstance?.fieldInstanceProperties?.find(
                (prop) => prop.name === "conditionalFormatRuleset"
              )?.value;

            console.log(
              `Field: ${fieldApiName}, Value: ${fieldValue}, isVisible: ${isVisible}, isRequired: ${isRequired}, isReadOnly: ${isReadOnly}, visibilityRule: ${JSON.stringify(visibilityRule)}`
            );
            if (conditionalFormatRuleset) {
              console.log(
                `Conditional Format Ruleset for ${fieldApiName}:`,
                JSON.stringify(conditionalFormatRuleset)
              );
            }

            sections[sectionFacetId].columns[columnFacetId].fields[
              fieldApiName
            ] = {
              value: fieldValue,
              isVisible: isVisible,
              isRequired: isRequired,
              isReadOnly: isReadOnly,
              visibilityRule: visibilityRule, // Add visibility rule to the field
              conditionalFormatRuleset: conditionalFormatRuleset, // Add conditional formatting rules
              order: itemIndex // Add order to maintain position
            };
          }
          // Handle blankSpace components
          else if (
            itemInstance.componentInstance &&
            itemInstance.componentInstance.componentName ===
              "flexipage:blankSpace"
          ) {
            const spacerId =
              itemInstance.componentInstance.identifier ||
              `spacer_${itemIndex}`;
            console.log(`Blank Space: ${spacerId} at position ${itemIndex}`);

            sections[sectionFacetId].columns[columnFacetId].fields[spacerId] = {
              isBlankSpace: true,
              isVisible: true,
              order: itemIndex // Add order to maintain position
            };
          }
        }
      });
    }
  });

  // Remove sections with no fields
  Object.keys(sections).forEach((sectionKey) => {
    const section = sections[sectionKey];
    const hasFields = Object.values(section.columns).some(
      (column) => Object.keys(column.fields).length > 0
    );
    if (!hasFields) {
      delete sections[sectionKey];
    }
  });

  console.log("Parsed Sections:", JSON.stringify(sections, null, 2));

  return sections;
}