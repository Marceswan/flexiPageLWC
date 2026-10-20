const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const bundles = ['flexipageRecordForm', 'flexipageRecordFormCPE'];
const codecs = bundles.map((bundle) => {
  const source = readFileSync(join(__dirname, `../force-app/main/default/lwc/${bundle}/defaultValues.js`), 'utf8');
  return import(`data:text/javascript,${encodeURIComponent(source)}`);
});

test('retains colons in legacy default values', async () => {
  for (const codec of codecs) {
    const { parseDefaultValuePairs } = await codec;
    assert.deepEqual(parseDefaultValuePairs('Website:https://example.com;Status:New'), {
      Website: 'https://example.com', Status: 'New'
    });
  }
});

test('round trips delimiters and backslashes without changing the property format', async () => {
  const values = { Notes: 'alpha,beta;gamma:delta\\end', Status: 'New' };
  for (const codec of codecs) {
    const { parseDefaultValuePairs, formatDefaultValuePairs } = await codec;
    assert.deepEqual(parseDefaultValuePairs(formatDefaultValuePairs(values)), values);
  }
});

test('preserves empty values and legacy comma separated pairs', async () => {
  for (const codec of codecs) {
    const { parseDefaultValuePairs } = await codec;
    assert.deepEqual(parseDefaultValuePairs('Name:,Stage:Open,Count:0'), {
      Name: '', Stage: 'Open', Count: '0'
    });
  }
});

test('keeps literal commas in legacy semicolon separated values', async () => {
  for (const codec of codecs) {
    const { parseDefaultValuePairs } = await codec;
    assert.deepEqual(parseDefaultValuePairs('Notes:hello,world;Status:New'), {
      Notes: 'hello,world', Status: 'New'
    });
  }
});
