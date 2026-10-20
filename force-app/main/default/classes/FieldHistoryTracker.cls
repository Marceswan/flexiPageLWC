public with sharing class FieldHistoryTracker {
    public class FieldChange {
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String fieldLabel;
        @AuraEnabled public String oldValue;
        @AuraEnabled public String newValue;
    }

    public class FieldHistoryRequest {
        @InvocableVariable(required=true)
        public SObject oldRecord;

        @InvocableVariable(required=true)
        public SObject newRecord;

        @InvocableVariable(required=true)
        public String recordId;

        @InvocableVariable(required=true)
        public String objectApiName;
    }

    private static Set<String> EXCLUDED_FIELDS = new Set<String>{
            'lastmodifieddate',
            'systemmodstamp',
            'isdeleted',
            'MasterRecordId'

    };

    private static String formatValue(Object value, Schema.DescribeFieldResult fieldDescribe, Map<Id, String> recordNames) {
        if (value == null) return '(blank)';

        try {
            // Handle lookup relationships
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                Id recordId = (Id)value;
                return recordNames.containsKey(recordId) ? recordNames.get(recordId) : String.valueOf(value);
            }

            // Handle other field types
            switch on fieldDescribe.getType() {
                when DATE {
                    Date d;
                    if (value instanceof Date) {
                        d = (Date)value;
                    } else if (value instanceof String) {
                        d = Date.valueOf((String)value);
                    } else {
                        return String.valueOf(value);
                    }
                    return DateTime.newInstance(d.year(), d.month(), d.day())
                            .format('EEE MMMM d, yyyy');
                }
                when DATETIME {
                    DateTime dt;
                    if (value instanceof DateTime) {
                        dt = (DateTime)value;
                    } else if (value instanceof String) {
                        String strValue = (String)value;
                        if (strValue.contains('T')) {
                            dt = DateTime.valueOfGmt(strValue.replace('T', ' '));
                        } else {
                            dt = DateTime.valueOf(strValue);
                        }
                    } else {
                        return String.valueOf(value);
                    }
                    return dt.format('EEE MMMM d, yyyy - h:mm:ss a');
                }
                when else {
                    return String.valueOf(value);
                }
            }
        } catch (Exception e) {
            return String.valueOf(value);
        }
    }

    private static Map<Id, String> getRecordNames(Set<Id> recordIds) {
        Map<Id, String> recordNames = new Map<Id, String>();

        if (recordIds.isEmpty()) return recordNames;

        // Group records by object type
        Map<String, Set<Id>> recordsByObject = new Map<String, Set<Id>>();
        for (Id recordId : recordIds) {
            String objectType = recordId.getSObjectType().getDescribe().getName();
            if (!recordsByObject.containsKey(objectType)) {
                recordsByObject.put(objectType, new Set<Id>());
            }
            recordsByObject.get(objectType).add(recordId);
        }

        // Query Name field for each object type
        for (String objectType : recordsByObject.keySet()) {
            String query = 'SELECT Id, Name FROM ' + objectType + ' WHERE Id IN :recordIds';
            Set<Id> objectRecordIds = recordsByObject.get(objectType);

            for (SObject record : Database.query(query)) {
                recordNames.put(record.Id, (String)record.get('Name'));
            }
        }

        return recordNames;
    }

    private static List<Field_History__c> processFieldChanges(SObject oldRecord, SObject newRecord,
            String recordId, String objectApiName) {
        List<Field_History__c> historyRecords = new List<Field_History__c>();
        Schema.DescribeSObjectResult describeResult = Schema.getGlobalDescribe()
                .get(objectApiName).getDescribe();
        Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
        List<FieldChange> changes = new List<FieldChange>();

        // Collect all reference IDs that need to be queried
        Set<Id> referencedRecordIds = new Set<Id>();

        // First pass: identify changed fields and collect reference IDs
        Map<String, FieldChange> preliminaryChanges = new Map<String, FieldChange>();
        for(String fieldName : fieldMap.keySet()) {
            if(EXCLUDED_FIELDS.contains(fieldName.toLowerCase())) {
                continue;
            }

            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();
            if(fieldDescribe.isAccessible() &&
                    !fieldDescribe.isAutoNumber() &&
                    !fieldDescribe.isCalculated()) {

                Object newValue = newRecord.get(fieldName);
                Boolean hasChanged = false;

                if (oldRecord == null) {
                    hasChanged = (newValue != null);
                } else {
                    Object oldValue = oldRecord.get(fieldName);
                    hasChanged = (oldValue == null && newValue != null) ||
                            (oldValue != null && newValue == null) ||
                            (oldValue != null && newValue != null && !oldValue.equals(newValue));
                }

                if(hasChanged) {
                    // For reference fields, collect the IDs
                    if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                        if (oldRecord != null && oldRecord.get(fieldName) != null) {
                            referencedRecordIds.add((Id)oldRecord.get(fieldName));
                        }
                        if (newValue != null) {
                            referencedRecordIds.add((Id)newValue);
                        }
                    }

                    FieldChange change = new FieldChange();
                    change.fieldApiName = fieldName;
                    change.fieldLabel = fieldDescribe.getLabel();
                    preliminaryChanges.put(fieldName, change);
                }
            }
        }

        // Get all record names in bulk
        Map<Id, String> recordNames = getRecordNames(referencedRecordIds);

        // Second pass: format values with record names
        for (String fieldName : preliminaryChanges.keySet()) {
            FieldChange change = preliminaryChanges.get(fieldName);
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();

            change.oldValue = oldRecord == null ? '(new)' :
                    formatValue(oldRecord.get(fieldName), fieldDescribe, recordNames);
            change.newValue = formatValue(newRecord.get(fieldName), fieldDescribe, recordNames);

            changes.add(change);
        }

        if(!changes.isEmpty()) {
            Field_History__c history = new Field_History__c(
                    Record_Id__c = recordId,
                    Object_Api_Name__c = objectApiName,
                    Change__c = JSON.serialize(changes)
            );
            historyRecords.add(history);
        }

        return historyRecords;
    }

    @InvocableMethod(label='Track Field Changes' description='Creates Field History records for changed fields')
    public static void trackFieldChanges(List<FieldHistoryRequest> requests) {
        List<Field_History__c> historyRecords = new List<Field_History__c>();

        for(FieldHistoryRequest req : requests) {
            List<Field_History__c> records = processFieldChanges(req.oldRecord, req.newRecord,
                    req.recordId, req.objectApiName);
            historyRecords.addAll(records);
        }

        if(!historyRecords.isEmpty()) {
            insert historyRecords;
        }
    }

    @AuraEnabled
    public static String trackFieldChangesAura(String oldRecordJson, String newRecordJson,
            String recordId, String objectApiName) {
        try {
            SObject oldRecord = String.isBlank(oldRecordJson) ? null :
                    (SObject)JSON.deserialize(oldRecordJson, Type.forName('Schema.' + objectApiName));
            SObject newRecord = (SObject)JSON.deserialize(newRecordJson,
                    Type.forName('Schema.' + objectApiName));

            List<Field_History__c> historyRecords = processFieldChanges(oldRecord, newRecord,
                    recordId, objectApiName);

            if(!historyRecords.isEmpty()) {
                insert historyRecords;
                return 'Successfully tracked ' + historyRecords.size() + ' field changes';
            }
            return 'No changes detected';

        } catch(Exception e) {
            throw new AuraHandledException('Error tracking field changes: ' + e.getMessage());
        }
    }

    @AuraEnabled(Cacheable=true)
    public static List<Field_History__c> getFieldHistory(String recordId) {
        return [
                SELECT Id, CreatedById, CreatedBy.Name, CreatedDate,
                        Change__c, Record_Id__c, Object_Api_Name__c
                FROM Field_History__c
                WHERE Record_Id__c = :recordId
                ORDER BY CreatedDate DESC
        ];
    }
}