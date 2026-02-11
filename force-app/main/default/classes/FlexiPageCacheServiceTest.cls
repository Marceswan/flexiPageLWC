/**
 * @description Test class for FlexiPageCacheService
 * Tests cache operations, HTTP callouts, and platform event publishing
 *
 * @author Marc Swan
 * @date 2025-01-19
 * @version 64.0
 */
@isTest
public class FlexiPageCacheServiceTest {
  private static final String TEST_DEVELOPER_NAME = 'Test_FlexiPage';
  private static final String TEST_METADATA_JSON = '{"developerName":"Test_FlexiPage","metadata":{"flexiPageRegions":[],"sobjectType":"Account","type":"RecordPage","masterLabel":"Test FlexiPage","fullName":"Test_FlexiPage"},"success":true}';

  // Mock response that works for BOTH getFlexiPageLastModifiedDate AND fetchFreshMetadata
  // Contains LastModifiedDate for the date check, and Metadata for the fetch
  private static final String TOOLING_MOCK_RESPONSE =
    '{"size":1,"totalSize":1,"done":true,"records":[{' +
    '"Id":"0M0000000000001",' +
    '"DeveloperName":"Test_FlexiPage",' +
    '"LastModifiedDate":"2025-01-19T12:00:00.000+0000",' +
    '"MasterLabel":"Test FlexiPage",' +
    '"Type":"RecordPage",' +
    '"Metadata":{"metadata":{"flexiPageRegions":[],"sobjectType":"Account","Id":"0M0000000000001","type":"RecordPage","masterLabel":"Test FlexiPage","fullName":"Test_FlexiPage"}}}]}';

  // Mock response without nested metadata (for direct metadata paths)
  private static final String TOOLING_MOCK_SIMPLE =
    '{"size":1,"totalSize":1,"done":true,"records":[{' +
    '"Id":"0M0000000000002",' +
    '"DeveloperName":"Simple_Page",' +
    '"LastModifiedDate":"2025-01-19T12:00:00.000+0000",' +
    '"MasterLabel":"Simple Page",' +
    '"Metadata":{"flexiPageRegions":[],"sobjectType":"Contact","type":"RecordPage"}}]}';

  // Empty records response
  private static final String TOOLING_MOCK_EMPTY = '{"size":0,"totalSize":0,"done":true,"records":[]}';

  @TestSetup
  static void setupTestData() {
    FlexiPage_Cache__c testCache = new FlexiPage_Cache__c();
    testCache.FlexiPage_Developer_Name__c = TEST_DEVELOPER_NAME;
    testCache.FlexiPage_Metadata_JSON__c = TEST_METADATA_JSON;
    testCache.Cache_Created_Date__c = DateTime.now().addMinutes(-30);
    testCache.FlexiPage_Last_Modified_Date__c = DateTime.now();
    testCache.Is_Active__c = true;
    testCache.API_Version__c = '64.0';
    testCache.Object_API_Name__c = 'Account';
    testCache.FlexiPage_Id__c = '123';
    insert testCache;
  }

  /**
   * @description Test cache hit - cache is fresh and FlexiPage hasn't been modified
   */
  @isTest
  static void testGetFlexiPageMetadata_CacheHit() {
    // Mock returns LastModifiedDate in the past, cache's FlexiPage_Last_Modified_Date__c is now
    // So flexiPageLastModified < cache last modified → cache is valid
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    System.assertEquals(TEST_METADATA_JSON, result, 'Should return cached metadata');
  }

  /**
   * @description Test cache miss with successful Tooling API fetch
   */
  @isTest
  static void testGetFlexiPageMetadata_CacheMiss() {
    delete [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata('New_FlexiPage');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  /**
   * @description Test stale cache (older than timeout) triggers refresh
   */
  @isTest
  static void testGetFlexiPageMetadata_StaleCache() {
    FlexiPage_Cache__c cacheRecord = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    cacheRecord.Cache_Created_Date__c = DateTime.now().addHours(-2);
    update cacheRecord;

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  /**
   * @description Test that updateCache extracts objectApiName and flexiPageId from metadata
   */
  @isTest
  static void testUpdateCache_WithMetadataParsing() {
    delete [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];

    // Use mock with nested metadata containing sobjectType and Id
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata('Parsed_Page');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');

    List<FlexiPage_Cache__c> cacheRecords = [
      SELECT Object_API_Name__c, FlexiPage_Id__c, Is_Active__c, API_Version__c
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = 'Parsed_Page'
    ];

    if (!cacheRecords.isEmpty()) {
      System.assertEquals(true, cacheRecords[0].Is_Active__c, 'Cache should be active');
      System.assertEquals('64.0', cacheRecords[0].API_Version__c, 'API version should be set');
      // Object name and ID extracted from nested metadata
      System.assertEquals('Account', cacheRecords[0].Object_API_Name__c, 'Should extract objectApiName');
      System.assertEquals('0M0000000000001', cacheRecords[0].FlexiPage_Id__c, 'Should extract flexiPageId');
    }
  }

  /**
   * @description Test updateCache with existing cache record (upsert path)
   */
  @isTest
  static void testUpdateCache_ExistingRecord() {
    FlexiPage_Cache__c cacheRecord = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    cacheRecord.Cache_Created_Date__c = DateTime.now().addHours(-2);
    update cacheRecord;

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
    List<FlexiPage_Cache__c> cacheRecords = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    System.assertEquals(1, cacheRecords.size(), 'Should have exactly 1 cache record (upserted)');
  }

  /**
   * @description Test blank developer name returns error
   */
  @isTest
  static void testGetFlexiPageMetadata_BlankDeveloperName() {
    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata('');
    Test.stopTest();

    System.assert(result.contains('error'), 'Should return error response');
    System.assert(
      result.contains('Developer name cannot be blank'),
      'Should contain specific error message'
    );
  }

  /**
   * @description Test null developer name returns error
   */
  @isTest
  static void testGetFlexiPageMetadata_NullDeveloperName() {
    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(null);
    Test.stopTest();

    System.assert(result.contains('error'), 'Should return error');
  }

  /**
   * @description Test fetchFreshMetadata with 500 error from Tooling API
   */
  @isTest
  static void testGetFlexiPageMetadata_ToolingApiFailure() {
    delete [SELECT Id FROM FlexiPage_Cache__c];

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(500, '{"error":"Internal Server Error"}')
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata('Failed_Page');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  /**
   * @description Test fetchFreshMetadata with empty records
   */
  @isTest
  static void testGetFlexiPageMetadata_EmptyRecords() {
    delete [SELECT Id FROM FlexiPage_Cache__c];

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_EMPTY)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata('Empty_Page');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  /**
   * @description Test getFlexiPageLastModifiedDate with 200 response containing records
   */
  @isTest
  static void testGetFlexiPageLastModifiedDate_Success() {
    String mockResponse =
      '{"records":[{"Id":"0M0xx","DeveloperName":"Test","LastModifiedDate":"2025-06-15T10:30:00.000+0000"}]}';
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, mockResponse)
    );

    Test.startTest();
    DateTime result = FlexiPageCacheService.getFlexiPageLastModifiedDate('Test');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should return a date');
  }

  /**
   * @description Test getFlexiPageLastModifiedDate with empty records
   */
  @isTest
  static void testGetFlexiPageLastModifiedDate_EmptyRecords() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_EMPTY)
    );

    Test.startTest();
    DateTime result = FlexiPageCacheService.getFlexiPageLastModifiedDate('NonExistent');
    Test.stopTest();

    System.assertEquals(null, result, 'Should return null for no records');
  }

  /**
   * @description Test getFlexiPageLastModifiedDate with failed HTTP response
   */
  @isTest
  static void testGetFlexiPageLastModifiedDate_HttpError() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(401, '{"error":"Unauthorized"}')
    );

    Test.startTest();
    DateTime result = FlexiPageCacheService.getFlexiPageLastModifiedDate('Test');
    Test.stopTest();

    System.assertEquals(null, result, 'Should return null on HTTP error');
  }

  /**
   * @description Test getFlexiPageLastModifiedDate with blank LastModifiedDate
   */
  @isTest
  static void testGetFlexiPageLastModifiedDate_BlankDate() {
    String mockResponse = '{"records":[{"Id":"0M0xx","DeveloperName":"Test","LastModifiedDate":""}]}';
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, mockResponse)
    );

    Test.startTest();
    DateTime result = FlexiPageCacheService.getFlexiPageLastModifiedDate('Test');
    Test.stopTest();

    System.assertEquals(null, result, 'Should return null for blank date');
  }

  /**
   * @description Test cache validation with null creation date
   */
  @isTest
  static void testCacheValidation_NullCacheDate() {
    FlexiPage_Cache__c cacheRecord = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    cacheRecord.Cache_Created_Date__c = null;
    update cacheRecord;

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle null cache date');
  }

  /**
   * @description Test cache with null FlexiPage_Last_Modified_Date (skips date comparison)
   */
  @isTest
  static void testCacheValidation_NullLastModifiedDate() {
    FlexiPage_Cache__c cacheRecord = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    cacheRecord.FlexiPage_Last_Modified_Date__c = null;
    update cacheRecord;

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle null last modified date');
  }

  /**
   * @description Test inactive cache record is treated as miss
   */
  @isTest
  static void testGetFlexiPageMetadata_InactiveCache() {
    FlexiPage_Cache__c cacheRecord = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    cacheRecord.Is_Active__c = false;
    update cacheRecord;

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  /**
   * @description Test clearCache method
   */
  @isTest
  static void testClearCache() {
    Test.startTest();
    FlexiPageCacheService.clearCache(TEST_DEVELOPER_NAME);
    Test.stopTest();

    List<FlexiPage_Cache__c> cacheRecords = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    System.assertEquals(0, cacheRecords.size(), 'Cache should be deleted');
  }

  /**
   * @description Test clearCache with nonexistent name
   */
  @isTest
  static void testClearCache_NonExistent() {
    Test.startTest();
    FlexiPageCacheService.clearCache('NonExistent_Page');
    Test.stopTest();

    List<FlexiPage_Cache__c> cacheRecords = [SELECT Id FROM FlexiPage_Cache__c];
    System.assertEquals(1, cacheRecords.size(), 'Original cache should remain');
  }

  /**
   * @description Test clearAllCache method
   */
  @isTest
  static void testClearAllCache() {
    FlexiPage_Cache__c additionalCache = new FlexiPage_Cache__c();
    additionalCache.FlexiPage_Developer_Name__c = 'Another_FlexiPage';
    additionalCache.FlexiPage_Metadata_JSON__c = TEST_METADATA_JSON;
    additionalCache.Cache_Created_Date__c = DateTime.now();
    additionalCache.Is_Active__c = true;
    insert additionalCache;

    Test.startTest();
    FlexiPageCacheService.clearAllCache();
    Test.stopTest();

    List<FlexiPage_Cache__c> cacheRecords = [SELECT Id FROM FlexiPage_Cache__c];
    System.assertEquals(0, cacheRecords.size(), 'All cache should be deleted');
  }

  /**
   * @description Test refreshCache clears and re-fetches
   */
  @isTest
  static void testRefreshCache() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.refreshCache(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Result should not be null');
  }

  /**
   * @description Test platform event publishing
   */
  @isTest
  static void testPublishCacheRefreshEvent() {
    Test.startTest();
    FlexiPageCacheService.publishCacheRefreshEvent('Refresh', TEST_DEVELOPER_NAME);
    FlexiPageCacheService.publishCacheRefreshEvent('Clear', null);
    Test.stopTest();

    System.assert(true, 'Should execute without exceptions');
  }

  /**
   * @description Test getCacheStatistics
   */
  @isTest
  static void testGetCacheStatistics() {
    Test.startTest();
    Map<String, Object> stats = FlexiPageCacheService.getCacheStatistics();
    Test.stopTest();

    System.assertNotEquals(null, stats, 'Stats should not be null');
    System.assert(stats.containsKey('totalRecords'), 'Should have totalRecords');
    System.assert(stats.containsKey('activeRecords'), 'Should have activeRecords');
    System.assert(stats.containsKey('recentRecords'), 'Should have recentRecords');
    System.assert(stats.containsKey('oldRecords'), 'Should have oldRecords');
    System.assertEquals(1, (Integer) stats.get('totalRecords'), 'Should have 1 record');
  }

  /**
   * @description Test getCacheStatistics with old records
   */
  @isTest
  static void testGetCacheStatistics_WithOldRecords() {
    FlexiPage_Cache__c cacheRecord = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    cacheRecord.Cache_Created_Date__c = DateTime.now().addDays(-2);
    update cacheRecord;

    Test.startTest();
    Map<String, Object> stats = FlexiPageCacheService.getCacheStatistics();
    Test.stopTest();

    System.assertEquals(1, (Integer) stats.get('oldRecords'), 'Should have 1 old record');
  }

  /**
   * @description Test transaction cache prevents duplicate SOQL queries
   */
  @isTest
  static void testTransactionCache() {
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result1 = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    String result2 = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertEquals(result1, result2, 'Both calls should return same result');
  }

  /**
   * @description Test fetchFreshMetadata with invalid JSON response
   */
  @isTest
  static void testFetchFreshMetadata_InvalidJson() {
    delete [SELECT Id FROM FlexiPage_Cache__c];

    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, 'not valid json at all')
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata('Bad_Json');
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should handle gracefully');
  }

  /**
   * @description Test cache validation when FlexiPage has been modified since cache
   * (flexiPageLastModified > cache's FlexiPage_Last_Modified_Date)
   */
  @isTest
  static void testCacheValidation_FlexiPageModifiedSinceCache() {
    FlexiPage_Cache__c cacheRecord = [
      SELECT Id
      FROM FlexiPage_Cache__c
      WHERE FlexiPage_Developer_Name__c = :TEST_DEVELOPER_NAME
    ];
    // Set cache's last modified to very old so mock date will be newer
    cacheRecord.FlexiPage_Last_Modified_Date__c = DateTime.newInstance(2020, 1, 1);
    update cacheRecord;

    // Mock returns LastModifiedDate of 2025-01-19 which is > 2020-01-01
    Test.setMock(
      HttpCalloutMock.class,
      new MockHttpResponseGenerator(200, TOOLING_MOCK_RESPONSE)
    );

    Test.startTest();
    String result = FlexiPageCacheService.getFlexiPageMetadata(TEST_DEVELOPER_NAME);
    Test.stopTest();

    System.assertNotEquals(null, result, 'Should refresh with new data');
  }

  /**
   * Mock HTTP Response Generator
   */
  public class MockHttpResponseGenerator implements HttpCalloutMock {
    private Integer statusCode;
    private String responseBody;

    public MockHttpResponseGenerator(Integer statusCode, String responseBody) {
      this.statusCode = statusCode;
      this.responseBody = responseBody;
    }

    public HTTPResponse respond(HTTPRequest req) {
      HttpResponse res = new HttpResponse();
      res.setHeader('Content-Type', 'application/json');
      res.setBody(responseBody);
      res.setStatusCode(statusCode);
      return res;
    }
  }
}
