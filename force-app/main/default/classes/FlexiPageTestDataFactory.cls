/** Isolated records for related-field service tests. */
@IsTest
public with sharing class FlexiPageTestDataFactory {
  public static void createRelatedFieldRecords() {
    Account parent = new Account(Name = 'Parent Account');
    insert parent;
    Account child = new Account(
      Name = 'Child Account',
      ParentId = parent.Id,
      AnnualRevenue = 0
    );
    insert child;
    insert new List<Contact>{
      new Contact(LastName = 'Related Fields', AccountId = child.Id),
      new Contact(LastName = 'No Account')
    };
  }
}
