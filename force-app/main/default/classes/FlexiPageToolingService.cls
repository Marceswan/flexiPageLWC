public class FlexiPageToolingService {

  /**
   * Retrieves the metadata for a specified FlexiPage based on its developer name.
   *
   * @param developerName The developer name of the FlexiPage to retrieve metadata for.
   * @return A JSON string representing the metadata of the specified FlexiPage.
   * @throws AuraHandledException if an error occurs while retrieving the metadata.
   */
  @AuraEnabled
  public static String getFlexiPageMetadata(String developerName) {
    try {
      // Call CacheService directly - returns raw FlexiPage Metadata JSON
      String cached = FlexiPageCacheService.getFlexiPageMetadata(developerName);

      // Check if cache service returned an error envelope
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(cached);
      if (parsed.containsKey('success') && parsed.get('success') == false) {
        String errorMsg = parsed.containsKey('error')
          ? (String) parsed.get('error')
          : 'Unknown error retrieving FlexiPage metadata';
        throw new AuraHandledException(errorMsg);
      }

      // Return the raw FlexiPage Metadata JSON (has flexiPageRegions at top level)
      return cached;
    } catch (AuraHandledException e) {
      throw e;
    } catch (Exception e) {
      throw new AuraHandledException(
        'Exception in getFlexiPageMetadata: ' + e.getMessage()
      );
    }
  }

  /**
   * Retrieves the field values for a specified record in a specified object.
   *
   * @param recordId The ID of the record to retrieve field values for.
   * @param objectApiName The API name of the object the record belongs to.
   * @return A Map of field API names to their corresponding values for the specified record.
   * @throws AuraHandledException if an error occurs while retrieving the field values.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getFieldValues(
    String recordId,
    String objectApiName,
    List<String> fieldApiNames
  ) {
    Map<String, Object> result = new Map<String, Object>();
    Map<String, Object> fieldValues = new Map<String, Object>();
    Map<String, Object> fieldMetadata = new Map<String, Object>();

    try {
      // Retrieve the schema for the specified object
      Schema.SObjectType sObjectType = Schema.getGlobalDescribe()
        .get(objectApiName);
      if (sObjectType == null) {
        throw new IllegalArgumentException(
          'Invalid object API name: ' + objectApiName
        );
      }

      // Get the field map for the object
      Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe()
        .fields.getMap();

      // Build list of fields to query (use provided list or all fields)
      Set<String> fieldsToQuery = new Set<String>();
      if (fieldApiNames != null && !fieldApiNames.isEmpty()) {
        // Normalize field names to lowercase for lookup
        for (String fieldName : fieldApiNames) {
          String normalizedName = fieldName.toLowerCase();
          if (fieldMap.containsKey(normalizedName)) {
            fieldsToQuery.add(normalizedName);
          }
        }

        // Always include system fields to ensure they're available
        Set<String> systemFields = new Set<String>{
          'createdbyid',
          'createddate',
          'lastmodifiedbyid',
          'lastmodifieddate',
          'systemmodstamp',
          'ownerid'
        };
        for (String sysField : systemFields) {
          if (
            fieldMap.containsKey(sysField) && !fieldsToQuery.contains(sysField)
          ) {
            fieldsToQuery.add(sysField);
          }
        }
      } else {
        fieldsToQuery.addAll(fieldMap.keySet());
      }

      // Construct the SOQL query
      String query =
        'SELECT ' +
        String.join(new List<String>(fieldsToQuery), ',') +
        ' FROM ' +
        objectApiName +
        ' WHERE Id = :recordId';

      // Execute the query
      SObject record = Database.query(query);

      // Populate field values and metadata
      for (String fieldApiName : fieldsToQuery) {
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldApiName)
          .getDescribe();

        // Get field value
        Object fieldValue = record.get(fieldApiName);
        fieldValues.put(fieldApiName, fieldValue);

        // Build field metadata
        Map<String, Object> fieldInfo = new Map<String, Object>();
        fieldInfo.put('label', fieldDescribe.getLabel());
        fieldInfo.put('type', String.valueOf(fieldDescribe.getType()));
        fieldInfo.put('isNameField', fieldDescribe.isNameField());

        // Debug logging for Owner field
        if (fieldApiName.equalsIgnoreCase('ownerid')) {
          System.debug('Processing OwnerId field:');
          System.debug('  - Field value: ' + fieldValue);
          System.debug('  - Field type: ' + fieldDescribe.getType());
        }

        // Add reference info for lookup fields
        if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
          List<Schema.SObjectType> referenceTypes = fieldDescribe.getReferenceTo();
          if (!referenceTypes.isEmpty()) {
            fieldInfo.put(
              'referenceObjectName',
              referenceTypes[0].getDescribe().getName()
            );

            // If we have a value, get the name field value for display
            if (fieldValue != null) {
              try {
                String refObjectName = referenceTypes[0]
                  .getDescribe()
                  .getName();
                String nameField = getNameField(refObjectName);

                // Special handling for User reference fields
                if (
                  fieldApiName.equalsIgnoreCase('ownerid') ||
                  fieldApiName.equalsIgnoreCase('createdbyid') ||
                  fieldApiName.equalsIgnoreCase('lastmodifiedbyid')
                ) {
                  String userId = String.valueOf(fieldValue);
                  if (fieldApiName.equalsIgnoreCase('ownerid')) {
                    // Owner can be User or Group
                    if (userId.startsWith('005')) {
                      // It's a User
                      String userQuery = 'SELECT Name FROM User WHERE Id = :fieldValue LIMIT 1';
                      List<User> users = Database.query(userQuery);
                      if (!users.isEmpty()) {
                        fieldInfo.put('referenceNameValue', users[0].Name);
                        System.debug('OwnerId User found: ' + users[0].Name);
                      } else {
                        System.debug(
                          'OwnerId User NOT found for ID: ' + fieldValue
                        );
                      }
                    } else if (userId.startsWith('00G')) {
                      // It's a Group (Queue)
                      String groupQuery = 'SELECT Name FROM Group WHERE Id = :fieldValue LIMIT 1';
                      List<Group> groups = Database.query(groupQuery);
                      if (!groups.isEmpty()) {
                        fieldInfo.put('referenceNameValue', groups[0].Name);
                      }
                    }
                  } else {
                    // CreatedById and LastModifiedById are always Users
                    String userQuery = 'SELECT Name FROM User WHERE Id = :fieldValue LIMIT 1';
                    List<User> users = Database.query(userQuery);
                    if (!users.isEmpty()) {
                      fieldInfo.put('referenceNameValue', users[0].Name);
                      System.debug('OwnerId User found: ' + users[0].Name);
                    } else {
                      System.debug(
                        'OwnerId User NOT found for ID: ' + fieldValue
                      );
                    }
                  }
                } else {
                  // Standard lookup handling
                  String refQuery =
                    'SELECT ' +
                    nameField +
                    ' FROM ' +
                    refObjectName +
                    ' WHERE Id = :fieldValue LIMIT 1';
                  List<SObject> refRecords = Database.query(refQuery);
                  if (!refRecords.isEmpty()) {
                    fieldInfo.put(
                      'referenceNameValue',
                      refRecords[0].get(nameField)
                    );
                  }
                }
              } catch (Exception e) {
                // If we can't get the reference name, just log and continue
                System.debug(
                  'Error getting reference name for field ' +
                    fieldApiName +
                    ': ' +
                    e.getMessage()
                );
              }
            }
          }
        }

        // Store metadata with lowercase key for consistent lookup
        fieldMetadata.put(fieldApiName.toLowerCase(), fieldInfo);
      }

      result.put('values', fieldValues);
      result.put('metadata', fieldMetadata);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving field values: ' + e.getMessage()
      );
    }

    return result;
  }

  /**
   * Get the name field for an object
   */
  private static String getNameField(String objectApiName) {
    Schema.SObjectType sObjectType = Schema.getGlobalDescribe()
      .get(objectApiName);
    if (sObjectType != null) {
      Map<String, Schema.SObjectField> fields = sObjectType.getDescribe()
        .fields.getMap();
      for (String fieldName : fields.keySet()) {
        if (fields.get(fieldName).getDescribe().isNameField()) {
          return fieldName;
        }
      }
    }
    return 'Name'; // Default fallback
  }

  /**
   * Retrieves the UiFormatSpecificationSet metadata for icon conditional formatting using Metadata API.
   *
   * @param developerName The developer name of the UiFormatSpecificationSet.
   * @return A Map containing the icon formatting rules.
   * @throws AuraHandledException if an error occurs while retrieving the metadata.
   */
  @AuraEnabled(cacheable=true)
  public static Map<String, Object> getUiFormatSpecificationSet(
    String developerName
  ) {
    try {
      // Use Metadata API service to retrieve UiFormatSpecificationSet
      return FlexiPageMetadataService.getUiFormatSpecificationSet(
        developerName
      );
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving UiFormatSpecificationSet: ' + e.getMessage()
      );
    }
  }

  /**
   * Retrieves available FlexiPages for a specified object.
   * Used by the Custom Property Editor to populate FlexiPage dropdown.
   *
   * @param objectApiName The API name of the object to find FlexiPages for.
   * @return A List of Maps containing FlexiPage information (developerName, label, description).
   * @throws AuraHandledException if an error occurs while retrieving the FlexiPages.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getAvailableFlexiPages(
    String objectApiName
  ) {
    List<Map<String, Object>> flexiPages = new List<Map<String, Object>>();

    try {
      // Use Metadata API service to get available FlexiPages
      return FlexiPageMetadataService.getAvailableFlexiPages(objectApiName);
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving FlexiPages: ' + e.getMessage()
      );
    }
  }

  /**
   * Retrieves field information for a specified object.
   * Used by the Custom Property Editor to populate field selection lists.
   *
   * @param objectApiName The API name of the object to retrieve fields for.
   * @return A List of Maps containing field information (apiName, label, type, required).
   * @throws AuraHandledException if an error occurs while retrieving the fields.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getObjectFields(
    String objectApiName
  ) {
    List<Map<String, Object>> fieldList = new List<Map<String, Object>>();

    try {
      Schema.SObjectType sObjectType = Schema.getGlobalDescribe()
        .get(objectApiName);
      if (sObjectType == null) {
        throw new IllegalArgumentException(
          'Invalid object API name: ' + objectApiName
        );
      }

      Map<String, Schema.SObjectField> fieldMap = sObjectType.getDescribe()
        .fields.getMap();

      for (String fieldName : fieldMap.keySet()) {
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName)
          .getDescribe();

        // Include only updateable or creatable fields
        if (fieldDescribe.isUpdateable() || fieldDescribe.isCreateable()) {
          fieldList.add(
            new Map<String, Object>{
              'apiName' => fieldDescribe.getName(),
              'label' => fieldDescribe.getLabel(),
              'type' => String.valueOf(fieldDescribe.getType()),
              'required' => fieldDescribe.isNillable() == false
            }
          );
        }
      }

      // Sort by label for better UX using a custom comparator
      fieldList.sort(new FieldComparator());
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving object fields: ' + e.getMessage()
      );
    }

    return fieldList;
  }

  /**
   * Retrieves all available sObjects in the org.
   * Used by the Custom Property Editor to populate the object selection dropdown.
   *
   * @return A List of Maps containing sObject information (value, label, isCustom).
   * @throws AuraHandledException if an error occurs while retrieving the sObjects.
   */
  @AuraEnabled(cacheable=true)
  public static List<Map<String, Object>> getAllSObjects() {
    List<Map<String, Object>> sObjectList = new List<Map<String, Object>>();

    try {
      Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

      for (String objectName : globalDescribe.keySet()) {
        Schema.DescribeSObjectResult describeResult = globalDescribe.get(
            objectName
          )
          .getDescribe();

        // Include only objects that support layouts and are accessible
        if (
          describeResult.isAccessible() &&
          describeResult.isQueryable() &&
          describeResult.isSearchable() &&
          !describeResult.isDeprecatedAndHidden()
        ) {
          Map<String, Object> sObjectInfo = new Map<String, Object>();
          sObjectInfo.put('value', describeResult.getName());
          sObjectInfo.put(
            'label',
            describeResult.getLabel() + ' (' + describeResult.getName() + ')'
          );
          sObjectInfo.put('isCustom', describeResult.isCustom());

          sObjectList.add(sObjectInfo);
        }
      }

      // Sort with standard objects first, then custom objects, alphabetically within each group
      sObjectList.sort(new SObjectComparator());
    } catch (Exception e) {
      throw new AuraHandledException(
        'Error retrieving sObjects: ' + e.getMessage()
      );
    }

    return sObjectList;
  }

  /**
   * Comparator class for sorting sObjects
   */
  public class SObjectComparator implements System.Comparator<Map<String, Object>> {
    public Integer compare(Map<String, Object> o1, Map<String, Object> o2) {
      Boolean isCustom1 = (Boolean) o1.get('isCustom');
      Boolean isCustom2 = (Boolean) o2.get('isCustom');
      String label1 = (String) o1.get('label');
      String label2 = (String) o2.get('label');

      // If one is custom and the other is not, standard objects come first
      if (isCustom1 != isCustom2) {
        return isCustom1 ? 1 : -1;
      }

      // Otherwise, sort alphabetically by label
      return label1.compareTo(label2);
    }
  }

  /**
   * Comparator class for sorting fields by label
   */
  public class FieldComparator implements System.Comparator<Map<String, Object>> {
    public Integer compare(Map<String, Object> f1, Map<String, Object> f2) {
      String label1 = (String) f1.get('label');
      String label2 = (String) f2.get('label');

      if (label1 == null && label2 == null)
        return 0;
      if (label1 == null)
        return 1;
      if (label2 == null)
        return -1;

      return label1.compareTo(label2);
    }
  }
}