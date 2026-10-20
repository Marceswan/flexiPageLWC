import { createElement } from "lwc";
import FlexiPageRecordForm from "c/flexipageRecordForm";
import getFlexiPageMetadata from "@salesforce/apex/FlexiPageToolingService.getFlexiPageMetadata";
import getFieldValues from "@salesforce/apex/FlexiPageToolingService.getFieldValues";
import trackFieldChangesAura from "@salesforce/apex/FieldHistoryTracker.trackFieldChangesAura";
import { updateRecord } from "lightning/uiRecordApi";

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
  "@salesforce/apex/FieldHistoryTracker.trackFieldChangesAura",
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

const RECORD_ID = "001000000000001AAA";
const config = {
  flexiPageRegions: [
    {
      type: "Region",
      itemInstances: ["Name", "Account.Name"].map((path) => ({
        fieldInstance: { fieldItem: `Record.${path}` },
      })),
    },
  ],
};
const response = {
  values: { name: "Acme", "account.name": "Parent" },
  metadata: {
    name: { label: "Name", type: "STRING", isUpdateable: true },
    "account.name": { label: "Account Name", type: "STRING" },
  },
};
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

beforeEach(() => {
  jest.spyOn(console, "log").mockImplementation(() => {});
  getFlexiPageMetadata.mockResolvedValue(config);
  trackFieldChangesAura.mockResolvedValue("Success");
  updateRecord.mockResolvedValue({ id: RECORD_ID });
});
afterEach(() => {
  document.body.innerHTML = "";
  jest.restoreAllMocks();
  jest.clearAllMocks();
});

async function editAndSave(useFieldHistory) {
  const element = createElement("c-flexi-page-record-form", {
    is: FlexiPageRecordForm,
  });
  Object.assign(element, {
    recordId: RECORD_ID,
    objectApiName: "Account",
    flexiPageName: "Account_Form",
    useFieldHistory,
  });
  document.body.appendChild(element);
  await flush();
  getFieldValues.emit(response);
  await flush();
  element.shadowRoot.querySelector("lightning-button-icon").click();
  await flush();
  element.shadowRoot.querySelector("lightning-input-field").value = "Updated";
  [...element.shadowRoot.querySelectorAll("lightning-button")]
    .find((button) => button.label === "Save")
    .click();
  await flush();
}

it("tracks only the changed fields after save when useFieldHistory is on", async () => {
  await editAndSave(true);
  expect(trackFieldChangesAura).toHaveBeenCalledWith({
    oldRecordJson: JSON.stringify({ Name: "Acme" }),
    newRecordJson: JSON.stringify({ Name: "Updated" }),
    recordId: RECORD_ID,
    objectApiName: "Account",
  });
});

it("does not track field history when useFieldHistory is off", async () => {
  await editAndSave(false);
  expect(updateRecord).toHaveBeenCalled();
  expect(trackFieldChangesAura).not.toHaveBeenCalled();
});
