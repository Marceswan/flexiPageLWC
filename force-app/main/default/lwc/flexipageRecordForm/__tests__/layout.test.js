import { createElement } from "lwc";
import FlexiPageRecordForm from "c/flexipageRecordForm";
import getFlexiPageMetadata from "@salesforce/apex/FlexiPageToolingService.getFlexiPageMetadata";
import getFieldValues from "@salesforce/apex/FlexiPageToolingService.getFieldValues";

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

const config = {
  flexiPageRegions: [
    {
      type: "Region",
      itemInstances: ["Name", "Formula__c", "Hidden__c", "Phone"].map(
        (path) => ({ fieldInstance: { fieldItem: `Record.${path}` } }),
      ),
    },
  ],
};
// Hidden__c has no metadata: getFieldValues omits fields the user cannot read.
const response = {
  values: { name: "Acme", formula__c: "Calculated", phone: "555-0100" },
  metadata: {
    name: { label: "Name", type: "STRING", isUpdateable: true },
    formula__c: { label: "Formula", type: "STRING", isUpdateable: false },
    phone: {
      label: "Phone",
      type: "PHONE",
      isUpdateable: true,
      inlineHelpText: "Main office line",
    },
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

async function mount(readOnly) {
  const element = createElement("c-flexi-page-record-form", {
    is: FlexiPageRecordForm,
  });
  Object.assign(element, {
    recordId: "001000000000001AAA",
    objectApiName: "Account",
    flexiPageName: "Account_Form",
    isReadOnly: readOnly,
  });
  document.body.appendChild(element);
  await flush();
  getFieldValues.emit(response);
  await flush();
  return element;
}

const labels = (element) =>
  [
    ...element.shadowRoot.querySelectorAll(
      ".slds-form-element_readonly .slds-form-element__label",
    ),
  ].map((label) => label.textContent.trim());

it.each([true, false])(
  "hides fields the user cannot read and shows help text (read-only mode: %s)",
  async (readOnly) => {
    const element = await mount(readOnly);
    expect(labels(element)).toEqual(["Name", "Formula", "Phone"]);
    const helpText = element.shadowRoot.querySelectorAll("lightning-helptext");
    expect(helpText).toHaveLength(1);
    expect(helpText[0].content).toBe("Main office line");
    expect(element.shadowRoot.querySelector("lightning-output-field")).toBe(
      null,
    );
  },
);

it("shows the inline edit pencil in the value row of updateable fields only", async () => {
  const element = await mount(false);
  const rows = [
    ...element.shadowRoot.querySelectorAll(".slds-form-element_readonly"),
  ];
  const pencilFor = (label) =>
    rows
      .find(
        (row) =>
          row.querySelector(".slds-form-element__label").textContent.trim() ===
          label,
      )
      .querySelector(".slds-form-element__static lightning-button-icon");
  expect(pencilFor("Name")).not.toBeNull();
  expect(pencilFor("Phone")).not.toBeNull();
  expect(pencilFor("Formula")).toBeNull();
});

it("formats dates like a standard record page and shows picklist labels", async () => {
  getFlexiPageMetadata.mockResolvedValue({
    flexiPageRegions: [
      {
        type: "Region",
        itemInstances: ["Start__c", "Status__c"].map((path) => ({
          fieldInstance: { fieldItem: `Record.${path}` },
        })),
      },
    ],
  });
  const element = createElement("c-flexi-page-record-form", {
    is: FlexiPageRecordForm,
  });
  Object.assign(element, {
    recordId: "001000000000001AAA",
    objectApiName: "Account",
    flexiPageName: "Account_Form",
  });
  document.body.appendChild(element);
  await flush();
  getFieldValues.emit({
    values: { start__c: "2026-07-27", status__c: "NA" },
    metadata: {
      start__c: { label: "Start", type: "DATE", isUpdateable: true },
      status__c: {
        label: "Status",
        type: "PICKLIST",
        isUpdateable: true,
        displayValue: "N/A",
      },
    },
  });
  await flush();

  const date = element.shadowRoot.querySelector(
    "lightning-formatted-date-time",
  );
  expect(date.value).toBe("2026-07-27");
  expect(date.timeZone).toBe("UTC");
  const text = element.shadowRoot.querySelector("lightning-formatted-text");
  expect(text.value).toBe("N/A");
});
