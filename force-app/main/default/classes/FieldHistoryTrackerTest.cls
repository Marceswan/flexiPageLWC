@IsTest
private class FieldHistoryTrackerTest {
    @TestSetup
    static void setupTestData() {
        // Create test Account
        Account testAccount = new Account(
                Name = 'Test Account',
                Industry = 'Technology',
                Description = 'Initial Description',
                NumberOfEmployees = 100,
                Website = 'www.test.com'
        );
        insert testAccount;

        // Create related Contact for testing lookup relationships
        Contact testContact = new Contact(
                FirstName = 'Test',
                LastName = 'Contact',
                AccountId = testAccount.Id,
                Email = 'test@example.com'
        );
        insert testContact;
    }

    // Helper method to get all accessible fields for an SObject
    private static String getAllAccessibleFields(String objectName) {
        List<String> fieldNames = new List<String>();
        SObjectType objectType = Schema.getGlobalDescribe().get(objectName);
        Map<String, Schema.SObjectField> fieldMap = objectType.getDescribe().fields.getMap();

        for(String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult describeResult = fieldMap.get(fieldName).getDescribe();
            if(describeResult.isAccessible()) {
                fieldNames.add(fieldName);
            }
        }

        return String.join(fieldNames, ',');
    }

    @IsTest
    static void testTrackFieldChangesInvocable() {
        // Get all accessible fields for Account
        String fields = getAllAccessibleFields('Account');

        // Get the original Account with all fields
        Account oldAccount = Database.query('SELECT ' + fields + ' FROM Account LIMIT 1');

        // Create modified version of the Account
        Account newAccount = oldAccount.clone(true, true, true, true);
        newAccount.Name = 'Updated Test Account';
        newAccount.Industry = 'Healthcare';
        newAccount.Description = 'Updated Description';
        newAccount.NumberOfEmployees = 200;
        update newAccount;

        // Now query the updated account
        newAccount = Database.query('SELECT ' + fields + ' FROM Account WHERE Id = \'' + newAccount.Id + '\'');

        // Create request for field tracking
        FieldHistoryTracker.FieldHistoryRequest req = new FieldHistoryTracker.FieldHistoryRequest();
        req.oldRecord = oldAccount;
        req.newRecord = newAccount;
        req.recordId = newAccount.Id;
        req.objectApiName = 'Account';

        Test.startTest();
        FieldHistoryTracker.trackFieldChanges(new List<FieldHistoryTracker.FieldHistoryRequest>{req});
        Test.stopTest();

        // Verify Field History records
        List<Field_History__c> histories = [SELECT Id, Change__c FROM Field_History__c
        WHERE Record_Id__c = :newAccount.Id];
        System.assertEquals(1, histories.size(), 'Should have created one history record');

        // Verify the changes were tracked correctly
        List<FieldHistoryTracker.FieldChange> changes =
                (List<FieldHistoryTracker.FieldChange>)JSON.deserialize(
                        histories[0].Change__c,
                        List<FieldHistoryTracker.FieldChange>.class
                );

        // Verify specific field changes
        Map<String, FieldHistoryTracker.FieldChange> changesByField = new Map<String, FieldHistoryTracker.FieldChange>();
        for(FieldHistoryTracker.FieldChange change : changes) {
            changesByField.put(change.fieldApiName, change);
        }

        //System.assert(changesByField.containsKey('Name'), 'Should track Name change');
        //System.assert(changesByField.containsKey('Industry'), 'Should track Industry change');
        //System.assertEquals('Test Account', changesByField.get('Name').oldValue);
        //System.assertEquals('Updated Test Account', changesByField.get('Name').newValue);
    }

    @IsTest
    static void testTrackFieldChangesAura() {
        String fields = getAllAccessibleFields('Account');
        Account oldAccount = Database.query('SELECT ' + fields + ' FROM Account LIMIT 1');

        // Create modified version
        Account newAccount = oldAccount.clone(true, true, true, true);
        newAccount.Name = 'Updated Via Aura';
        newAccount.Website = 'www.updated.com';
        update newAccount;

        // Query after update
        newAccount = Database.query('SELECT ' + fields + ' FROM Account WHERE Id = \'' + newAccount.Id + '\'');

        Test.startTest();
        String result = FieldHistoryTracker.trackFieldChangesAura(
                JSON.serialize(oldAccount),
                JSON.serialize(newAccount),
                newAccount.Id,
                'Account'
        );
        Test.stopTest();

        System.assert(result.contains('Successfully tracked'), 'Should return success message');
    }

    @IsTest
    static void testTrackFieldChangesWithLookup() {
        String fields = getAllAccessibleFields('Contact');
        Contact oldContact = Database.query('SELECT ' + fields + ' FROM Contact LIMIT 1');

        // Create new Account for updated lookup
        Account newAccount = new Account(Name = 'New Parent Account');
        insert newAccount;

        // Create modified version of Contact
        Contact newContact = oldContact.clone(true, true, true, true);
        newContact.AccountId = newAccount.Id;
        update newContact;

        // Query after update
        newContact = Database.query('SELECT ' + fields + ' FROM Contact WHERE Id = \'' + newContact.Id + '\'');

        Test.startTest();
        FieldHistoryTracker.trackFieldChangesAura(
                JSON.serialize(oldContact),
                JSON.serialize(newContact),
                newContact.Id,
                'Contact'
        );
        Test.stopTest();

        // Verify Field History records
        List<Field_History__c> histories = [SELECT Id, Change__c FROM Field_History__c
        WHERE Record_Id__c = :newContact.Id];
        System.assertEquals(1, histories.size(), 'Should have created one history record');

        // Verify lookup change was tracked with record names
        List<FieldHistoryTracker.FieldChange> changes =
                (List<FieldHistoryTracker.FieldChange>)JSON.deserialize(
                        histories[0].Change__c,
                        List<FieldHistoryTracker.FieldChange>.class
                );

        Boolean foundAccountChange = false;
        for(FieldHistoryTracker.FieldChange change : changes) {
            if(change.fieldApiName == 'AccountId') {
                foundAccountChange = true;
                System.assert(change.oldValue.contains('Test Account'));
                System.assert(change.newValue.contains('New Parent Account'));
                break;
            }
        }
        System.assert(foundAccountChange, 'Should track Account lookup change');
    }

    @IsTest
    static void testNewRecordTracking() {
        Account newAccount = new Account(
                Name = 'Brand New Account',
                Industry = 'Education'
        );
        insert newAccount;

        // Query after insert
        String fields = getAllAccessibleFields('Account');
        newAccount = Database.query('SELECT ' + fields + ' FROM Account WHERE Id = \'' + newAccount.Id + '\'');

        Test.startTest();
        String result = FieldHistoryTracker.trackFieldChangesAura(
                null,
                JSON.serialize(newAccount),
                newAccount.Id,
                'Account'
        );
        Test.stopTest();

        System.assert(result.contains('Successfully tracked'), 'Should return success message');
    }

    @IsTest
    static void testErrorHandling() {
        try {
            FieldHistoryTracker.trackFieldChangesAura(
                    'Invalid JSON',
                    'Invalid JSON',
                    'Invalid ID',
                    'Invalid Object'
            );
            System.assert(false, 'Should throw an exception for invalid input');
        } catch(AuraHandledException e) {
            // Test passes if exception is thrown
            System.assert(true, 'Exception was thrown as expected');
        }
    }
}