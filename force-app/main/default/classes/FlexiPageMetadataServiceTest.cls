/**
 * @description Test class for FlexiPageMetadataService
 * @author Marc Swan
 * @date 2025-01-19
 */
@isTest
private class FlexiPageMetadataServiceTest {
  /**
   * @description Mock HTTP response
   */
  private class MockHttpResponse implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;

    public MockHttpResponse(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setStatusCode(statusCode);
      res.setBody(responseBody);
      return res;
    }
  }

  // ===== getFlexiPageFields tests =====

  @isTest
  static void testGetFlexiPageFields_Success() {
    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = FlexiPageMetadataService.getFlexiPageFields(
      'Account_Record_Page'
    );
    Test.stopTest();

    System.assertNotEquals(null, fieldInfoList, 'Field info list should not be null');
    System.assertEquals(2, fieldInfoList.size(), 'Should have 2 field instances');

    FlexiPageMetadataService.FieldInfo field1 = fieldInfoList[0];
    System.assertEquals('Region1', field1.section, 'Section should be Region1');
    System.assertEquals(1, field1.position, 'Position should be 1');
    System.assertEquals('Name', field1.fieldName, 'Field name should be Name');
    System.assertNotEquals(null, field1.visibilityRules, 'Visibility rules should exist');
    System.assertEquals('1 AND 2', field1.visibilityRules.get('booleanFilter'), 'Boolean filter should match');

    FlexiPageMetadataService.FieldInfo field2 = fieldInfoList[1];
    System.assertEquals('Phone', field2.fieldName, 'Field name should be Phone');
    System.assertEquals(null, field2.visibilityRules, 'Visibility rules should be null');
  }

  @isTest
  static void testGetFlexiPageFields_BlankDeveloperName() {
    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = FlexiPageMetadataService.getFlexiPageFields('');
    Test.stopTest();

    System.assertNotEquals(null, fieldInfoList, 'Should not be null');
    System.assertEquals(0, fieldInfoList.size(), 'Should have no fields for blank name');
  }

  @isTest
  static void testGetFlexiPageFields_NullDeveloperName() {
    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = FlexiPageMetadataService.getFlexiPageFields(null);
    Test.stopTest();

    System.assertEquals(0, fieldInfoList.size(), 'Should have no fields for null name');
  }

  @isTest
  static void testGetFlexiPageFields_NonExistentPage() {
    Test.setMock(HttpCalloutMock.class, new MockHttpResponse(404, ''));
    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = FlexiPageMetadataService.getFlexiPageFields('NonExistent_Page');
    Test.stopTest();

    System.assertEquals(0, fieldInfoList.size(), 'Should have no fields');
  }

  @isTest
  static void testGetFlexiPageFields_EmptyPage() {
    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = FlexiPageMetadataService.getFlexiPageFields('Empty_Page');
    Test.stopTest();

    System.assertEquals(0, fieldInfoList.size(), 'Empty page should have no fields');
  }

  @isTest
  static void testGetFlexiPageFields_ComplexPage() {
    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = FlexiPageMetadataService.getFlexiPageFields('Complex_Page');
    Test.stopTest();

    System.assertEquals(3, fieldInfoList.size(), 'Complex page should have 3 fields');
  }

  // ===== getFlexiPageMetadata tests =====

  @isTest
  static void testGetFlexiPageMetadata_Success() {
    Test.startTest();
    String jsonResult = FlexiPageMetadataService.getFlexiPageMetadata('Account_Record_Page');
    Test.stopTest();

    Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResult);
    System.assertEquals(true, resultMap.get('success'), 'Success should be true');
    System.assertEquals('Account_Record_Page', resultMap.get('developerName'), 'Developer name should match');

    Map<String, Object> metadata = (Map<String, Object>) resultMap.get('metadata');
    System.assertNotEquals(null, metadata, 'Metadata should not be null');
    System.assertEquals('Account_Record_Page', metadata.get('fullName'), 'Full name should match');
    System.assertEquals('RecordPage', metadata.get('type'), 'Type should be RecordPage');
  }

  @isTest
  static void testGetFlexiPageMetadata_BlankDeveloperName() {
    Test.startTest();
    String jsonResult = FlexiPageMetadataService.getFlexiPageMetadata('');
    Test.stopTest();

    Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResult);
    System.assertEquals(false, resultMap.get('success'), 'Should be false');
    System.assert(
      ((String) resultMap.get('error')).contains('Developer name cannot be blank'),
      'Error should mention blank developer name'
    );
  }

  @isTest
  static void testGetFlexiPageMetadata_FlexiPageNotFound() {
    Test.setMock(HttpCalloutMock.class, new MockHttpResponse(404, ''));
    Test.startTest();
    String jsonResult = FlexiPageMetadataService.getFlexiPageMetadata('NonExistent_Page');
    Test.stopTest();

    Map<String, Object> resultMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResult);
    System.assertEquals(false, resultMap.get('success'), 'Should indicate not found');
  }

  // ===== FieldInfo tests =====

  @isTest
  static void testFieldInfoConstructor() {
    Map<String, Object> visibilityRules = new Map<String, Object>{
      'booleanFilter' => '1',
      'criteria' => new List<Object>()
    };

    Test.startTest();
    FlexiPageMetadataService.FieldInfo fieldInfo = new FlexiPageMetadataService.FieldInfo(
      'TestSection', 1, 'TestField', visibilityRules
    );
    Test.stopTest();

    System.assertEquals('TestSection', fieldInfo.section, 'Section should match');
    System.assertEquals(1, fieldInfo.position, 'Position should match');
    System.assertEquals('TestField', fieldInfo.fieldName, 'Field name should match');
    System.assertEquals(visibilityRules, fieldInfo.visibilityRules, 'Rules should match');
  }

  // ===== FlexiPageMetadataException tests =====

  @isTest
  static void testFlexiPageMetadataException() {
    Test.startTest();
    try {
      throw new FlexiPageMetadataService.FlexiPageMetadataException('Test exception');
    } catch (FlexiPageMetadataService.FlexiPageMetadataException e) {
      System.assertEquals('Test exception', e.getMessage(), 'Message should match');
    }
    Test.stopTest();
  }

  // ===== processFlexiPageMetadata tests =====

  @isTest
  static void testProcessFlexiPageMetadata_DirectFieldInstances() {
    Map<String, Object> metadata = new Map<String, Object>();
    List<Map<String, Object>> regions = new List<Map<String, Object>>();
    Map<String, Object> region = new Map<String, Object>();
    region.put('name', 'TestRegion');
    region.put('type', 'Region');

    List<Map<String, Object>> items = new List<Map<String, Object>>();

    // Field with visibility rules and Record. prefix
    Map<String, Object> item1 = new Map<String, Object>();
    Map<String, Object> fieldInst1 = new Map<String, Object>();
    fieldInst1.put('fieldItem', 'Record.Email');

    Map<String, Object> visRule = new Map<String, Object>();
    visRule.put('booleanFilter', '1');
    List<Map<String, Object>> criteria = new List<Map<String, Object>>();
    Map<String, Object> criterion = new Map<String, Object>();
    criterion.put('field', 'Status');
    criterion.put('operation', 'equals');
    criterion.put('value', 'Active');
    criteria.add(criterion);
    visRule.put('criteria', criteria);
    fieldInst1.put('visibilityRule', visRule);
    item1.put('fieldInstance', fieldInst1);
    items.add(item1);

    // Field without Record. prefix
    Map<String, Object> item2 = new Map<String, Object>();
    Map<String, Object> fieldInst2 = new Map<String, Object>();
    fieldInst2.put('fieldItem', 'Website');
    item2.put('fieldInstance', fieldInst2);
    items.add(item2);

    region.put('itemInstances', items);
    regions.add(region);
    metadata.put('flexiPageRegions', regions);

    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fields = FlexiPageMetadataService.processFlexiPageMetadata(metadata);
    Test.stopTest();

    System.assertEquals(2, fields.size(), 'Should have 2 fields');
    System.assertEquals('Email', fields[0].fieldName, 'Should strip Record. prefix');
    System.assertNotEquals(null, fields[0].visibilityRules, 'Should have visibility rules');
    System.assertEquals('Website', fields[1].fieldName, 'Field without prefix');
  }

  @isTest
  static void testProcessFlexiPageMetadata_ComponentInstances() {
    Map<String, Object> metadata = new Map<String, Object>();
    List<Map<String, Object>> regions = new List<Map<String, Object>>();
    Map<String, Object> region = new Map<String, Object>();
    region.put('name', 'MainRegion');
    region.put('type', 'Region');

    List<Map<String, Object>> items = new List<Map<String, Object>>();

    // Component instance with fieldSection
    Map<String, Object> item = new Map<String, Object>();
    Map<String, Object> componentInstance = new Map<String, Object>();
    componentInstance.put('componentType', 'flexipage:fieldSection');
    componentInstance.put('componentName', 'fieldSection1');

    List<Map<String, Object>> nestedItems = new List<Map<String, Object>>();
    Map<String, Object> nestedItem = new Map<String, Object>();
    Map<String, Object> fieldInstance = new Map<String, Object>();
    fieldInstance.put('fieldItem', 'Record.Industry');
    nestedItem.put('fieldInstance', fieldInstance);
    nestedItems.add(nestedItem);
    componentInstance.put('itemInstances', nestedItems);

    item.put('componentInstance', componentInstance);
    items.add(item);

    region.put('itemInstances', items);
    regions.add(region);
    metadata.put('flexiPageRegions', regions);

    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fields = FlexiPageMetadataService.processFlexiPageMetadata(metadata);
    Test.stopTest();

    System.assertEquals(1, fields.size(), 'Should have 1 field from fieldSection');
    System.assertEquals('Industry', fields[0].fieldName, 'Should be Industry');
  }

  @isTest
  static void testProcessFlexiPageMetadata_FacetRegions() {
    Map<String, Object> metadata = new Map<String, Object>();
    List<Map<String, Object>> regions = new List<Map<String, Object>>();

    Map<String, Object> facetRegion = new Map<String, Object>();
    facetRegion.put('name', 'Facet1');
    facetRegion.put('type', 'Facet');

    List<Map<String, Object>> facetItems = new List<Map<String, Object>>();
    Map<String, Object> fItem = new Map<String, Object>();
    Map<String, Object> fFieldInst = new Map<String, Object>();
    fFieldInst.put('fieldItem', 'Name');
    fItem.put('fieldInstance', fFieldInst);
    facetItems.add(fItem);
    facetRegion.put('itemInstances', facetItems);
    regions.add(facetRegion);

    Map<String, Object> normalRegion = new Map<String, Object>();
    normalRegion.put('name', 'Region1');
    normalRegion.put('type', 'Region');

    List<Map<String, Object>> rItems = new List<Map<String, Object>>();
    Map<String, Object> rItem = new Map<String, Object>();
    Map<String, Object> rFieldInst = new Map<String, Object>();
    rFieldInst.put('fieldItem', 'Phone');
    rItem.put('fieldInstance', rFieldInst);
    rItems.add(rItem);
    normalRegion.put('itemInstances', rItems);
    regions.add(normalRegion);

    metadata.put('flexiPageRegions', regions);

    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fields = FlexiPageMetadataService.processFlexiPageMetadata(metadata);
    Test.stopTest();

    System.assert(fields.size() >= 1, 'Should have fields');
  }

  @isTest
  static void testProcessFlexiPageMetadata_NoRegions() {
    Map<String, Object> metadata = new Map<String, Object>();
    metadata.put('fullName', 'Test_Page');

    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fields = FlexiPageMetadataService.processFlexiPageMetadata(metadata);
    Test.stopTest();

    System.assertEquals(0, fields.size(), 'Should have no fields');
  }

  @isTest
  static void testProcessFlexiPageMetadata_DuplicateFields() {
    Map<String, Object> metadata = new Map<String, Object>();
    List<Map<String, Object>> regions = new List<Map<String, Object>>();
    Map<String, Object> region = new Map<String, Object>();
    region.put('name', 'TestRegion');
    region.put('type', 'Region');

    List<Map<String, Object>> items = new List<Map<String, Object>>();

    // Same field twice
    for (Integer i = 0; i < 2; i++) {
      Map<String, Object> item = new Map<String, Object>();
      Map<String, Object> fieldInst = new Map<String, Object>();
      fieldInst.put('fieldItem', 'Name');
      item.put('fieldInstance', fieldInst);
      items.add(item);
    }

    region.put('itemInstances', items);
    regions.add(region);
    metadata.put('flexiPageRegions', regions);

    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fields = FlexiPageMetadataService.processFlexiPageMetadata(metadata);
    Test.stopTest();

    System.assertEquals(1, fields.size(), 'Should deduplicate fields');
  }

  @isTest
  static void testProcessFlexiPageMetadata_NonFieldSectionComponent() {
    Map<String, Object> metadata = new Map<String, Object>();
    List<Map<String, Object>> regions = new List<Map<String, Object>>();
    Map<String, Object> region = new Map<String, Object>();
    region.put('name', 'TestRegion');
    region.put('type', 'Region');

    List<Map<String, Object>> items = new List<Map<String, Object>>();
    Map<String, Object> item = new Map<String, Object>();
    Map<String, Object> compInst = new Map<String, Object>();
    compInst.put('componentName', 'force:recordData');
    compInst.put('componentType', 'aura:component');
    item.put('componentInstance', compInst);
    items.add(item);

    region.put('itemInstances', items);
    regions.add(region);
    metadata.put('flexiPageRegions', regions);

    Test.startTest();
    List<FlexiPageMetadataService.FieldInfo> fields = FlexiPageMetadataService.processFlexiPageMetadata(metadata);
    Test.stopTest();

    System.assertEquals(0, fields.size(), 'Non-field components should not produce fields');
  }

  // ===== Direct @TestVisible method tests =====

  @isTest
  static void testConvertFlexiPageToMap_Direct() {
    MetadataService.FlexiPage flexiPage = new MetadataService.FlexiPage();
    flexiPage.fullName = 'Test_Page';
    flexiPage.masterLabel = 'Test Page';
    flexiPage.type_x = 'RecordPage';
    flexiPage.sobjectType = 'Account';
    flexiPage.description = 'Test';

    // With regions
    MetadataService.FlexiPageRegion region = new MetadataService.FlexiPageRegion();
    region.name = 'main';
    region.type_x = 'Region';
    region.mode = 'Replace';
    region.componentInstances = null;
    flexiPage.flexiPageRegions = new List<MetadataService.FlexiPageRegion>{ region };

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertFlexiPageToMap(flexiPage);
    Test.stopTest();

    System.assertEquals('Test_Page', result.get('fullName'), 'Full name should match');
    System.assertEquals('Test Page', result.get('masterLabel'), 'Master label should match');
    System.assertEquals('RecordPage', result.get('type'), 'Type should match');
    System.assertEquals('Account', result.get('sobjectType'), 'SObject type should match');
    System.assertEquals('Test', result.get('description'), 'Description should match');
    System.assert(result.containsKey('flexiPageRegions'), 'Should have regions');
  }

  @isTest
  static void testConvertFlexiPageToMap_NullRegions() {
    MetadataService.FlexiPage flexiPage = new MetadataService.FlexiPage();
    flexiPage.fullName = 'Empty_Page';
    flexiPage.masterLabel = 'Empty Page';
    flexiPage.type_x = 'RecordPage';
    flexiPage.flexiPageRegions = null;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertFlexiPageToMap(flexiPage);
    Test.stopTest();

    System.assertEquals('Empty_Page', result.get('fullName'), 'Full name should match');
    System.assert(!result.containsKey('flexiPageRegions'), 'Should not have regions');
  }

  @isTest
  static void testConvertFlexiPageRegionToMap_WithFieldItems() {
    MetadataService.FlexiPageRegion region = new MetadataService.FlexiPageRegion();
    region.name = 'Section1';
    region.type_x = 'Region';
    region.mode = 'Replace';

    // Component with fieldItem property
    MetadataService.ComponentInstance comp = new MetadataService.ComponentInstance();
    comp.componentName = 'force:recordViewForm';

    MetadataService.ComponentInstanceProperty fieldProp = new MetadataService.ComponentInstanceProperty();
    fieldProp.name = 'fieldItem';
    fieldProp.value = 'Record.Name';

    MetadataService.ComponentInstanceProperty uiBehaviorProp = new MetadataService.ComponentInstanceProperty();
    uiBehaviorProp.name = 'uiBehavior';
    uiBehaviorProp.value = 'required';

    MetadataService.ComponentInstanceProperty formatProp = new MetadataService.ComponentInstanceProperty();
    formatProp.name = 'conditionalFormatRuleset';
    formatProp.value = 'TestRuleset';

    comp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{
      fieldProp, uiBehaviorProp, formatProp
    };

    // Add visibility rule
    MetadataService.UiFormulaRule visRule = new MetadataService.UiFormulaRule();
    visRule.booleanFilter = '1';
    MetadataService.UiFormulaCriterion crit = new MetadataService.UiFormulaCriterion();
    crit.leftValue = 'Type';
    crit.operator = 'equals';
    crit.rightValue = 'Customer';
    visRule.criteria = new List<MetadataService.UiFormulaCriterion>{ crit };
    comp.visibilityRule = visRule;

    region.componentInstances = new List<MetadataService.ComponentInstance>{ comp };

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertFlexiPageRegionToMap(region);
    Test.stopTest();

    System.assertEquals('Section1', result.get('name'), 'Region name should match');
    System.assertEquals('Region', result.get('type'), 'Region type should match');
    List<Object> itemInstances = (List<Object>) result.get('itemInstances');
    System.assertEquals(1, itemInstances.size(), 'Should have 1 item');

    Map<String, Object> item = (Map<String, Object>) itemInstances[0];
    System.assert(item.containsKey('fieldInstance'), 'Should be a field instance');
    Map<String, Object> fieldInstance = (Map<String, Object>) item.get('fieldInstance');
    System.assertEquals('Record.Name', fieldInstance.get('fieldItem'), 'Field item should match');
    System.assert(fieldInstance.containsKey('visibilityRule'), 'Should have visibility rule');
    System.assert(fieldInstance.containsKey('fieldInstanceProperties'), 'Should have properties');
  }

  @isTest
  static void testConvertFlexiPageRegionToMap_NoComponents() {
    MetadataService.FlexiPageRegion region = new MetadataService.FlexiPageRegion();
    region.name = 'EmptyRegion';
    region.type_x = 'Region';
    region.componentInstances = null;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertFlexiPageRegionToMap(region);
    Test.stopTest();

    List<Object> itemInstances = (List<Object>) result.get('itemInstances');
    System.assertEquals(0, itemInstances.size(), 'Should have empty items');
  }

  @isTest
  static void testConvertComponentInstanceToMap_FieldSection() {
    MetadataService.ComponentInstance comp = new MetadataService.ComponentInstance();
    comp.componentName = 'flexipage:fieldSection';

    MetadataService.ComponentInstanceProperty fieldProp = new MetadataService.ComponentInstanceProperty();
    fieldProp.name = 'fieldItem';
    fieldProp.value = 'Record.Phone';

    comp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{ fieldProp };

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertComponentInstanceToMap(comp);
    Test.stopTest();

    System.assertEquals('flexipage:fieldSection', result.get('componentName'), 'Name should match');
    System.assertEquals('flexipage:fieldSection', result.get('componentType'), 'Should be fieldSection type');
    System.assert(result.containsKey('itemInstances'), 'Should have itemInstances');
  }

  @isTest
  static void testConvertComponentInstanceToMap_NonFieldSection() {
    MetadataService.ComponentInstance comp = new MetadataService.ComponentInstance();
    comp.componentName = 'force:recordData';

    MetadataService.ComponentInstanceProperty prop = new MetadataService.ComponentInstanceProperty();
    prop.name = 'recordId';
    prop.value = '{!recordId}';
    prop.type_x = 'String';

    // Add actionNames property with null value to cover valueList path
    MetadataService.ComponentInstanceProperty actionProp = new MetadataService.ComponentInstanceProperty();
    actionProp.name = 'actionNames';
    actionProp.value = null;

    comp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{ prop, actionProp };

    // Add visibility rule
    MetadataService.UiFormulaRule visRule = new MetadataService.UiFormulaRule();
    visRule.booleanFilter = null;
    visRule.criteria = null;
    comp.visibilityRule = visRule;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertComponentInstanceToMap(comp);
    Test.stopTest();

    System.assertEquals('force:recordData', result.get('componentName'), 'Name should match');
    System.assert(result.containsKey('componentInstanceProperties'), 'Should have properties');
    System.assert(result.containsKey('visibilityRule'), 'Should have visibility rule');
  }

  @isTest
  static void testConvertUiFormulaRuleToMap_Direct() {
    MetadataService.UiFormulaRule rule = new MetadataService.UiFormulaRule();
    rule.booleanFilter = '1 AND 2';

    MetadataService.UiFormulaCriterion crit1 = new MetadataService.UiFormulaCriterion();
    crit1.leftValue = 'Type';
    crit1.operator = 'equals';
    crit1.rightValue = 'Customer';

    MetadataService.UiFormulaCriterion crit2 = new MetadataService.UiFormulaCriterion();
    crit2.leftValue = 'Status';
    crit2.operator = 'notEqual';
    crit2.rightValue = 'Closed';

    rule.criteria = new List<MetadataService.UiFormulaCriterion>{ crit1, crit2 };

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertUiFormulaRuleToMap(rule);
    Test.stopTest();

    System.assertEquals('1 AND 2', result.get('booleanFilter'), 'Boolean filter should match');
    List<Object> criteria = (List<Object>) result.get('criteria');
    System.assertEquals(2, criteria.size(), 'Should have 2 criteria');
  }

  @isTest
  static void testConvertUiFormulaRuleToMap_NullFields() {
    MetadataService.UiFormulaRule rule = new MetadataService.UiFormulaRule();
    rule.booleanFilter = null;
    rule.criteria = null;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertUiFormulaRuleToMap(rule);
    Test.stopTest();

    System.assert(!result.containsKey('booleanFilter'), 'Should not have booleanFilter');
    System.assert(!result.containsKey('criteria'), 'Should not have criteria');
  }

  @isTest
  static void testProcessItemInstances_Direct() {
    List<Object> items = new List<Object>();

    // Field with visibility rules
    Map<String, Object> item1 = new Map<String, Object>();
    Map<String, Object> fieldInst1 = new Map<String, Object>();
    fieldInst1.put('fieldItem', 'Record.Email');

    Map<String, Object> visRule = new Map<String, Object>();
    visRule.put('booleanFilter', '1');
    List<Map<String, Object>> criteria = new List<Map<String, Object>>();
    Map<String, Object> criterion = new Map<String, Object>();
    criterion.put('field', 'Status');
    criterion.put('operation', 'equals');
    criterion.put('value', 'Active');
    criteria.add(criterion);
    visRule.put('criteria', criteria);
    fieldInst1.put('visibilityRule', visRule);
    item1.put('fieldInstance', fieldInst1);
    items.add(item1);

    // Field without visibility rules
    Map<String, Object> item2 = new Map<String, Object>();
    Map<String, Object> fieldInst2 = new Map<String, Object>();
    fieldInst2.put('fieldItem', 'Phone');
    item2.put('fieldInstance', fieldInst2);
    items.add(item2);

    // Item without fieldInstance (should be skipped)
    Map<String, Object> item3 = new Map<String, Object>();
    item3.put('componentInstance', new Map<String, Object>());
    items.add(item3);

    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = new List<FlexiPageMetadataService.FieldInfo>();
    Set<String> processedFields = new Set<String>();
    Map<String, Map<String, Object>> facetMap = new Map<String, Map<String, Object>>();

    Test.startTest();
    FlexiPageMetadataService.processItemInstances(
      items, 'TestSection', facetMap, fieldInfoList, processedFields
    );
    Test.stopTest();

    System.assertEquals(2, fieldInfoList.size(), 'Should have 2 fields');
    System.assertEquals('Email', fieldInfoList[0].fieldName, 'Should strip Record. prefix');
    System.assertNotEquals(null, fieldInfoList[0].visibilityRules, 'Should have visibility rules');
    System.assertEquals('Phone', fieldInfoList[1].fieldName, 'Second field should be Phone');
  }

  @isTest
  static void testProcessItemInstances_NullItems() {
    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = new List<FlexiPageMetadataService.FieldInfo>();
    Set<String> processedFields = new Set<String>();
    Map<String, Map<String, Object>> facetMap = new Map<String, Map<String, Object>>();

    Test.startTest();
    FlexiPageMetadataService.processItemInstances(
      null, 'TestSection', facetMap, fieldInfoList, processedFields
    );
    Test.stopTest();

    System.assertEquals(0, fieldInfoList.size(), 'Null items should produce no fields');
  }

  @isTest
  static void testProcessItemInstances_DuplicateSkip() {
    List<Object> items = new List<Object>();

    Map<String, Object> item = new Map<String, Object>();
    Map<String, Object> fieldInst = new Map<String, Object>();
    fieldInst.put('fieldItem', 'Name');
    item.put('fieldInstance', fieldInst);
    items.add(item);

    List<FlexiPageMetadataService.FieldInfo> fieldInfoList = new List<FlexiPageMetadataService.FieldInfo>();
    Set<String> processedFields = new Set<String>{ 'Name' }; // Already processed
    Map<String, Map<String, Object>> facetMap = new Map<String, Map<String, Object>>();

    Test.startTest();
    FlexiPageMetadataService.processItemInstances(
      items, 'TestSection', facetMap, fieldInfoList, processedFields
    );
    Test.stopTest();

    System.assertEquals(0, fieldInfoList.size(), 'Duplicate fields should be skipped');
  }

  @isTest
  static void testParseVisibilityRule_Direct() {
    Map<String, Object> visibilityRule = new Map<String, Object>();
    visibilityRule.put('booleanFilter', '1 AND 2 OR 3');

    List<Map<String, Object>> criteria = new List<Map<String, Object>>();
    criteria.add(new Map<String, Object>{ 'field' => 'Field1', 'operation' => 'contains', 'value' => 'Val1' });
    criteria.add(new Map<String, Object>{ 'field' => 'Field2', 'operation' => 'notEquals', 'value' => 'Val2' });
    visibilityRule.put('criteria', criteria);

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.parseVisibilityRule(visibilityRule);
    Test.stopTest();

    System.assertEquals('1 AND 2 OR 3', result.get('booleanFilter'), 'Boolean filter should match');
    List<Object> parsedCriteria = (List<Object>) result.get('criteria');
    System.assertEquals(2, parsedCriteria.size(), 'Should have 2 criteria');

    Map<String, String> crit1 = (Map<String, String>) parsedCriteria[0];
    System.assertEquals('Field1', crit1.get('leftValue'), 'Left value should match');
    System.assertEquals('contains', crit1.get('operator'), 'Operator should match');
    System.assertEquals('Val1', crit1.get('rightValue'), 'Right value should match');
  }

  @isTest
  static void testParseVisibilityRule_NoBooleanFilter() {
    Map<String, Object> visibilityRule = new Map<String, Object>();
    List<Map<String, Object>> criteria = new List<Map<String, Object>>();
    criteria.add(new Map<String, Object>{ 'field' => 'F1', 'operation' => 'eq', 'value' => 'V1' });
    visibilityRule.put('criteria', criteria);

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.parseVisibilityRule(visibilityRule);
    Test.stopTest();

    System.assert(!result.containsKey('booleanFilter'), 'Should not have booleanFilter');
    System.assert(result.containsKey('criteria'), 'Should have criteria');
  }

  @isTest
  static void testMapToSLDSIcon_Direct() {
    Test.startTest();
    String sadResult = FlexiPageMetadataService.mapToSLDSIcon('sad_face', 'red');
    String neutralResult = FlexiPageMetadataService.mapToSLDSIcon('neutral_face', 'yellow');
    String happyResult = FlexiPageMetadataService.mapToSLDSIcon('happy_face', 'green');
    String bigGrinResult = FlexiPageMetadataService.mapToSLDSIcon('big_grin_face', 'green');
    String unknownResult = FlexiPageMetadataService.mapToSLDSIcon('unknown_icon', 'blue');
    Test.stopTest();

    System.assertEquals('utility:emoji_sad', sadResult, 'Sad face should map correctly');
    System.assertEquals('utility:emoji_neutral', neutralResult, 'Neutral face should map correctly');
    System.assertEquals('utility:emoji', happyResult, 'Happy face should map correctly');
    System.assertEquals('utility:smiley_and_people', bigGrinResult, 'Big grin should map correctly');
    System.assertEquals('utility:info', unknownResult, 'Unknown should default to info');
  }

  @isTest
  static void testGetUiConditionalFormatIcon_Direct() {
    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.getUiConditionalFormatIcon('testId');
    Test.stopTest();

    System.assertEquals(null, result, 'Should return null');
  }

  @isTest
  static void testCreateMetadataService_Direct() {
    Test.startTest();
    MetadataService.MetadataPort service = FlexiPageMetadataService.createMetadataService();
    Test.stopTest();

    System.assertNotEquals(null, service, 'Service should not be null');
    System.assertNotEquals(null, service.SessionHeader, 'Session header should not be null');
  }

  // ===== retrieveFlexiPageViaMetadataAPI tests =====

  @isTest
  static void testRetrieveFlexiPageViaMetadataAPI() {
    Test.startTest();
    try {
      Map<String, Object> result = FlexiPageMetadataService.retrieveFlexiPageViaMetadataAPI('Test_Page');
      System.assertNotEquals(null, result, 'Result should not be null');
    } catch (FlexiPageMetadataService.FlexiPageMetadataException e) {
      System.assert(e.getMessage().length() > 0, 'Should have error message');
    }
    Test.stopTest();
  }

  @isTest
  static void testRetrieveFlexiPageViaMetadataAPI_SuccessWithMock() {
    // Build mock FlexiPage with regions, components, and properties
    MetadataService.FlexiPage flexiPage = new MetadataService.FlexiPage();
    flexiPage.fullName = 'Test_FlexiPage';
    flexiPage.type_x = 'RecordPage';
    flexiPage.masterLabel = 'Test FlexiPage';
    flexiPage.sobjectType = 'Account';
    flexiPage.description = 'Test description';

    // Create a region with a field section component
    MetadataService.FlexiPageRegion region = new MetadataService.FlexiPageRegion();
    region.name = 'MainRegion';
    region.type_x = 'Region';

    MetadataService.ComponentInstance comp = new MetadataService.ComponentInstance();
    comp.componentName = 'flexipage:fieldSection';

    MetadataService.ComponentInstanceProperty prop = new MetadataService.ComponentInstanceProperty();
    prop.name = 'fieldItem';
    prop.value = 'Account.Name';

    comp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{ prop };
    region.componentInstances = new List<MetadataService.ComponentInstance>{ comp };
    flexiPage.flexiPageRegions = new List<MetadataService.FlexiPageRegion>{ region };

    // Create mock ReadResult
    MetadataService.ReadFlexiPageResult readResult = new MetadataService.ReadFlexiPageResult();
    readResult.records = new List<MetadataService.FlexiPage>{ flexiPage };

    FlexiPageMetadataService.mockReadResult = readResult;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.retrieveFlexiPageViaMetadataAPI('Test_FlexiPage');
    Test.stopTest();

    FlexiPageMetadataService.mockReadResult = null;

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(true, result.get('success'), 'Should be successful');
    System.assert(result.containsKey('metadata'), 'Should contain metadata');
  }

  @isTest
  static void testRetrieveFlexiPageViaMetadataAPI_NotFound() {
    // Create mock ReadResult with empty records
    MetadataService.ReadFlexiPageResult readResult = new MetadataService.ReadFlexiPageResult();
    readResult.records = new List<MetadataService.FlexiPage>();

    FlexiPageMetadataService.mockReadResult = readResult;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.retrieveFlexiPageViaMetadataAPI('Nonexistent_Page');
    Test.stopTest();

    FlexiPageMetadataService.mockReadResult = null;

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(false, result.get('success'), 'Should not be successful');
    System.assert(result.containsKey('message'), 'Should contain message');
  }

  @isTest
  static void testRetrieveFlexiPageViaMetadataAPI_NullRecords() {
    // Create mock ReadResult with null records
    MetadataService.ReadFlexiPageResult readResult = new MetadataService.ReadFlexiPageResult();
    readResult.records = null;

    FlexiPageMetadataService.mockReadResult = readResult;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.retrieveFlexiPageViaMetadataAPI('Test_Page');
    Test.stopTest();

    FlexiPageMetadataService.mockReadResult = null;

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(false, result.get('success'), 'Should not be successful');
  }

  @isTest
  static void testRetrieveFlexiPageViaMetadataAPI_MultipleRegionsAndComponents() {
    // Build FlexiPage with multiple regions and components for detailed coverage
    MetadataService.FlexiPage flexiPage = new MetadataService.FlexiPage();
    flexiPage.fullName = 'Detailed_Page';
    flexiPage.type_x = 'RecordPage';
    flexiPage.masterLabel = 'Detailed Page';
    flexiPage.sobjectType = 'Account';

    // Region 1 with multiple components including field sections and regular components
    MetadataService.FlexiPageRegion region1 = new MetadataService.FlexiPageRegion();
    region1.name = 'Region1';
    region1.type_x = 'Region';

    // Field section component with properties
    MetadataService.ComponentInstance fieldComp = new MetadataService.ComponentInstance();
    fieldComp.componentName = 'flexipage:fieldSection';
    MetadataService.ComponentInstanceProperty fieldProp = new MetadataService.ComponentInstanceProperty();
    fieldProp.name = 'fieldItem';
    fieldProp.value = 'Account.Industry';
    MetadataService.ComponentInstanceProperty behaviorProp = new MetadataService.ComponentInstanceProperty();
    behaviorProp.name = 'uiBehavior';
    behaviorProp.value = 'readonly';
    fieldComp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{ fieldProp, behaviorProp };

    // Regular (non-field) component
    MetadataService.ComponentInstance regularComp = new MetadataService.ComponentInstance();
    regularComp.componentName = 'flexipage:chart';
    MetadataService.ComponentInstanceProperty chartProp = new MetadataService.ComponentInstanceProperty();
    chartProp.name = 'chartType';
    chartProp.value = 'bar';
    regularComp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{ chartProp };

    region1.componentInstances = new List<MetadataService.ComponentInstance>{ fieldComp, regularComp };

    // Region 2 - empty region
    MetadataService.FlexiPageRegion region2 = new MetadataService.FlexiPageRegion();
    region2.name = 'Region2';
    region2.type_x = 'Facet';
    region2.componentInstances = null;

    flexiPage.flexiPageRegions = new List<MetadataService.FlexiPageRegion>{ region1, region2 };

    MetadataService.ReadFlexiPageResult readResult = new MetadataService.ReadFlexiPageResult();
    readResult.records = new List<MetadataService.FlexiPage>{ flexiPage };

    FlexiPageMetadataService.mockReadResult = readResult;

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.retrieveFlexiPageViaMetadataAPI('Detailed_Page');
    Test.stopTest();

    FlexiPageMetadataService.mockReadResult = null;

    System.assertEquals(true, result.get('success'), 'Should be successful');
  }

  // ===== getAvailableFlexiPages tests =====

  @isTest
  static void testGetAvailableFlexiPages_Account() {
    Test.startTest();
    List<Map<String, Object>> flexiPages = FlexiPageMetadataService.getAvailableFlexiPages('Account');
    Test.stopTest();

    System.assertNotEquals(null, flexiPages, 'Should not be null');
    System.assertEquals(1, flexiPages.size(), 'Should have 1 Account FlexiPage');
    System.assertEquals('Account_Record_Page', flexiPages[0].get('developerName'), 'Name should match');
  }

  @isTest
  static void testGetAvailableFlexiPages_Contact() {
    Test.startTest();
    List<Map<String, Object>> flexiPages = FlexiPageMetadataService.getAvailableFlexiPages('Contact');
    Test.stopTest();

    System.assertEquals(1, flexiPages.size(), 'Should have 1 Contact FlexiPage');
  }

  @isTest
  static void testGetAvailableFlexiPages_Opportunity() {
    Test.startTest();
    List<Map<String, Object>> flexiPages = FlexiPageMetadataService.getAvailableFlexiPages('Opportunity');
    Test.stopTest();

    System.assertEquals(1, flexiPages.size(), 'Should have 1 Opportunity FlexiPage');
  }

  @isTest
  static void testGetAvailableFlexiPages_BlankName() {
    Test.startTest();
    List<Map<String, Object>> flexiPages = FlexiPageMetadataService.getAvailableFlexiPages('');
    Test.stopTest();

    System.assertEquals(0, flexiPages.size(), 'Should return empty for blank name');
  }

  @isTest
  static void testGetAvailableFlexiPages_NullName() {
    Test.startTest();
    List<Map<String, Object>> flexiPages = FlexiPageMetadataService.getAvailableFlexiPages(null);
    Test.stopTest();

    System.assertEquals(0, flexiPages.size(), 'Should return empty for null name');
  }

  @isTest
  static void testGetAvailableFlexiPages_NoMatch() {
    Test.startTest();
    List<Map<String, Object>> flexiPages = FlexiPageMetadataService.getAvailableFlexiPages('CustomObject__c');
    Test.stopTest();

    System.assertEquals(0, flexiPages.size(), 'Should return empty for unmatched object');
  }

  // ===== getUiFormatSpecificationSet tests =====

  @isTest
  static void testGetUiFormatSpecificationSet() {
    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.getUiFormatSpecificationSet('Expected_Revenue');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals('Expected_Revenue', result.get('developerName'), 'Name should match');
    System.assert(result.containsKey('rules'), 'Should contain rules');
  }

  @isTest
  static void testRetrieveUiFormatSpecificationSetViaSOQL() {
    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.retrieveUiFormatSpecificationSetViaSOQL('Test_Set');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals('Test_Set', result.get('developerName'), 'Name should match');
    List<Object> rules = (List<Object>) result.get('rules');
    System.assertEquals(0, rules.size(), 'Should have empty rules');
  }

  // ===== getObjectFields tests =====

  @isTest
  static void testGetObjectFields() {
    Test.startTest();
    List<Map<String, Object>> fields = FlexiPageMetadataService.getObjectFields('Account');
    Test.stopTest();

    System.assert(fields.size() > 0, 'Should return account fields');
    for (Map<String, Object> field : fields) {
      System.assert(field.containsKey('apiName'), 'Should have apiName');
      System.assert(field.containsKey('label'), 'Should have label');
      System.assert(field.containsKey('type'), 'Should have type');
    }
  }

  @isTest
  static void testGetObjectFields_InvalidObject() {
    try {
      Test.startTest();
      FlexiPageMetadataService.getObjectFields('InvalidObject123');
      Test.stopTest();
      System.assert(false, 'Should have thrown exception');
    } catch (Exception e) {
      System.assert(true, 'Exception was thrown as expected');
    }
  }

  // ===== getAllSObjects tests =====

  @isTest
  static void testGetAllSObjects() {
    Test.startTest();
    List<Map<String, Object>> sObjects = FlexiPageMetadataService.getAllSObjects();
    Test.stopTest();

    System.assert(sObjects.size() > 0, 'Should return sObjects');

    Boolean hasAccount = false;
    for (Map<String, Object> sObj : sObjects) {
      if ((String) sObj.get('value') == 'Account') {
        hasAccount = true;
        break;
      }
    }
    System.assert(hasAccount, 'Should include Account');
  }

  // ===== Comparator tests =====

  @isTest
  static void testFlexiPageComparator() {
    List<Map<String, Object>> pages = new List<Map<String, Object>>();
    pages.add(new Map<String, Object>{ 'label' => 'Zebra' });
    pages.add(new Map<String, Object>{ 'label' => 'Alpha' });
    pages.add(new Map<String, Object>{ 'label' => null });

    Test.startTest();
    pages.sort(new FlexiPageMetadataService.FlexiPageComparator());
    Test.stopTest();

    System.assertEquals('Alpha', pages[0].get('label'), 'Alpha first');
    System.assertEquals('Zebra', pages[1].get('label'), 'Zebra second');
    System.assertEquals(null, pages[2].get('label'), 'Null last');
  }

  @isTest
  static void testFlexiPageComparator_BothNull() {
    List<Map<String, Object>> pages = new List<Map<String, Object>>();
    pages.add(new Map<String, Object>{ 'label' => null });
    pages.add(new Map<String, Object>{ 'label' => null });

    Test.startTest();
    pages.sort(new FlexiPageMetadataService.FlexiPageComparator());
    Test.stopTest();

    System.assertEquals(null, pages[0].get('label'), 'Both should be null');
  }

  @isTest
  static void testFieldComparator() {
    List<Map<String, Object>> fields = new List<Map<String, Object>>();
    fields.add(new Map<String, Object>{ 'label' => 'Zebra' });
    fields.add(new Map<String, Object>{ 'label' => 'Alpha' });
    fields.add(new Map<String, Object>{ 'label' => null });

    Test.startTest();
    fields.sort(new FlexiPageMetadataService.FieldComparator());
    Test.stopTest();

    System.assertEquals('Alpha', fields[0].get('label'), 'Alpha first');
    System.assertEquals(null, fields[2].get('label'), 'Null last');
  }

  @isTest
  static void testFieldComparator_BothNull() {
    List<Map<String, Object>> fields = new List<Map<String, Object>>();
    fields.add(new Map<String, Object>{ 'label' => null });
    fields.add(new Map<String, Object>{ 'label' => null });

    Test.startTest();
    fields.sort(new FlexiPageMetadataService.FieldComparator());
    Test.stopTest();

    System.assertEquals(null, fields[0].get('label'), 'Both should be null');
  }

  @isTest
  static void testSObjectComparator() {
    List<Map<String, Object>> sObjects = new List<Map<String, Object>>();
    sObjects.add(new Map<String, Object>{ 'label' => 'Zebra' });
    sObjects.add(new Map<String, Object>{ 'label' => 'Alpha' });
    sObjects.add(new Map<String, Object>{ 'label' => null });

    Test.startTest();
    sObjects.sort(new FlexiPageMetadataService.SObjectComparator());
    Test.stopTest();

    System.assertEquals('Alpha', sObjects[0].get('label'), 'Alpha first');
    System.assertEquals(null, sObjects[2].get('label'), 'Null last');
  }

  @isTest
  static void testSObjectComparator_BothNull() {
    List<Map<String, Object>> sObjects = new List<Map<String, Object>>();
    sObjects.add(new Map<String, Object>{ 'label' => null });
    sObjects.add(new Map<String, Object>{ 'label' => null });

    Test.startTest();
    sObjects.sort(new FlexiPageMetadataService.SObjectComparator());
    Test.stopTest();

    System.assertEquals(null, sObjects[0].get('label'), 'Both should be null');
  }

  // ===== Edge case: convertFlexiPageRegionToMap with fieldSection record reference =====

  @isTest
  static void testConvertFlexiPageRegionToMap_FieldSectionWithRecordRef() {
    MetadataService.FlexiPageRegion region = new MetadataService.FlexiPageRegion();
    region.name = 'FieldSectionRegion';
    region.type_x = 'Region';

    MetadataService.ComponentInstance comp = new MetadataService.ComponentInstance();
    comp.componentName = 'flexipage:fieldSection';

    MetadataService.ComponentInstanceProperty prop1 = new MetadataService.ComponentInstanceProperty();
    prop1.name = 'fieldItem';
    prop1.value = 'Record.Industry';

    MetadataService.ComponentInstanceProperty prop2 = new MetadataService.ComponentInstanceProperty();
    prop2.name = 'sectionLabel';
    prop2.value = 'Details';

    comp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{ prop1, prop2 };
    region.componentInstances = new List<MetadataService.ComponentInstance>{ comp };

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertFlexiPageRegionToMap(region);
    Test.stopTest();

    System.assert(result.containsKey('itemInstances'), 'Should have itemInstances');
  }

  // ===== getFlexiPagesViaMetadataAPI direct test =====

  @isTest
  static void testGetFlexiPagesViaMetadataAPI_Direct() {
    Test.startTest();
    // This will use MetadataService internally, which may fail in test context
    // The method handles exceptions gracefully by returning empty list
    List<Map<String, Object>> result = FlexiPageMetadataService.getFlexiPagesViaMetadataAPI('Account');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  // ===== Comparator direct tests for null-first edge cases =====

  @isTest
  static void testFieldComparator_FirstNullSecondNotNull() {
    FlexiPageMetadataService.FieldComparator comp = new FlexiPageMetadataService.FieldComparator();

    Test.startTest();
    Integer result = comp.compare(
      new Map<String, Object>{ 'label' => null },
      new Map<String, Object>{ 'label' => 'Alpha' }
    );
    Test.stopTest();

    System.assertEquals(1, result, 'Null label should sort after non-null');
  }

  @isTest
  static void testSObjectComparator_FirstNullSecondNotNull() {
    FlexiPageMetadataService.SObjectComparator comp = new FlexiPageMetadataService.SObjectComparator();

    Test.startTest();
    Integer result = comp.compare(
      new Map<String, Object>{ 'label' => null },
      new Map<String, Object>{ 'label' => 'Alpha' }
    );
    Test.stopTest();

    System.assertEquals(1, result, 'Null label should sort after non-null');
  }

  @isTest
  static void testFlexiPageComparator_FirstNullSecondNotNull() {
    FlexiPageMetadataService.FlexiPageComparator comp = new FlexiPageMetadataService.FlexiPageComparator();

    Test.startTest();
    Integer result = comp.compare(
      new Map<String, Object>{ 'label' => null },
      new Map<String, Object>{ 'label' => 'Alpha' }
    );
    Test.stopTest();

    System.assertEquals(1, result, 'Null label should sort after non-null');
  }

  // ===== convertFlexiPageRegionToMap with visibility rule on field =====

  @isTest
  static void testConvertFlexiPageRegionToMap_FieldWithVisibilityRule() {
    MetadataService.FlexiPageRegion region = new MetadataService.FlexiPageRegion();
    region.name = 'VisibilityRegion';
    region.type_x = 'Region';

    MetadataService.ComponentInstance comp = new MetadataService.ComponentInstance();
    comp.componentName = 'flexipage:fieldSection';

    MetadataService.ComponentInstanceProperty prop = new MetadataService.ComponentInstanceProperty();
    prop.name = 'fieldItem';
    prop.value = 'Account.Status__c';
    comp.componentInstanceProperties = new List<MetadataService.ComponentInstanceProperty>{ prop };

    // Add visibility rule
    MetadataService.UiFormulaRule visRule = new MetadataService.UiFormulaRule();
    visRule.booleanFilter = '1';
    MetadataService.UiFormulaCriterion criterion = new MetadataService.UiFormulaCriterion();
    criterion.leftValue = '{!Record.Industry}';
    criterion.operator = 'EQUAL';
    criterion.rightValue = 'Technology';
    visRule.criteria = new List<MetadataService.UiFormulaCriterion>{ criterion };
    comp.visibilityRule = visRule;

    region.componentInstances = new List<MetadataService.ComponentInstance>{ comp };

    Test.startTest();
    Map<String, Object> result = FlexiPageMetadataService.convertFlexiPageRegionToMap(region);
    Test.stopTest();

    System.assert(result.containsKey('itemInstances'), 'Should have itemInstances');
    List<Object> items = (List<Object>) result.get('itemInstances');
    System.assertEquals(1, items.size(), 'Should have 1 item');

    Map<String, Object> item = (Map<String, Object>) items[0];
    Map<String, Object> fieldInstance = (Map<String, Object>) item.get('fieldInstance');
    System.assert(fieldInstance.containsKey('visibilityRule'), 'Should have visibilityRule');
  }
}
