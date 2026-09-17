@isTest
public class TaskHandlerTest {
    
    @testSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test Account');
        insert testAccount;
        
        Contact testContact = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = testAccount.Id
        );
        insert testContact;
    }
    
    @isTest
    static void testSetCustomerNameWithContact() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Doe' LIMIT 1];
        
        Task taskWithContact = new Task(
            Subject = 'Test Task',
            WhoId = testContact.Id,
            Status = 'Open'
        );
        
        Test.startTest();
        insert taskWithContact;
        Test.stopTest();
        
        Task insertedTask = [SELECT Customer_Name__c FROM Task WHERE Id = :taskWithContact.Id];
    }
    
    @isTest
    static void testSetCustomerNameWithAccount() {
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        
        Task taskWithAccount = new Task(
            Subject = 'Test Task',
            WhatId = testAccount.Id,
            Status = 'Open'
        );
        
        Test.startTest();
        insert taskWithAccount;
        Test.stopTest();
        
        Task insertedTask = [SELECT Customer_Name__c FROM Task WHERE Id = :taskWithAccount.Id];
    }
    
    @isTest
    static void testSetCustomerNameBulk() {
        Contact testContact = [SELECT Id FROM Contact WHERE LastName = 'Doe' LIMIT 1];
        Account testAccount = [SELECT Id FROM Account WHERE Name = 'Test Account' LIMIT 1];
        
        List<Task> tasks = new List<Task>();
        for (Integer i = 0; i < 5; i++) {
            if (Math.mod(i, 2) == 0) {
                tasks.add(new Task(Subject = 'Task ' + i, WhoId = testContact.Id, Status = 'Open'));
            } else {
                tasks.add(new Task(Subject = 'Task ' + i, WhatId = testAccount.Id, Status = 'Open'));
            }
        }
        
        Test.startTest();
        insert tasks;
        Test.stopTest();
        
        List<Task> insertedTasks = [SELECT Customer_Name__c FROM Task ORDER BY Subject];
        for (Task t : insertedTasks) {
        }
    }
}