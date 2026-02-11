/**
 * @description Service class for caching FlexiPage metadata to improve performance
 * and reduce Tooling API callouts. Uses custom object storage with Platform Events
 * for cache invalidation and refresh management.
 *
 * Features:
 * - Cache storage in FlexiPage_Cache__c custom object
 * - Staleness checking via Tooling API LastModifiedDate comparison
 * - Platform Event-driven cache refresh/invalidation
 * - Fallback to existing FlexiPageMetadataService when cache miss
 *
 * @author Marc Swan
 * @date 2025-01-19
 * @version 64.0
 */
public with sharing class FlexiPageCacheService {
  // Cache timeout in minutes - configurable via custom settings
  private static final Integer DEFAULT_CACHE_TIMEOUT_MINUTES = 60;

  // Tooling API endpoint for FlexiPage LastModifiedDate checks
  private static final String TOOLING_API_FLEXIPAGE_ENDPOINT = '/services/data/v64.0/tooling/query/';

  // Static cache to prevent duplicate SOQL queries in same transaction
  private static Map<String, FlexiPage_Cache__c> transactionCache = new Map<String, FlexiPage_Cache__c>();

  /**
   * @description Gets a valid API session ID using Visualforce page workaround.
   * Lightning sessions are restricted and can't make API callouts to the same org.
   * This retrieves a full API-capable session ID via a VF page.
   * In test context, uses UserInfo.getSessionId() since HTTP mocks don't validate tokens.
   * @return A valid session ID for API callouts
   */
  private static String getApiSessionId() {
    if (Test.isRunningTest()) {
      return UserInfo.getSessionId();
    }
    return Page.SessionIdProvider.getContent().toString().trim();
  }

  /**
   * @description Main entry point for retrieving FlexiPage metadata with caching
   * Checks cache first, validates staleness, and refreshes if needed
   * @param developerName The developer name of the FlexiPage
   * @return JSON string containing FlexiPage metadata
   */
  @AuraEnabled(cacheable=true)
  public static String getFlexiPageMetadata(String developerName) {
    try {
      System.debug(
        'FlexiPageCacheService.getFlexiPageMetadata called for: ' +
        developerName
      );

      // Validate input
      if (String.isBlank(developerName)) {
        return createErrorResponse('Developer name cannot be blank');
      }

      // Check if cache exists and is valid
      FlexiPage_Cache__c cacheRecord = getCacheRecord(developerName);

      if (cacheRecord != null && isCacheValid(cacheRecord)) {
        System.debug(
          'Cache hit - returning cached metadata for: ' + developerName
        );
        return cacheRecord.FlexiPage_Metadata_JSON__c;
      }

      // Cache miss or stale - fetch fresh data
      System.debug(
        'Cache miss or stale - fetching fresh metadata for: ' + developerName
      );
      String freshMetadata = fetchFreshMetadata(developerName);

      if (freshMetadata != null) {
        // Update cache with fresh data
        updateCache(developerName, freshMetadata);
        return freshMetadata;
      }

      // If all else fails, return error
      return createErrorResponse(
        'Unable to retrieve FlexiPage metadata for: ' + developerName
      );
    } catch (Exception e) {
      System.debug(
        'Error in FlexiPageCacheService.getFlexiPageMetadata: ' + e.getMessage()
      );
      System.debug('Stack trace: ' + e.getStackTraceString());
      return createErrorResponse(
        'Error retrieving FlexiPage metadata: ' + e.getMessage()
      );
    }
  }

  /**
   * @description Retrieves cache record for a given FlexiPage developer name
   * @param developerName The developer name to search for
   * @return FlexiPage_Cache__c record or null if not found
   */
  private static FlexiPage_Cache__c getCacheRecord(String developerName) {
    try {
      // Check transaction cache first
      if (transactionCache.containsKey(developerName)) {
        System.debug('Transaction cache hit for: ' + developerName);
        return transactionCache.get(developerName);
      }

      // Query from database
      List<FlexiPage_Cache__c> cacheRecords = [
        SELECT
          Id,
          FlexiPage_Developer_Name__c,
          FlexiPage_Metadata_JSON__c,
          FlexiPage_Last_Modified_Date__c,
          Cache_Created_Date__c,
          Object_API_Name__c,
          Is_Active__c,
          FlexiPage_Id__c,
          API_Version__c
        FROM FlexiPage_Cache__c
        WHERE
          FlexiPage_Developer_Name__c = :developerName
          AND Is_Active__c = TRUE
        LIMIT 1
      ];

      FlexiPage_Cache__c result = cacheRecords.isEmpty()
        ? null
        : cacheRecords[0];

      // Store in transaction cache (even if null to prevent re-querying)
      transactionCache.put(developerName, result);

      return result;
    } catch (Exception e) {
      System.debug('Error retrieving cache record: ' + e.getMessage());
      return null;
    }
  }

  /**
   * @description Validates if cache record is still valid (not stale)
   * Checks cache age and compares with FlexiPage LastModifiedDate via Tooling API
   * @param cacheRecord The cache record to validate
   * @return True if cache is valid, false if stale
   */
  private static Boolean isCacheValid(FlexiPage_Cache__c cacheRecord) {
    try {
      // Check cache age first
      if (cacheRecord.Cache_Created_Date__c == null) {
        System.debug('Cache record has no creation date - treating as invalid');
        return false;
      }

      DateTime cacheCreated = cacheRecord.Cache_Created_Date__c;
      DateTime now = DateTime.now();
      Integer ageInMinutes = (Integer) ((now.getTime() -
      cacheCreated.getTime()) / (1000 * 60));

      System.debug('Cache age: ' + ageInMinutes + ' minutes');

      // If cache is older than timeout, it's stale
      Integer timeoutMinutes = getCacheTimeoutMinutes();
      if (ageInMinutes > timeoutMinutes) {
        System.debug(
          'Cache is older than timeout (' +
            timeoutMinutes +
            ' minutes) - treating as stale'
        );
        return false;
      }

      // Check FlexiPage LastModifiedDate via Tooling API
      DateTime flexiPageLastModified = getFlexiPageLastModifiedDate(
        cacheRecord.FlexiPage_Developer_Name__c
      );

      if (
        flexiPageLastModified != null &&
        cacheRecord.FlexiPage_Last_Modified_Date__c != null
      ) {
        if (
          flexiPageLastModified > cacheRecord.FlexiPage_Last_Modified_Date__c
        ) {
          System.debug(
            'FlexiPage has been modified since cache - treating as stale'
          );
          return false;
        }
      }

      System.debug('Cache is valid');
      return true;
    } catch (Exception e) {
      System.debug('Error validating cache: ' + e.getMessage());
      // If we can't validate, treat as invalid to be safe
      return false;
    }
  }

  /**
   * @description Gets FlexiPage LastModifiedDate from Tooling API
   * @param developerName The FlexiPage developer name
   * @return DateTime of last modification, or null if not found
   */
  @TestVisible
  private static DateTime getFlexiPageLastModifiedDate(String developerName) {
    try {
      String query =
        'SELECT Id, DeveloperName, LastModifiedDate ' +
        'FROM FlexiPage WHERE DeveloperName = \'' +
        String.escapeSingleQuotes(developerName) +
        '\' LIMIT 1';

      String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
      String endpoint = TOOLING_API_FLEXIPAGE_ENDPOINT + '?q=' + encodedQuery;

      HttpRequest req = new HttpRequest();
      req.setEndpoint(URL.getOrgDomainUrl().toExternalForm() + endpoint);
      req.setMethod('GET');
      req.setHeader('Authorization', 'Bearer ' + getApiSessionId());
      req.setHeader('Content-Type', 'application/json');

      Http h = new Http();
      HttpResponse res = h.send(req);

      if (res.getStatusCode() == 200) {
        Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
          res.getBody()
        );
        List<Object> records = (List<Object>) responseMap.get('records');

        if (records != null && !records.isEmpty()) {
          Map<String, Object> record = (Map<String, Object>) records[0];
          String lastModifiedStr = (String) record.get('LastModifiedDate');

          if (String.isNotBlank(lastModifiedStr)) {
            return DateTime.valueOf(
              lastModifiedStr.replace('T', ' ').substring(0, 19)
            );
          }
        }
      } else {
        System.debug(
          'Tooling API request failed with status: ' +
            res.getStatusCode() +
            ' - ' +
            res.getBody()
        );
      }
    } catch (Exception e) {
      System.debug(
        'Error getting FlexiPage LastModifiedDate: ' + e.getMessage()
      );
    }

    return null;
  }

  /**
   * @description Fetches fresh metadata directly using Tooling API
   * @param developerName The FlexiPage developer name
   * @return Fresh metadata JSON string
   */
  private static String fetchFreshMetadata(String developerName) {
    // Use Tooling API directly to avoid circular dependency
    String query =
      'SELECT Id, DeveloperName, MasterLabel, Type, Description, ' +
      'EntityDefinitionId, NamespacePrefix, Metadata ' +
      'FROM FlexiPage WHERE DeveloperName = \'' +
      String.escapeSingleQuotes(developerName) +
      '\' LIMIT 1';

    String encodedQuery = EncodingUtil.urlEncode(query, 'UTF-8');
    String endpoint = TOOLING_API_FLEXIPAGE_ENDPOINT + '?q=' + encodedQuery;
    String fullEndpoint =
      URL.getOrgDomainUrl().toExternalForm() + endpoint;

    HttpRequest req = new HttpRequest();
    req.setEndpoint(fullEndpoint);
    req.setMethod('GET');
    req.setHeader('Authorization', 'Bearer ' + getApiSessionId());
    req.setHeader('Content-Type', 'application/json');

    Http h = new Http();
    HttpResponse res = h.send(req);

    if (res.getStatusCode() == 200) {
      Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
        res.getBody()
      );
      List<Object> records = (List<Object>) responseMap.get('records');

      if (records != null && !records.isEmpty()) {
        Map<String, Object> record = (Map<String, Object>) records[0];
        // Return the metadata directly from Tooling API
        return JSON.serialize(record.get('Metadata'));
      }

      throw new FlexiPageCacheException(
        'FlexiPage \'' +
          developerName +
          '\' not found via Tooling API. Verify the developer name is correct.'
      );
    }

    throw new FlexiPageCacheException(
      'Tooling API returned HTTP ' +
        res.getStatusCode() +
        '. Endpoint: ' +
        fullEndpoint +
        '. Check that a Remote Site Setting exists for your org domain.'
    );
  }

  public class FlexiPageCacheException extends Exception {
  }

  /**
   * @description Updates cache with fresh metadata
   * @param developerName The FlexiPage developer name
   * @param metadataJson The fresh metadata JSON
   */
  private static void updateCache(String developerName, String metadataJson) {
    try {
      // Parse metadata to extract object name and FlexiPage ID if available
      Map<String, Object> metadata = parseMetadataForCacheInfo(metadataJson);

      // Get existing cache record or create new one
      FlexiPage_Cache__c cacheRecord = getCacheRecord(developerName);

      if (cacheRecord == null) {
        cacheRecord = new FlexiPage_Cache__c();
        cacheRecord.FlexiPage_Developer_Name__c = developerName;
      }

      // Update cache record
      cacheRecord.FlexiPage_Metadata_JSON__c = metadataJson;
      cacheRecord.Cache_Created_Date__c = DateTime.now();
      cacheRecord.FlexiPage_Last_Modified_Date__c = getFlexiPageLastModifiedDate(
        developerName
      );
      cacheRecord.Is_Active__c = true;
      cacheRecord.API_Version__c = '64.0';

      // Set object API name if available in metadata
      if (metadata.containsKey('objectApiName')) {
        cacheRecord.Object_API_Name__c = (String) metadata.get('objectApiName');
      }

      // Set FlexiPage ID if available
      if (metadata.containsKey('flexiPageId')) {
        cacheRecord.FlexiPage_Id__c = (String) metadata.get('flexiPageId');
      }

      upsert cacheRecord FlexiPage_Developer_Name__c;

      // Update transaction cache
      transactionCache.put(developerName, cacheRecord);

      System.debug('Cache updated successfully for: ' + developerName);
    } catch (Exception e) {
      System.debug('Error updating cache: ' + e.getMessage());
      // Don't throw exception - cache update failure shouldn't break the main flow
    }
  }

  /**
   * @description Parses metadata JSON to extract cache-relevant information
   * @param metadataJson The metadata JSON string
   * @return Map containing extracted information
   */
  private static Map<String, Object> parseMetadataForCacheInfo(
    String metadataJson
  ) {
    Map<String, Object> result = new Map<String, Object>();

    try {
      Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(
        metadataJson
      );

      if (responseMap.containsKey('metadata')) {
        Map<String, Object> metadata = (Map<String, Object>) responseMap.get(
          'metadata'
        );

        if (metadata.containsKey('sobjectType')) {
          result.put('objectApiName', metadata.get('sobjectType'));
        }

        if (metadata.containsKey('Id')) {
          result.put('flexiPageId', metadata.get('Id'));
        }
      }
    } catch (Exception e) {
      System.debug('Error parsing metadata for cache info: ' + e.getMessage());
    }

    return result;
  }

  /**
   * @description Gets cache timeout in minutes from custom settings or default
   * @return Cache timeout in minutes
   */
  private static Integer getCacheTimeoutMinutes() {
    try {
      // Try to get from custom settings (you can implement this later)
      // For now, return default
      return DEFAULT_CACHE_TIMEOUT_MINUTES;
    } catch (Exception e) {
      System.debug(
        'Error getting cache timeout, using default: ' + e.getMessage()
      );
      return DEFAULT_CACHE_TIMEOUT_MINUTES;
    }
  }

  /**
   * @description Creates standardized error response
   * @param errorMessage The error message
   * @return JSON error response string
   */
  private static String createErrorResponse(String errorMessage) {
    Map<String, Object> errorResponse = new Map<String, Object>();
    errorResponse.put('success', false);
    errorResponse.put('error', errorMessage);
    return JSON.serialize(errorResponse);
  }

  /**
   * @description Clears cache for a specific FlexiPage
   * @param developerName The FlexiPage developer name
   */
  public static void clearCache(String developerName) {
    try {
      List<FlexiPage_Cache__c> cacheRecords = [
        SELECT Id
        FROM FlexiPage_Cache__c
        WHERE FlexiPage_Developer_Name__c = :developerName
      ];

      if (!cacheRecords.isEmpty()) {
        delete cacheRecords;
        System.debug('Cache cleared for: ' + developerName);
      }

      // Clear from transaction cache
      transactionCache.remove(developerName);
    } catch (Exception e) {
      System.debug('Error clearing cache: ' + e.getMessage());
    }
  }

  /**
   * @description Clears all FlexiPage cache records
   */
  public static void clearAllCache() {
    try {
      List<FlexiPage_Cache__c> allCacheRecords = [
        SELECT Id
        FROM FlexiPage_Cache__c
      ];

      if (!allCacheRecords.isEmpty()) {
        delete allCacheRecords;
        System.debug(
          'All cache cleared. Records deleted: ' + allCacheRecords.size()
        );
      }

      // Clear transaction cache
      transactionCache.clear();
    } catch (Exception e) {
      System.debug('Error clearing all cache: ' + e.getMessage());
    }
  }

  /**
   * @description Refreshes cache for a specific FlexiPage by clearing and refetching
   * @param developerName The FlexiPage developer name
   * @return Fresh metadata JSON string
   */
  public static String refreshCache(String developerName) {
    try {
      // Clear existing cache
      clearCache(developerName);

      // Fetch fresh metadata (which will automatically update cache)
      return getFlexiPageMetadata(developerName);
    } catch (Exception e) {
      System.debug('Error refreshing cache: ' + e.getMessage());
      return createErrorResponse('Error refreshing cache: ' + e.getMessage());
    }
  }

  /**
   * @description Publishes Platform Event for cache operations
   * @param action The action to perform (Refresh, Clear, RefreshAll)
   * @param developerName The FlexiPage developer name (optional for RefreshAll)
   */
  public static void publishCacheRefreshEvent(
    String action,
    String developerName
  ) {
    try {
      FlexiPage_Cache_Refresh__e event = new FlexiPage_Cache_Refresh__e();
      event.Action__c = action;
      event.FlexiPage_Developer_Name__c = developerName;
      event.Performed_By_User_Id__c = UserInfo.getUserId();

      EventBus.publish(event);

      System.debug(
        'Cache refresh event published - Action: ' +
          action +
          ', FlexiPage: ' +
          developerName
      );
    } catch (Exception e) {
      System.debug('Error publishing cache refresh event: ' + e.getMessage());
    }
  }

  /**
   * @description Gets cache statistics for monitoring
   * @return Map containing cache statistics
   */
  @AuraEnabled
  public static Map<String, Object> getCacheStatistics() {
    Map<String, Object> stats = new Map<String, Object>();

    try {
      // Total cache records
      Integer totalRecords = [SELECT COUNT() FROM FlexiPage_Cache__c];
      stats.put('totalRecords', totalRecords);

      // Active cache records
      Integer activeRecords = [
        SELECT COUNT()
        FROM FlexiPage_Cache__c
        WHERE Is_Active__c = TRUE
      ];
      stats.put('activeRecords', activeRecords);

      // Records by age
      DateTime oneHourAgo = DateTime.now().addHours(-1);
      DateTime oneDayAgo = DateTime.now().addDays(-1);

      Integer recentRecords = [
        SELECT COUNT()
        FROM FlexiPage_Cache__c
        WHERE Cache_Created_Date__c >= :oneHourAgo
      ];
      stats.put('recentRecords', recentRecords);

      Integer oldRecords = [
        SELECT COUNT()
        FROM FlexiPage_Cache__c
        WHERE Cache_Created_Date__c < :oneDayAgo
      ];
      stats.put('oldRecords', oldRecords);
    } catch (Exception e) {
      System.debug('Error getting cache statistics: ' + e.getMessage());
      stats.put('error', e.getMessage());
    }

    return stats;
  }
}