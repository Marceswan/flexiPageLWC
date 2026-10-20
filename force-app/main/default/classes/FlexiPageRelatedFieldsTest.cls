/** Regression coverage for lookup paths returned to the dynamic record form. */
@IsTest
private with sharing class FlexiPageRelatedFieldsTest {
  @TestSetup
  static void setupRecords() {
    FlexiPageTestDataFactory.createRelatedFieldRecords();
  }

  @IsTest
  static void readsStandardAndNestedRelationships() {
    Contact contact = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Related Fields'
    ];
    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      contact.Id,
      'Contact',
      new List<String>{
        'LastName',
        'Record.Account.Name',
        'account.parent.name',
        'Account.AnnualRevenue'
      }
    );
    Integer queries = Limits.getQueries();
    Test.stopTest();
    Map<String, Object> values = (Map<String, Object>) result.get('values');
    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    Assert.areEqual(
      'Related Fields',
      values.get('lastname'),
      'Direct fields still resolve'
    );
    Assert.areEqual(
      'Child Account',
      values.get('account.name'),
      'Keep the entire relationship path'
    );
    Assert.areEqual(
      'Parent Account',
      values.get('account.parent.name'),
      'Resolve two parent hops'
    );
    Assert.areEqual(
      Decimal.valueOf('0'),
      values.get('account.annualrevenue'),
      'Zero is a value'
    );
    Map<String, Object> info = (Map<String, Object>) metadata.get(
      'account.name'
    );
    Assert.areEqual(
      Account.Name.getDescribe().getLabel(),
      info.get('label'),
      'Use terminal field label'
    );
    Assert.areEqual(
      true,
      info.get('isRelatedField'),
      'Identify cross-object fields'
    );
    Assert.areEqual(
      false,
      info.get('isUpdateable'),
      'Related fields are read-only'
    );
    Assert.areEqual(1, queries, 'Lookup labels must not add queries per field');
  }

  @IsTest
  static void returnsNullForEmptyLookup() {
    Contact contact = [SELECT Id FROM Contact WHERE LastName = 'No Account'];
    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      contact.Id,
      'Contact',
      new List<String>{ 'Account.Name', 'Account.Parent.Name' }
    );
    Test.stopTest();
    Map<String, Object> values = (Map<String, Object>) result.get('values');
    Assert.isTrue(
      values.containsKey('account.name'),
      'Preserve the empty field'
    );
    Assert.isNull(values.get('account.name'), 'A missing lookup is blank');
    Assert.isNull(
      values.get('account.parent.name'),
      'A missing intermediate record is blank'
    );
  }

  @IsTest
  static void returnsNullForEmptySecondHop() {
    Account child = [SELECT Id FROM Account WHERE Name = 'Child Account'];
    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      child.Id,
      'Account',
      new List<String>{ 'Parent.Parent.Name' }
    );
    Test.stopTest();
    Map<String, Object> values = (Map<String, Object>) result.get('values');
    Assert.isNull(
      values.get('parent.parent.name'),
      'Null parent chains are safe'
    );
  }

  @IsTest
  static void resolvesLookupAtEndOfRelatedPath() {
    Contact contact = [
      SELECT Id, Account.ParentId
      FROM Contact
      WHERE LastName = 'Related Fields'
    ];
    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      contact.Id,
      'Contact',
      new List<String>{ 'Account.ParentId' }
    );
    Test.stopTest();
    Map<String, Object> values = (Map<String, Object>) result.get('values');
    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    Map<String, Object> info = (Map<String, Object>) metadata.get(
      'account.parentid'
    );
    Assert.areEqual(
      contact.Account.ParentId,
      values.get('account.parentid'),
      'Return the lookup Id'
    );
    Assert.areEqual(
      'Parent Account',
      info.get('referenceNameValue'),
      'Fetch the display name'
    );
    Assert.areEqual(
      'Account',
      info.get('referenceObjectName'),
      'Links target the related object'
    );
  }

  @IsTest
  static void rejectsInvalidPathsWithoutDroppingValidFields() {
    Contact contact = [
      SELECT Id
      FROM Contact
      WHERE LastName = 'Related Fields'
    ];
    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      contact.Id,
      'Contact',
      new List<String>{
        'LastName',
        'Account.NotAField',
        'NotARelationship.Name',
        'Account.Name FROM User',
        'Account..Name',
        'Account.',
        null,
        ''
      }
    );
    Test.stopTest();
    Map<String, Object> values = (Map<String, Object>) result.get('values');
    Assert.areEqual(
      'Related Fields',
      values.get('lastname'),
      'Valid fields still render'
    );
    for (String key : values.keySet()) {
      Assert.isFalse(
        key.contains('.'),
        'Invalid relationship paths must never be queried'
      );
    }
  }
}
