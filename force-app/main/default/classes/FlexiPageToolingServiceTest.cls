@isTest
private class FlexiPageToolingServiceTest {
  private static final String TEST_FLEXIPAGE_NAME = 'Account_Record_Page';
  private static final String TEST_OBJECT_API_NAME = 'Account';
  private static final String TEST_RECORD_ID = '001xx000003DGb0AAG';

  @isTest
  static void testGetFieldValues_RelationshipPaths() {
    Account grandparent = new Account(Name = 'Grandparent', AnnualRevenue = 0);
    insert grandparent;
    Account parent = new Account(Name = 'Parent', ParentId = grandparent.Id);
    insert parent;
    Account child = new Account(Name = 'Child', ParentId = parent.Id);
    insert child;

    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      child.Id,
      'Account',
      new List<String>{
        'Name',
        'Parent.Name',
        'ParentId.Name',
        'Parent.Parent.Name',
        'Parent.Parent.AnnualRevenue',
        'Parent.ParentId',
        'Parent.DoesNotExist__c',
        'NotARelationship.Name',
        'Name FROM User'
      }
    );
    Test.stopTest();
    Map<String, Object> values = (Map<String, Object>) result.get('values');
    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    System.assertEquals('Child', values.get('name'));
    System.assertEquals('Parent', values.get('parent.name'));
    System.assertEquals('Parent', values.get('parentid.name'));
    System.assertEquals('Grandparent', values.get('parent.parent.name'));
    System.assertEquals(
      Decimal.valueOf('0'),
      values.get('parent.parent.annualrevenue')
    );
    System.assertEquals(grandparent.Id, values.get('parent.parentid'));
    System.assert(!values.containsKey('parent.doesnotexist__c'));
    System.assert(!values.containsKey('notarelationship.name'));
    System.assert(!values.containsKey('name from user'));
    Map<String, Object> info = (Map<String, Object>) metadata.get(
      'parent.parent.annualrevenue'
    );
    System.assertEquals('CURRENCY', info.get('type'));
    System.assertEquals(
      Account.AnnualRevenue.getDescribe().getLabel(),
      info.get('label')
    );
    System.assertEquals(true, info.get('isRelatedField'));
    System.assertEquals('ParentId', info.get('rootLookupField'));
    System.assertEquals(
      Account.AnnualRevenue.getDescribe().getInlineHelpText(),
      info.get('inlineHelpText')
    );
    System.assertEquals(
      false,
      info.get('isUpdateable'),
      'Related fields are read-only'
    );
    Map<String, Object> lookupInfo = (Map<String, Object>) metadata.get(
      'parent.parentid'
    );
    System.assertEquals('Grandparent', lookupInfo.get('referenceNameValue'));
  }

  @isTest
  static void testGetFieldValues_EmptyRelationships() {
    Account parent = new Account(Name = 'Parent without grandparent');
    insert parent;
    Account child = new Account(Name = 'Child', ParentId = parent.Id);
    insert child;

    Test.startTest();
    Map<String, Object> childResult = FlexiPageToolingService.getFieldValues(
      child.Id,
      'Account',
      new List<String>{ 'Parent.Name', 'Parent.Parent.Name' }
    );
    Map<String, Object> parentResult = FlexiPageToolingService.getFieldValues(
      parent.Id,
      'Account',
      new List<String>{ 'Parent.Name', 'Parent.Parent.Name' }
    );
    Test.stopTest();
    Map<String, Object> childValues = (Map<String, Object>) childResult.get(
      'values'
    );
    Map<String, Object> parentValues = (Map<String, Object>) parentResult.get(
      'values'
    );
    System.assertEquals(
      'Parent without grandparent',
      childValues.get('parent.name')
    );
    System.assert(childValues.containsKey('parent.parent.name'));
    System.assertEquals(null, childValues.get('parent.parent.name'));
    System.assert(parentValues.containsKey('parent.name'));
    System.assertEquals(null, parentValues.get('parent.name'));
    System.assertEquals(null, parentValues.get('parent.parent.name'));
    Map<String, Object> metadata = (Map<String, Object>) parentResult.get(
      'metadata'
    );
    System.assertEquals(
      Account.Name.getDescribe().getLabel(),
      ((Map<String, Object>) metadata.get('parent.name')).get('label')
    );
  }

  @isTest
  static void testRelationshipPathValidation() {
    System.assertNotEquals(
      null,
      FlexiPageToolingService.resolveFieldPath(
        Account.SObjectType,
        'parent.name'
      )
    );
    System.assertEquals(
      null,
      FlexiPageToolingService.resolveFieldPath(
        Account.SObjectType,
        'Parent..Name'
      )
    );
    System.assertEquals(
      null,
      FlexiPageToolingService.resolveFieldPath(
        Account.SObjectType,
        'Parent.Name FROM User'
      )
    );
    System.assertEquals(
      null,
      FlexiPageToolingService.resolveFieldPath(
        Account.SObjectType,
        'Parent.Parent.Parent.Parent.Parent.Parent.Name'
      )
    );
    // Who can reference either Contact or Lead; traversing it is deliberately unsupported.
    System.assertEquals(
      null,
      FlexiPageToolingService.resolveFieldPath(Task.SObjectType, 'Who.Name')
    );
  }

  @isTest
  static void testGetFlexiPageMetadata_Success() {
    Test.setMock(HttpCalloutMock.class, new FlexiPageToolingServiceMock(false));

    Test.startTest();
    String result = FlexiPageToolingService.getFlexiPageMetadata(
      TEST_FLEXIPAGE_NAME
    );
    Test.stopTest();

    // After alignment: returns raw FlexiPage Metadata JSON directly (no envelope)
    System.assertNotEquals(null, result, 'Result should not be null');
    Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(
      result
    );
    // Raw metadata should have type or fullName at top level
    System.assert(
      resultMap.containsKey('type') || resultMap.containsKey('fullName'),
      'Result should contain raw FlexiPage metadata with type or fullName at top level'
    );
  }

  @isTest
  static void testGetFlexiPageMetadata_NoRecordsFound() {
    Test.setMock(HttpCalloutMock.class, new FlexiPageToolingServiceMock(true));

    Test.startTest();
    try {
      // After alignment: errors throw AuraHandledException instead of returning JSON envelope
      FlexiPageToolingService.getFlexiPageMetadata('NonExistent_Page');
      System.assert(false, 'AuraHandledException should have been thrown');
    } catch (AuraHandledException e) {
      // AuraHandledException wraps the message - verify it was thrown
      System.assertEquals(
        'Script-thrown exception',
        e.getMessage(),
        'Should throw AuraHandledException for not found FlexiPage'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetFieldValues_PicklistDisplayValue() {
    Account testAccount = new Account(
      Name = 'Picklist Account',
      Industry = 'Technology'
    );
    insert testAccount;

    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      testAccount.Id,
      TEST_OBJECT_API_NAME,
      new List<String>{ 'Industry' }
    );
    Test.stopTest();

    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    Map<String, Object> industryInfo = (Map<String, Object>) metadata.get(
      'industry'
    );
    System.assertEquals(
      FlexiPageToolingService.getPicklistDisplayValue(
        Account.Industry.getDescribe(),
        'Technology'
      ),
      industryInfo.get('displayValue'),
      'Picklist metadata should carry the display label'
    );
  }

  @isTest
  static void testGetFieldValues_PolymorphicLookupFallback() {
    Account whatAccount = new Account(Name = 'What Account');
    insert whatAccount;
    Task testTask = new Task(Subject = 'Follow up', WhatId = whatAccount.Id);
    insert testTask;

    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      testTask.Id,
      'Task',
      new List<String>{ 'WhatId' }
    );
    Test.stopTest();

    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    Map<String, Object> whatInfo = (Map<String, Object>) metadata.get('whatid');
    System.assertEquals(
      'Account',
      whatInfo.get('referenceObjectName'),
      'Should resolve the actual target object'
    );
    System.assertEquals(
      'What Account',
      whatInfo.get('referenceNameValue'),
      'Should query the name when targets share no name field'
    );
  }

  @isTest
  static void testReferenceNameField() {
    System.assertEquals(
      null,
      FlexiPageToolingService.referenceNameField(
        new List<Schema.SObjectType>()
      ),
      'No targets should have no name field'
    );
    System.assertEquals(
      'Name',
      FlexiPageToolingService.referenceNameField(
        new List<Schema.SObjectType>{ Account.SObjectType }
      ),
      'Account uses Name'
    );
    System.assertEquals(
      null,
      FlexiPageToolingService.referenceNameField(
        new List<Schema.SObjectType>{
          Account.SObjectType,
          Case.SObjectType
        }
      ),
      'Targets with different name fields should share none'
    );
  }

  @isTest
  static void testGetPicklistDisplayValue() {
    Schema.DescribeFieldResult industry = Account.Industry.getDescribe();
    Schema.PicklistEntry first = industry.getPicklistValues()[0];

    System.assertEquals(
      null,
      FlexiPageToolingService.getPicklistDisplayValue(industry, null),
      'Null value should stay null'
    );
    System.assertEquals(
      first.getLabel() + '; Not_A_Value',
      FlexiPageToolingService.getPicklistDisplayValue(
        industry,
        first.getValue() + ';Not_A_Value'
      ),
      'Should map known values to labels and keep unknown values'
    );
  }

  @isTest
  static void testGetFieldValues_Success() {
    Account testAccount = new Account(
      Name = 'Test Account',
      Type = 'Customer',
      Industry = 'Technology',
      AnnualRevenue = 1000000
    );
    insert testAccount;

    // Query the record back to verify the Name field
    Account insertedAccount = [
      SELECT Id, Name
      FROM Account
      WHERE Id = :testAccount.Id
    ];
    System.debug('Inserted Account Name: ' + insertedAccount.Name);

    Test.startTest();
    List<String> fieldApiNames = new List<String>{ 'Name', 'AnnualRevenue' };
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      testAccount.Id,
      TEST_OBJECT_API_NAME,
      fieldApiNames
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.debug('Result: ' + result);

    // Check structure of new response format
    System.assert(
      result.containsKey('values'),
      'Result should contain values map'
    );
    System.assert(
      result.containsKey('metadata'),
      'Result should contain metadata map'
    );

    Map<String, Object> values = (Map<String, Object>) result.get('values');
    if (values.containsKey('name')) {
      System.assertEquals(
        'Test Account',
        (String) values.get('name'),
        'Name field should match'
      );
    } else {
      System.assert(false, 'Name field is missing from the values');
    }
  }

  @isTest
  static void testGetFieldValues_EmptyFieldList() {
    Account testAccount = new Account(Name = 'Test Account for Empty Fields');
    insert testAccount;

    Test.startTest();
    // Pass null fieldApiNames to trigger the else path that adds all fields
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      testAccount.Id,
      TEST_OBJECT_API_NAME,
      null
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      result.containsKey('values'),
      'Result should contain values map'
    );
    System.assert(
      result.containsKey('metadata'),
      'Result should contain metadata map'
    );

    Map<String, Object> values = (Map<String, Object>) result.get('values');
    // When no specific fields are requested, all fields should be returned
    System.assert(values.size() > 0, 'Should return field values');
  }

  @isTest
  static void testGetFieldValues_WithOwnerIdUser() {
    // Create an Account with a User as Owner (default behavior)
    Account testAccount = new Account(Name = 'Test Account with User Owner');
    insert testAccount;

    // Reload to get OwnerId populated
    testAccount = [
      SELECT Id, OwnerId
      FROM Account
      WHERE Id = :testAccount.Id
    ];

    Test.startTest();
    List<String> fieldApiNames = new List<String>{
      'Name',
      'OwnerId',
      'CreatedById',
      'LastModifiedById'
    };
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      testAccount.Id,
      TEST_OBJECT_API_NAME,
      fieldApiNames
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      result.containsKey('metadata'),
      'Result should contain metadata'
    );

    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    System.assert(
      metadata.containsKey('ownerid'),
      'Should have OwnerId metadata'
    );
    System.assert(
      metadata.containsKey('createdbyid'),
      'Should have CreatedById metadata'
    );
    System.assert(
      metadata.containsKey('lastmodifiedbyid'),
      'Should have LastModifiedById metadata'
    );

    // Verify that reference name values were populated for User fields
    Map<String, Object> ownerInfo = (Map<String, Object>) metadata.get(
      'ownerid'
    );
    System.assert(
      ownerInfo.containsKey('referenceObjectName'),
      'OwnerId should have referenceObjectName'
    );
    // The referenceNameValue may or may not be populated depending on User query success
  }

  @isTest
  static void testGetFieldValues_WithOwnerIdGroup() {
    // Create setup objects in System.runAs to avoid mixed DML
    Group testQueue;
    User currentUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
    System.runAs(currentUser) {
      testQueue = new Group(
        Name = 'Test Queue',
        Type = 'Queue',
        DeveloperName = 'Test_Queue_' + String.valueOf(System.now().getTime())
      );
      insert testQueue;

      QueueSObject queueSObject = new QueueSObject(
        QueueId = testQueue.Id,
        SObjectType = 'Case'
      );
      insert queueSObject;
    }

    // Create non-setup object separately
    Case testCase = new Case(
      Subject = 'Test Case with Queue Owner',
      OwnerId = testQueue.Id
    );
    insert testCase;

    Test.startTest();
    List<String> fieldApiNames = new List<String>{ 'Subject', 'OwnerId' };
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      testCase.Id,
      'Case',
      fieldApiNames
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      result.containsKey('metadata'),
      'Result should contain metadata'
    );

    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    Map<String, Object> ownerInfo = (Map<String, Object>) metadata.get(
      'ownerid'
    );
    System.assert(
      ownerInfo.containsKey('referenceObjectName'),
      'OwnerId should have referenceObjectName'
    );
    // The referenceNameValue should be populated with the Queue name
    if (ownerInfo.containsKey('referenceNameValue')) {
      System.assertEquals(
        'Test Queue',
        ownerInfo.get('referenceNameValue'),
        'Should have Queue name'
      );
    }
  }

  @isTest
  static void testGetFieldValues_WithStandardLookup() {
    // Create a parent Account for lookup
    Account parentAccount = new Account(Name = 'Parent Account');
    insert parentAccount;

    // Create a child Account with ParentId lookup
    Account childAccount = new Account(
      Name = 'Child Account',
      ParentId = parentAccount.Id
    );
    insert childAccount;

    Test.startTest();
    List<String> fieldApiNames = new List<String>{ 'Name', 'ParentId' };
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      childAccount.Id,
      TEST_OBJECT_API_NAME,
      fieldApiNames
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      result.containsKey('metadata'),
      'Result should contain metadata'
    );

    Map<String, Object> metadata = (Map<String, Object>) result.get('metadata');
    Map<String, Object> parentInfo = (Map<String, Object>) metadata.get(
      'parentid'
    );
    System.assert(
      parentInfo.containsKey('referenceObjectName'),
      'ParentId should have referenceObjectName'
    );
    System.assertEquals(
      'Account',
      parentInfo.get('referenceObjectName'),
      'ParentId should reference Account'
    );

    // Verify that reference name value was populated
    if (parentInfo.containsKey('referenceNameValue')) {
      System.assertEquals(
        'Parent Account',
        parentInfo.get('referenceNameValue'),
        'Should have parent account name'
      );
    }
  }

  @isTest
  static void testGetFieldValues_ReferenceFieldWithInvalidId() {
    // Create an Account
    Account testAccount = new Account(Name = 'Test Account Reference Error');
    insert testAccount;

    // We'll test the exception handling path by using a valid field structure
    // but the getFieldValues method will handle any errors gracefully
    Test.startTest();
    List<String> fieldApiNames = new List<String>{ 'Name', 'ParentId' };
    Map<String, Object> result = FlexiPageToolingService.getFieldValues(
      testAccount.Id,
      TEST_OBJECT_API_NAME,
      fieldApiNames
    );
    Test.stopTest();

    // Should still return a result even if ParentId is null
    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      result.containsKey('metadata'),
      'Result should contain metadata'
    );
  }

  @isTest
  static void testGetFieldValues_InvalidObject() {
    Test.startTest();
    try {
      FlexiPageToolingService.getFieldValues(
        TEST_RECORD_ID,
        'InvalidObject',
        new List<String>()
      );
      System.assert(false, 'Exception should have been thrown');
    } catch (AuraHandledException e) {
      System.assertEquals(
        'Script-thrown exception',
        e.getMessage(),
        'Incorrect exception message'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetUiFormatSpecificationSet_Success() {
    Test.setMock(HttpCalloutMock.class, new UiFormatSpecMock(false));

    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getUiFormatSpecificationSet(
      'Test_Format_Spec'
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(
      result.containsKey('developerName') || result.containsKey('success'),
      'Result should contain developerName or success flag'
    );
  }

  @isTest
  static void testGetUiFormatSpecificationSet_Error() {
    Test.setMock(HttpCalloutMock.class, new UiFormatSpecMock(true));

    Test.startTest();
    Map<String, Object> result = FlexiPageToolingService.getUiFormatSpecificationSet(
      'NonExistent_Format_Spec'
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    // The result will contain error information from the metadata service
  }

  @isTest
  static void testGetAllSObjects() {
    Test.startTest();
    List<Map<String, Object>> result = FlexiPageToolingService.getAllSObjects();
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(result.size() > 0, 'Should return at least one sObject');

    // Verify structure of returned data
    Map<String, Object> firstObject = result[0];
    System.assert(
      firstObject.containsKey('value'),
      'Each sObject should have a value'
    );
    System.assert(
      firstObject.containsKey('label'),
      'Each sObject should have a label'
    );
    System.assert(
      firstObject.containsKey('isCustom'),
      'Each sObject should have isCustom flag'
    );

    // Verify Account object is included (should always exist)
    Boolean foundAccount = false;
    for (Map<String, Object> sObj : result) {
      if (sObj.get('value') == 'Account') {
        foundAccount = true;
        System.assertEquals(
          false,
          sObj.get('isCustom'),
          'Account should not be custom'
        );
        break;
      }
    }
    System.assert(foundAccount, 'Account object should be in the list');
  }

  @isTest
  static void testGetObjectFields() {
    Test.startTest();
    List<Map<String, Object>> result = FlexiPageToolingService.getObjectFields(
      'Account'
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assert(result.size() > 0, 'Should return at least one field');

    // Verify structure of returned data
    Map<String, Object> firstField = result[0];
    System.assert(
      firstField.containsKey('apiName'),
      'Each field should have apiName'
    );
    System.assert(
      firstField.containsKey('label'),
      'Each field should have label'
    );
    System.assert(
      firstField.containsKey('type'),
      'Each field should have type'
    );
    System.assert(
      firstField.containsKey('required'),
      'Each field should have required flag'
    );

    // Verify Name field is included (should always exist for Account)
    Boolean foundName = false;
    for (Map<String, Object> field : result) {
      if (field.get('apiName') == 'Name') {
        foundName = true;
        System.assertEquals(
          'STRING',
          field.get('type'),
          'Name should be STRING type'
        );
        break;
      }
    }
    System.assert(foundName, 'Name field should be in the list');
  }

  @isTest
  static void testGetObjectFields_InvalidObject() {
    Test.startTest();
    try {
      FlexiPageToolingService.getObjectFields('InvalidObject');
      System.assert(false, 'Exception should have been thrown');
    } catch (AuraHandledException e) {
      // AuraHandledException returns "Script-thrown exception" as the message
      System.assertEquals(
        'Script-thrown exception',
        e.getMessage(),
        'Incorrect exception message'
      );
    }
    Test.stopTest();
  }

  @isTest
  static void testGetAvailableFlexiPages() {
    // Mock the HTTP callout
    Test.setMock(HttpCalloutMock.class, new FlexiPageAvailableMock());

    Test.startTest();
    List<Map<String, Object>> result = FlexiPageToolingService.getAvailableFlexiPages(
      'Account'
    );
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    // In mock, we should get the expected results
  }

  @isTest
  static void testSObjectComparator() {
    // Create test data for sorting
    List<Map<String, Object>> testList = new List<Map<String, Object>>();

    Map<String, Object> customObj = new Map<String, Object>();
    customObj.put('value', 'Custom__c');
    customObj.put('label', 'Custom Object (Custom__c)');
    customObj.put('isCustom', true);
    testList.add(customObj);

    Map<String, Object> standardObj1 = new Map<String, Object>();
    standardObj1.put('value', 'Contact');
    standardObj1.put('label', 'Contact (Contact)');
    standardObj1.put('isCustom', false);
    testList.add(standardObj1);

    Map<String, Object> standardObj2 = new Map<String, Object>();
    standardObj2.put('value', 'Account');
    standardObj2.put('label', 'Account (Account)');
    standardObj2.put('isCustom', false);
    testList.add(standardObj2);

    Test.startTest();
    testList.sort(new FlexiPageToolingService.SObjectComparator());
    Test.stopTest();

    // Verify sorting: standard objects should come first, then custom
    System.assertEquals(
      'Account',
      testList[0].get('value'),
      'Account should be first (standard, alphabetical)'
    );
    System.assertEquals(
      'Contact',
      testList[1].get('value'),
      'Contact should be second (standard, alphabetical)'
    );
    System.assertEquals(
      'Custom__c',
      testList[2].get('value'),
      'Custom__c should be last (custom)'
    );
  }

  @isTest
  static void testFieldComparator() {
    // Create test data for field sorting
    List<Map<String, Object>> fieldList = new List<Map<String, Object>>();

    Map<String, Object> field1 = new Map<String, Object>();
    field1.put('apiName', 'ZField__c');
    field1.put('label', 'Z Field');
    fieldList.add(field1);

    Map<String, Object> field2 = new Map<String, Object>();
    field2.put('apiName', 'AField__c');
    field2.put('label', 'A Field');
    fieldList.add(field2);

    Map<String, Object> field3 = new Map<String, Object>();
    field3.put('apiName', 'MField__c');
    field3.put('label', null); // Test null handling
    fieldList.add(field3);

    Test.startTest();
    fieldList.sort(new FlexiPageToolingService.FieldComparator());
    Test.stopTest();

    // Verify sorting: alphabetical by label, nulls last
    System.assertEquals(
      'A Field',
      fieldList[0].get('label'),
      'A Field should be first'
    );
    System.assertEquals(
      'Z Field',
      fieldList[1].get('label'),
      'Z Field should be second'
    );
    System.assertEquals(null, fieldList[2].get('label'), 'Null should be last');
  }

  @isTest
  static void testFieldComparator_BothNull() {
    // Test the case where both labels are null
    List<Map<String, Object>> fieldList = new List<Map<String, Object>>();

    Map<String, Object> field1 = new Map<String, Object>();
    field1.put('apiName', 'Field1__c');
    field1.put('label', null);
    fieldList.add(field1);

    Map<String, Object> field2 = new Map<String, Object>();
    field2.put('apiName', 'Field2__c');
    field2.put('label', null);
    fieldList.add(field2);

    Test.startTest();
    fieldList.sort(new FlexiPageToolingService.FieldComparator());
    Test.stopTest();

    // Both nulls should remain in place (compareTo returns 0)
    System.assertEquals(
      null,
      fieldList[0].get('label'),
      'First should be null'
    );
    System.assertEquals(
      null,
      fieldList[1].get('label'),
      'Second should be null'
    );
  }

  private class FlexiPageToolingServiceMock implements HttpCalloutMock {
    private Boolean returnEmptyResults;

    public FlexiPageToolingServiceMock(Boolean returnEmptyResults) {
      this.returnEmptyResults = returnEmptyResults;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(200);

      if (returnEmptyResults) {
        res.setBody('{"records":[]}');
      } else {
        res.setBody(
          '{"records":[{"Metadata":{"type":"FlexiPage","fullName":"' +
            TEST_FLEXIPAGE_NAME +
            '"}}]}'
        );
      }

      return res;
    }
  }

  private class FlexiPageAvailableMock implements HttpCalloutMock {
    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(200);

      // Mock response for available FlexiPages
      String responseBody =
        '{"records":[' +
        '{"Id":"0M0xx0000000001","DeveloperName":"Account_Record_Page","MasterLabel":"Account Record Page","Description":"Standard Account page","Metadata":{"sobjectType":"Account"}},' +
        '{"Id":"0M0xx0000000002","DeveloperName":"Account_Custom_Page","MasterLabel":"Account Custom Page","Description":"Custom Account page","Metadata":{"sobjectType":"Account"}}' +
        ']}';
      res.setBody(responseBody);

      return res;
    }
  }

  private class UiFormatSpecMock implements HttpCalloutMock {
    private Boolean returnError;

    public UiFormatSpecMock(Boolean returnError) {
      this.returnError = returnError;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setStatusCode(200);

      if (returnError) {
        res.setBody('{"records":[]}');
      } else {
        res.setBody(
          '{"records":[{"Metadata":{"type":"UiFormatSpecificationSet","fullName":"Test_Format_Spec"}}]}'
        );
      }

      return res;
    }
  }
}
