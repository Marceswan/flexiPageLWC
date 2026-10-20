/** Optional integration fixtures, deployed only in a validation-only package. */
@IsTest
private with sharing class FlexiPageCustomRelatedFieldsTest {
  private static FlexiPage_Related_Test__c hierarchy() {
    FlexiPage_Related_Test__c grandparent = new FlexiPage_Related_Test__c(
      Name = 'Grandparent',
      Status__c = 'Grandparent status'
    );
    insert grandparent;
    FlexiPage_Related_Test__c parent = new FlexiPage_Related_Test__c(
      Name = 'Parent',
      Parent__c = grandparent.Id,
      Status__c = 'Parent status',
      Hidden__c = 'Private value'
    );
    insert parent;
    FlexiPage_Related_Test__c child = new FlexiPage_Related_Test__c(
      Name = 'Child',
      Parent__c = parent.Id
    );
    insert child;
    return child;
  }

  @IsTest
  static void resolvesCustomLookupAndNestedLookup() {
    User reader = createReader();
    System.runAs(reader) {
      Assert.isTrue(
        FlexiPage_Related_Test__c.Status__c.getDescribe().isAccessible(),
        'Fixture reader must have Status read access'
      );
      FlexiPage_Related_Test__c child = hierarchy();
      Test.startTest();
      Map<String, Object> result = FlexiPageToolingService.getFieldValues(
        child.Id,
        'FlexiPage_Related_Test__c',
        new List<String>{
          'Record.Parent__r.Status__c',
          'Parent__r.Parent__r.Status__c',
          'Parent__r.Parent__c'
        }
      );
      Test.stopTest();
      Map<String, Object> values = (Map<String, Object>) result.get('values');
      Map<String, Object> metadata = (Map<String, Object>) result.get(
        'metadata'
      );
      Assert.areEqual(
        'Parent status',
        values.get('parent__r.status__c'),
        'Resolve custom relationship names'
      );
      Assert.areEqual(
        'Grandparent status',
        values.get('parent__r.parent__r.status__c'),
        'Resolve nested custom paths'
      );
      Map<String, Object> reference = (Map<String, Object>) metadata.get(
        'parent__r.parent__c'
      );
      Assert.areEqual(
        'Grandparent',
        reference.get('referenceNameValue'),
        'Related custom lookups retain labels'
      );
    }
  }

  @IsTest
  static void omitsRelatedFieldsWithoutReadPermission() {
    User reader = createReader();
    System.runAs(reader) {
      FlexiPage_Related_Test__c child = hierarchy();
      Test.startTest();
      Map<String, Object> result = FlexiPageToolingService.getFieldValues(
        child.Id,
        'FlexiPage_Related_Test__c',
        new List<String>{ 'Parent__r.Status__c', 'Parent__r.Hidden__c' }
      );
      Test.stopTest();
      Map<String, Object> values = (Map<String, Object>) result.get('values');
      Map<String, Object> metadata = (Map<String, Object>) result.get(
        'metadata'
      );
      Assert.areEqual(
        'Parent status',
        values.get('parent__r.status__c'),
        'Readable fields still resolve'
      );
      Assert.isFalse(
        values.containsKey('parent__r.hidden__c'),
        'Do not expose inaccessible values'
      );
      Assert.isFalse(
        metadata.containsKey('parent__r.hidden__c'),
        'Do not expose inaccessible metadata'
      );
    }
  }
  // Explicit fixture permissions avoid depending on the deploying user's profile.
  private static User createReader() {
    Profile minimal = [
      SELECT Id
      FROM Profile
      WHERE Name = 'Minimum Access - Salesforce'
      LIMIT 1
    ];
    User reader = new User(
      ProfileId = minimal.Id,
      Username = 'flexipage.' +
        UserInfo.getOrganizationId() +
        '.' +
        System.now().getTime() +
        '@example.invalid',
      Email = 'flexipage@example.invalid',
      Alias = 'fpread',
      LastName = 'FlexiPage reader',
      TimeZoneSidKey = 'America/Chicago',
      LocaleSidKey = 'en_US',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US'
    );
    insert reader;
    PermissionSet permission = new PermissionSet(
      Name = 'FlexiPage_Related_Field_Test',
      Label = 'FlexiPage related field test'
    );
    insert permission;
    insert new ObjectPermissions(
      ParentId = permission.Id,
      SobjectType = 'FlexiPage_Related_Test__c',
      PermissionsRead = true
    );
    insert new List<FieldPermissions>{
      new FieldPermissions(
        ParentId = permission.Id,
        SobjectType = 'FlexiPage_Related_Test__c',
        Field = 'FlexiPage_Related_Test__c.Parent__c',
        PermissionsRead = true
      ),
      new FieldPermissions(
        ParentId = permission.Id,
        SobjectType = 'FlexiPage_Related_Test__c',
        Field = 'FlexiPage_Related_Test__c.Status__c',
        PermissionsRead = true
      )
    };
    insert new PermissionSetAssignment(
      AssigneeId = reader.Id,
      PermissionSetId = permission.Id
    );
    return reader;
  }
}
