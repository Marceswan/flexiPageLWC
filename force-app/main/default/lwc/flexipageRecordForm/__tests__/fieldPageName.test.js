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

const RECORD_ID = "a2A000000000001AAA";
const flush = () => new Promise((resolve) => setTimeout(resolve, 0));

beforeEach(() => {
  jest.spyOn(console, "log").mockImplementation(() => {});
  getFlexiPageMetadata.mockResolvedValue({ flexiPageRegions: [] });
});
afterEach(() => {
  document.body.innerHTML = "";
  jest.restoreAllMocks();
  jest.clearAllMocks();
});

async function mount(props) {
  const element = createElement("c-flexi-page-record-form", {
    is: FlexiPageRecordForm,
  });
  Object.assign(element, {
    recordId: RECORD_ID,
    objectApiName: "Opportunity_Readiness__c",
    ...props,
  });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

it("loads the FlexiPage named by the fieldPageName record field", async () => {
  getFieldValues.mockResolvedValue({
    values: { form_name__c: "Opp_Readiness_Form_Collect" },
  });
  await mount({ fieldPageName: "Form_Name__c" });
  expect(getFieldValues).toHaveBeenCalledWith({
    recordId: RECORD_ID,
    objectApiName: "Opportunity_Readiness__c",
    fieldApiNames: ["Form_Name__c"],
  });
  expect(getFlexiPageMetadata).toHaveBeenCalledWith({
    developerName: "Opp_Readiness_Form_Collect",
  });
});

it("falls back to flexiPageName when the fieldPageName field is empty", async () => {
  getFieldValues.mockResolvedValue({ values: { form_name__c: null } });
  await mount({
    fieldPageName: "Form_Name__c",
    flexiPageName: "Default_Form",
  });
  expect(getFlexiPageMetadata).toHaveBeenCalledWith({
    developerName: "Default_Form",
  });
});

it("uses flexiPageName directly when fieldPageName is not set", async () => {
  await mount({ flexiPageName: "Default_Form" });
  expect(getFieldValues).not.toHaveBeenCalled();
  expect(getFlexiPageMetadata).toHaveBeenCalledWith({
    developerName: "Default_Form",
  });
});
