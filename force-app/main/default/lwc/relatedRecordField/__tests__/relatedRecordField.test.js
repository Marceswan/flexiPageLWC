import { createElement } from "lwc";
import RelatedRecordField from "c/relatedRecordField";

afterEach(() => {
  document.body.innerHTML = "";
});
function mount(type, value) {
  const element = createElement("c-related-record-field", {
    is: RelatedRecordField,
  });
  element.fieldData = { label: "Related field", type, value, scale: 2 };
  document.body.appendChild(element);
  return element;
}
it("renders zero as a number instead of an empty value", () => {
  const element = mount("CURRENCY", 0);
  expect(
    element.shadowRoot.querySelector("lightning-formatted-number").value,
  ).toBe(0);
});
it("renders false as an unchecked, disabled checkbox", () => {
  const element = mount("BOOLEAN", false);
  const checkbox = element.shadowRoot.querySelector("lightning-input");
  expect(checkbox.checked).toBe(false);
  expect(checkbox.disabled).toBe(true);
});
it("renders an empty relationship without an input or undefined text", () => {
  const element = mount("STRING", null);
  expect(
    element.shadowRoot.querySelector("lightning-formatted-text"),
  ).toBeNull();
  expect(element.shadowRoot.textContent).not.toContain("undefined");
});
it("formats date-only values without timezone shifts", () => {
  const element = mount("DATE", "2026-10-19");
  expect(
    element.shadowRoot.querySelector("lightning-formatted-date-time").timeZone,
  ).toBe("UTC");
});
it("converts Salesforce percentages for the percent formatter", () => {
  const element = mount("PERCENT", 25);
  expect(
    element.shadowRoot.querySelector("lightning-formatted-number").value,
  ).toBe(0.25);
});
