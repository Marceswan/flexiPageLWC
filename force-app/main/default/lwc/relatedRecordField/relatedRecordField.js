import { LightningElement, api } from "lwc";
import currency from "@salesforce/i18n/currency";

// Cross-object Dynamic Forms fields are display-only in every form mode.
export default class RelatedRecordField extends LightningElement {
  @api fieldData = {};
  currencyCode = currency;

  get hasValue() {
    return (
      this.fieldData.value !== null &&
      this.fieldData.value !== undefined &&
      this.fieldData.value !== ""
    );
  }
  get isBoolean() {
    return this.fieldData.type === "BOOLEAN";
  }
  get isReference() {
    return this.fieldData.type === "REFERENCE";
  }
  get referenceLabel() {
    return this.fieldData.referenceNameValue || this.fieldData.value;
  }
  get isDate() {
    return this.fieldData.type === "DATE";
  }
  get isDateTime() {
    return this.fieldData.type === "DATETIME";
  }
  get isNumber() {
    return ["CURRENCY", "DOUBLE", "INTEGER", "LONG", "PERCENT"].includes(
      this.fieldData.type,
    );
  }
  get numberStyle() {
    if (this.fieldData.type === "CURRENCY") return "currency";
    return this.fieldData.type === "PERCENT" ? "percent" : "decimal";
  }
  get numberValue() {
    return this.fieldData.type === "PERCENT"
      ? this.fieldData.value / 100
      : this.fieldData.value;
  }
  get isEmail() {
    return this.fieldData.type === "EMAIL";
  }
  get isPhone() {
    return this.fieldData.type === "PHONE";
  }
  get isUrl() {
    return this.fieldData.type === "URL";
  }
  get isRichText() {
    return this.fieldData.isHtmlFormatted;
  }
}
