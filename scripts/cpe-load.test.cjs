const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');

function deferred() {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
}

test('a late field response cannot replace the current object fields', async () => {
  const requests = new Map();
  const source = readFileSync(join(__dirname, '../force-app/main/default/lwc/flexipageRecordFormCPE/flexipageRecordFormCPE.js'), 'utf8')
    .replace(/^import .*;\n/gm, '')
    .replace(/@track\s+/g, '')
    .replace(/@api\s+/g, '')
    .replace('export default class ', 'class ');
  const CPE = vm.runInNewContext(`${source}\nFlexipageRecordFormCPE`, {
    LightningElement: class {},
    getObjectFields: ({ objectApiName }) => {
      const request = deferred();
      requests.set(objectApiName, request);
      return request.promise;
    },
    getFlexiPageFields: ({ developerName }) => Promise.resolve([{ fieldName: developerName }]),
    console: { log() {}, warn() {}, error() {} }
  });
  const editor = new CPE();
  editor.objectApiName = 'Account';
  editor.selectedFlexiPage = 'Name';
  const oldLoad = editor.loadFields();
  editor.objectApiName = 'Contact';
  editor.selectedFlexiPage = 'Email';
  const newLoad = editor.loadFields();
  requests.get('Contact').resolve([{ apiName: 'Email', label: 'Email', type: 'Email' }]);
  await newLoad;
  requests.get('Account').resolve([{ apiName: 'Name', label: 'Name', type: 'String' }]);
  await oldLoad;
  assert.deepEqual(Array.from(editor.fieldOptions, (field) => field.value), ['Email']);
  assert.equal(editor.isLoadingFields, false);
});
