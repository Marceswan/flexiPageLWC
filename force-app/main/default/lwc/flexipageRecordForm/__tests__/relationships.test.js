import { createElement } from "lwc";
import FlexiPageRecordForm from "c/flexipageRecordForm";
import getFlexiPageMetadata from "@salesforce/apex/FlexiPageToolingService.getFlexiPageMetadata";
import getFieldValues from "@salesforce/apex/FlexiPageToolingService.getFieldValues";
import { updateRecord } from "lightning/uiRecordApi";
import { parseFlexiPageJson, collectRuleFields } from "../utils";

jest.mock(
  "@salesforce/apex/FlexiPageToolingService.getFlexiPageMetadata",
  () => ({ default: jest.fn() }),
  { virtual: true },
);
jest.mock(
  "@salesforce/apex/FlexiPageToolingService.getUiFormatSpecificationSet",
  () => ({ default: jest.fn() }),
  { virtual: true },
);
jest.mock(
  "@salesforce/apex/FlexiPageToolingService.getFieldValues",
  () => {
    const { createApexTestWireAdapter } = require("@salesforce/sfdx-lwc-jest");
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true },
);

const paths = [
  "Name",
  "Account.Name",
  "Account.Parent.Name",
  "Customer__r.Balance__c",
];
const items = paths.map((path) => ({
  fieldInstance: { fieldItem: `Record.${path}` },
}));
const config = { flexiPageRegions: [{ type: "Region", itemInstances: items }] };
const response = {
  values: {
    name: "Contact",
    "account.name": "Acme",
    "account.parent.name": "Group",
    "customer__r.balance__c": 0,
  },
  metadata: {
    name: { label: "Name", type: "STRING" },
    "account.name": { label: "Account Name", type: "STRING" },
    "account.parent.name": { label: "Parent Name", type: "STRING" },
    "customer__r.balance__c": { label: "Balance", type: "CURRENCY" },
  },
};
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

beforeEach(() => {
  jest.spyOn(console, "log").mockImplementation(() => {});
  getFlexiPageMetadata.mockResolvedValue(config);
});
afterEach(() => {
  document.body.innerHTML = "";
  jest.restoreAllMocks();
  jest.clearAllMocks();
});

it("preserves standard, nested and custom relationship paths in simple and section layouts", () => {
  const simple =
    parseFlexiPageJson(config).defaultSection.columns.defaultColumn.fields;
  expect(Object.keys(simple)).toEqual(paths);
  expect(simple["Account.Name"].isReadOnly).toBe(true);
  const complex = {
    flexiPageRegions: [
      {
        type: "Region",
        itemInstances: [
          {
            componentInstance: {
              componentName: "flexipage:fieldSection",
              componentInstanceProperties: [
                { name: "columns", value: "section" },
                { name: "label", value: "Details" },
              ],
            },
          },
        ],
      },
      {
        type: "Facet",
        name: "section",
        itemInstances: [
          {
            componentInstance: {
              componentName: "flexipage:column",
              identifier: "flexipage_column1",
              componentInstanceProperties: [{ name: "body", value: "column" }],
            },
          },
        ],
      },
      { type: "Facet", name: "column", itemInstances: items },
    ],
  };
  const fields = parseFlexiPageJson(complex).section.columns.column.fields;
  expect(Object.keys(fields)).toEqual(paths);
  expect(fields["Customer__r.Balance__c"].isReadOnly).toBe(true);
});

it("collects complete relationship paths referenced only by visibility rules", () => {
  expect(
    collectRuleFields({
      criteria: [
        { leftValue: "{!Record.Account.Type}" },
        { leftValue: "{!Record.Account.Type}" },
        { leftValue: "{!Record.Customer__r.Parent__r.Status__c}" },
      ],
    }),
  ).toEqual(["Account.Type", "Customer__r.Parent__r.Status__c"]);
});

async function mount(readOnly = false) {
  const element = createElement("c-flexi-page-record-form", {
    is: FlexiPageRecordForm,
  });
  Object.assign(element, {
    recordId: "003000000000001AAA",
    objectApiName: "Contact",
    flexiPageName: "Contact_Page",
    isReadOnly: readOnly,
  });
  document.body.appendChild(element);
  await flush();
  getFieldValues.emit(response);
  await flush();
  return element;
}

it.each([true, false])(
  "renders all related fields read-only (read-only mode: %s)",
  async (readOnly) => {
    const element = await mount(readOnly);
    expect(getFieldValues.getLastConfig().fieldApiNames).toEqual(paths);
    const fields = element.shadowRoot.querySelectorAll(
      "c-related-record-field",
    );
    expect(fields).toHaveLength(3);
    expect(fields[0].fieldData.value).toBe("Acme");
    expect(fields[1].fieldData.value).toBe("Group");
    expect(fields[2].fieldData.value).toBe(0);
    expect([...fields].every((field) => !field.fieldData.isEditable)).toBe(
      true,
    );
  },
);

it("keeps related fields out of editable inputs and save payloads", async () => {
  const element = await mount();
  element.shadowRoot.querySelector("lightning-button-icon").click();
  await flush();
  const inputs = element.shadowRoot.querySelectorAll("lightning-input-field");
  expect([...inputs].map((input) => input.fieldName)).toEqual(["Name"]);
  expect(
    element.shadowRoot.querySelectorAll("c-related-record-field"),
  ).toHaveLength(3);
  inputs[0].value = "Updated";
  updateRecord.mockResolvedValue({ id: element.recordId });
  [...element.shadowRoot.querySelectorAll("lightning-button")]
    .find((button) => button.label === "Save")
    .click();
  expect(updateRecord).toHaveBeenCalledWith({
    fields: { Name: "Updated", Id: element.recordId },
  });
  await flush();
});

it("never defaults a relationship path into a new Flow record", async () => {
  const element = createElement("c-flexi-page-record-form", {
    is: FlexiPageRecordForm,
  });
  Object.assign(element, {
    objectApiName: "Contact",
    flexiPageName: "Contact_Page",
    flowContext: true,
    defaultValues: "Name:New;Account.Name:Wrong",
  });
  document.body.appendChild(element);
  await flush();
  expect(element.varRecord).toEqual({ Name: "New" });
  expect(
    [...element.shadowRoot.querySelectorAll("lightning-input-field")].map(
      (field) => field.fieldName,
    ),
  ).toEqual(["Name"]);
});

it("clears stale related values on lookup changes without resetting edits, and restores them on cancel", async () => {
  getFlexiPageMetadata.mockResolvedValue({
    flexiPageRegions: [
      {
        type: "Region",
        itemInstances: ["Name", "AccountId", "Account.Name"].map((path) => ({
          fieldInstance: { fieldItem: `Record.${path}` },
        })),
      },
    ],
  });
  const element = await mount();
  getFieldValues.emit({
    values: {
      name: "Contact",
      accountid: "001000000000001AAA",
      "account.name": "Acme",
    },
    metadata: {
      name: { label: "Name", type: "STRING" },
      accountid: { label: "Account", type: "REFERENCE" },
      "account.name": {
        label: "Account Name",
        type: "STRING",
        rootLookupField: "AccountId",
      },
    },
  });
  await flush();
  element.shadowRoot.querySelector("lightning-button-icon").click();
  await flush();
  const inputs = [
    ...element.shadowRoot.querySelectorAll("lightning-input-field"),
  ];
  const nameInput = inputs.find((input) => input.fieldName === "Name");
  nameInput.value = "Unsaved edit";
  const lookup = inputs.find((input) => input.fieldName === "AccountId");
  lookup.value = "001000000000002AAA";
  lookup.dispatchEvent(new CustomEvent("change"));
  await flush();
  expect(
    element.shadowRoot.querySelector("c-related-record-field").fieldData.value,
  ).toBeNull();
  expect(
    [...element.shadowRoot.querySelectorAll("lightning-input-field")].find(
      (input) => input.fieldName === "Name",
    ).value,
  ).toBe("Unsaved edit");
  [...element.shadowRoot.querySelectorAll("lightning-button")]
    .find((button) => button.label === "Cancel")
    .click();
  await flush();
  expect(
    element.shadowRoot.querySelector("c-related-record-field").fieldData.value,
  ).toBe("Acme");
});

it("loads and evaluates a related field used only by a visibility rule", async () => {
  getFlexiPageMetadata.mockResolvedValue({
    flexiPageRegions: [
      {
        type: "Region",
        itemInstances: [
          {
            fieldInstance: {
              fieldItem: "Record.Name",
              visibilityRule: {
                criteria: [
                  {
                    leftValue: "{!Record.Account.Type}",
                    operator: "EQUAL",
                    rightValue: "Customer",
                  },
                ],
              },
            },
          },
        ],
      },
    ],
  });
  const element = createElement("c-flexi-page-record-form", {
    is: FlexiPageRecordForm,
  });
  Object.assign(element, {
    recordId: "003000000000001AAA",
    objectApiName: "Contact",
    flexiPageName: "Contact_Page",
    enableVisibilityRules: true,
  });
  document.body.appendChild(element);
  await flush();
  expect(getFieldValues.getLastConfig().fieldApiNames).toEqual([
    "Name",
    "Account.Type",
  ]);
  getFieldValues.emit({
    values: { name: "Contact", "account.type": "Other" },
    metadata: response.metadata,
  });
  await flush();
  expect(element.shadowRoot.querySelector("lightning-button-icon")).toBeNull();
  getFieldValues.emit({
    values: { name: "Contact", "account.type": "Customer" },
    metadata: response.metadata,
  });
  await flush();
  expect(
    element.shadowRoot.querySelector("lightning-button-icon"),
  ).not.toBeNull();
});
