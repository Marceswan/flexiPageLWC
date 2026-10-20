public with sharing class FlexiPageToolingService {
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
      Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(
        cached
      );
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
          if (String.isNotBlank(fieldName)) {
            // FlexiPage items use Record.<path>; accept the prefix
            fieldsToQuery.add(
              fieldName.trim().toLowerCase().removeStart('record.')
            );
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

      // Resolve every segment from describe metadata; never interpolate unvalidated paths.
      Map<String, ResolvedFieldPath> resolvedPaths = new Map<String, ResolvedFieldPath>();
      for (String fieldPath : fieldsToQuery) {
        ResolvedFieldPath resolved = resolveFieldPath(sObjectType, fieldPath);
        if (resolved != null) {
          resolvedPaths.put(fieldPath, resolved);
        }
      }
      fieldsToQuery = resolvedPaths.keySet();
      Set<String> queryFields = new Set<String>();
      for (ResolvedFieldPath resolved : resolvedPaths.values()) {
        queryFields.add(resolved.queryPath);
        if (resolved.referenceNamePath != null) {
          queryFields.add(resolved.referenceNamePath);
        }
      }
      queryFields.add('Id');

      // Construct the SOQL query
      String query =
        'SELECT ' +
        String.join(new List<String>(queryFields), ',') +
        ' FROM ' +
        sObjectType.getDescribe().getName() +
        ' WHERE Id = :recordId WITH USER_MODE';

      // Execute the query
      SObject record = Database.query(query);

      // Populate field values and metadata
      for (String fieldApiName : fieldsToQuery) {
        ResolvedFieldPath resolved = resolvedPaths.get(fieldApiName);
        Schema.DescribeFieldResult fieldDescribe = resolved.fieldDescribe;

        Object fieldValue = readFieldPath(record, resolved.queryPath);
        fieldValues.put(fieldApiName, fieldValue);

        // Build field metadata
        Map<String, Object> fieldInfo = new Map<String, Object>();
        fieldInfo.put('label', fieldDescribe.getLabel());
        fieldInfo.put('type', String.valueOf(fieldDescribe.getType()));
        fieldInfo.put('isNameField', fieldDescribe.isNameField());
        fieldInfo.put('scale', fieldDescribe.getScale());
        fieldInfo.put('isHtmlFormatted', fieldDescribe.isHtmlFormatted());
        fieldInfo.put('isRelatedField', fieldApiName.contains('.'));
        fieldInfo.put('rootLookupField', resolved.rootLookupField);
        fieldInfo.put('inlineHelpText', fieldDescribe.getInlineHelpText());
        // Related fields are read-only in the form
        fieldInfo.put(
          'isUpdateable',
          !fieldApiName.contains('.') && fieldDescribe.isUpdateable()
        );
        if (
          fieldDescribe.getType() == Schema.DisplayType.PICKLIST ||
          fieldDescribe.getType() == Schema.DisplayType.MULTIPICKLIST
        ) {
          fieldInfo.put(
            'displayValue',
            getPicklistDisplayValue(fieldDescribe, fieldValue)
          );
        }

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
            if (fieldValue != null && resolved.referenceNamePath != null) {
              // The record query already selected the name; no SOQL per lookup
              fieldInfo.put(
                'referenceObjectName',
                ((Id) fieldValue).getSObjectType().getDescribe().getName()
              );
              fieldInfo.put(
                'referenceNameValue',
                readFieldPath(record, resolved.referenceNamePath)
              );
            } else if (fieldValue != null) {
              // Fallback when the targets share no name field (for example Task.WhatId):
              // query the name on the ID's actual object type.
              try {
                Id referenceId = (Id) fieldValue;
                String refObjectName = referenceId.getSObjectType()
                  .getDescribe()
                  .getName();
                fieldInfo.put('referenceObjectName', refObjectName);
                String nameField = getNameField(refObjectName);
                String refQuery =
                  'SELECT ' +
                  nameField +
                  ' FROM ' +
                  refObjectName +
                  ' WHERE Id = :fieldValue WITH USER_MODE LIMIT 1';
                List<SObject> refRecords = Database.query(refQuery);
                if (!refRecords.isEmpty()) {
                  fieldInfo.put(
                    'referenceNameValue',
                    refRecords[0].get(nameField)
                  );
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

  @TestVisible
  private class ResolvedFieldPath {
    Schema.DescribeFieldResult fieldDescribe;
    String rootLookupField;
    String queryPath;
    // For a lookup leaf, the parent's name field path (for example Owner.Name)
    String referenceNamePath;
  }

  // Relationship API names come from getRelationshipName(), including custom __r names.
  @TestVisible
  private static ResolvedFieldPath resolveFieldPath(
    Schema.SObjectType rootType,
    String path
  ) {
    if (
      String.isBlank(path) ||
      !Pattern.matches('[a-zA-Z0-9_]+(\\.[a-zA-Z0-9_]+)*', path)
    ) {
      return null;
    }
    List<String> segments = path.split('\\.');
    // API 60 supports up to five child-to-parent traversals.
    if (segments.size() > 6)
      return null;
    Schema.SObjectType currentType = rootType;
    ResolvedFieldPath resolved = new ResolvedFieldPath();
    List<String> querySegments = new List<String>();
    for (Integer i = 0; i < segments.size(); i++) {
      Schema.DescribeSObjectResult objectDescribe = currentType.getDescribe();
      if (!objectDescribe.isAccessible())
        return null;
      Map<String, Schema.SObjectField> fields = objectDescribe.fields.getMap();
      if (i == segments.size() - 1) {
        Schema.SObjectField leaf = fields.get(segments[i]);
        if (leaf == null || !leaf.getDescribe().isAccessible())
          return null;
        resolved.fieldDescribe = leaf.getDescribe();
        querySegments.add(resolved.fieldDescribe.getName());
        resolved.queryPath = String.join(querySegments, '.');
        // Select a lookup's name in the same query, within SOQL's five-hop limit
        if (
          resolved.fieldDescribe.getType() == Schema.DisplayType.REFERENCE &&
          resolved.fieldDescribe.getRelationshipName() != null &&
          segments.size() < 6
        ) {
          String nameField = referenceNameField(
            resolved.fieldDescribe.getReferenceTo()
          );
          if (nameField != null) {
            querySegments.remove(querySegments.size() - 1);
            querySegments.add(resolved.fieldDescribe.getRelationshipName());
            querySegments.add(nameField);
            resolved.referenceNamePath = String.join(querySegments, '.');
          }
        }
        return resolved;
      }
      Schema.DescribeFieldResult relationship;
      for (Schema.SObjectField candidate : fields.values()) {
        Schema.DescribeFieldResult description = candidate.getDescribe();
        if (
          description.getRelationshipName() != null &&
          (description.getRelationshipName().equalsIgnoreCase(segments[i]) ||
          description.getName().equalsIgnoreCase(segments[i]))
        ) {
          relationship = description;
          break;
        }
      }
      if (
        relationship == null ||
        !relationship.isAccessible() ||
        relationship.getReferenceTo().size() != 1
      )
        return null;
      if (i == 0)
        resolved.rootLookupField = relationship.getName();
      querySegments.add(relationship.getRelationshipName());
      currentType = relationship.getReferenceTo()[0];
    }
    return null;
  }

  // Find a readable name field; polymorphic lookups need one shared by every target.
  @TestVisible
  private static String referenceNameField(List<Schema.SObjectType> targets) {
    if (targets.isEmpty())
      return null;
    String nameField;
    for (Schema.SObjectType target : targets) {
      Schema.DescribeSObjectResult described = target.getDescribe();
      if (!described.isAccessible())
        return null;
      String candidateName;
      for (Schema.SObjectField candidate : described.fields.getMap().values()) {
        Schema.DescribeFieldResult field = candidate.getDescribe();
        if (field.isNameField() && field.isAccessible()) {
          candidateName = field.getName();
          break;
        }
      }
      if (
        candidateName == null ||
        (nameField != null &&
        nameField != candidateName)
      )
        return null;
      nameField = candidateName;
    }
    return nameField;
  }

  private static Object readFieldPath(SObject record, String path) {
    List<String> segments = path.split('\\.');
    SObject current = record;
    for (Integer i = 0; i < segments.size() - 1; i++) {
      if (current == null)
        return null;
      current = current.getSObject(segments[i]);
    }
    return current == null ? null : current.get(segments[segments.size() - 1]);
  }

  /**
   * Get the display labels for a picklist or multi-select picklist value
   */
  @TestVisible
  private static String getPicklistDisplayValue(
    Schema.DescribeFieldResult fieldDescribe,
    Object fieldValue
  ) {
    if (fieldValue == null) {
      return null;
    }
    Map<String, String> labelsByValue = new Map<String, String>();
    for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
      labelsByValue.put(entry.getValue(), entry.getLabel());
    }
    List<String> labels = new List<String>();
    for (String value : String.valueOf(fieldValue).split(';')) {
      labels.add(
        labelsByValue.containsKey(value) ? labelsByValue.get(value) : value
      );
    }
    return String.join(labels, '; ');
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
