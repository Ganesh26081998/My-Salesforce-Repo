/*
----------------------------------------------------------------------------
Author        : Tushar Darode
Class Name    : PatientNotesController
CreatedOn     : 13-01-2026
LastModifiedOn: 15-05-2026
LastModifiedBy: Tushar Darode
Description   : This class manages Patient Notes functionality including 
                retrieving, searching, sorting, and creating patient notes 
                related to an Account. It supports keyword-based note search 
                across note names and descriptions, dynamic sorting by date, 
                and note creation with account association.
----------------------------------------------------------------------------
*/

public without sharing class PatientNotesController {

    @AuraEnabled
    public static List<Patient_Notes__c> getNotes(String searchKey, Id accountId, String sortDirection) {

        String key = '%' + (searchKey == null ? '' : searchKey) + '%';

        String baseSelect = 'SELECT Id, Name, Descriptions__c, Date__c, CreatedDate, CreatedBy.Name, Account__c, Account__r.Name FROM Patient_Notes__c';

        if (String.isBlank(sortDirection)) {
            sortDirection = 'DESC';
        }

        String orderBy;
        Boolean isAsc;

        if (sortDirection == 'ASC') {
            orderBy = ' ORDER BY Date__c ASC';
            isAsc = true;
        } else {
            orderBy = ' ORDER BY Date__c DESC';
            isAsc = false;
        }

        String nameQuery = baseSelect + ' WHERE ';

        if (accountId != null && String.isNotBlank(searchKey)) {
            nameQuery += 'Account__c = :accountId AND Name LIKE :key' + orderBy;
        } 
        else if (accountId != null) {
            nameQuery += 'Account__c = :accountId' + orderBy;
        } 
        else if (String.isNotBlank(searchKey)) {
            nameQuery += 'Name LIKE :key' + orderBy;
        } 
        else {
            nameQuery += 'Id != null' + orderBy;
        }

        List<Patient_Notes__c> results = Database.query(nameQuery);

        if (String.isNotBlank(searchKey)) {

            String lowerKey = searchKey.toLowerCase();
            Set<Id> seen = new Set<Id>();

            for (Patient_Notes__c n : results) {
                seen.add(n.Id);
            }

            String allQuery = baseSelect +
                (accountId != null
                ? ' WHERE Account__c = :accountId'
                : ' WHERE Id != null');

            for (Patient_Notes__c n : Database.query(allQuery)) {

                if (!seen.contains(n.Id) &&
                    n.Descriptions__c != null &&
                    n.Descriptions__c.toLowerCase().contains(lowerKey)) {

                    results.add(n);
                }
            }
        }

        results.sort(new CreatedDateComparator(isAsc));

        return results;
    }

    public class CreatedDateComparator implements Comparator<Patient_Notes__c> {
        Boolean isAsc;

        public CreatedDateComparator(Boolean isAsc) {
            this.isAsc = isAsc;
        }

        // public Integer compare(Patient_Notes__c a, Patient_Notes__c b) {

        //     if (a.Date__c == null && b.Date__c == null) return 0;
        //     if (a.Date__c == null) return isAsc ? -1 : 1;
        //     if (b.Date__c == null) return isAsc ? 1 : -1;

        //     if (a.Date__c == b.Date__c) return 0;

        //     return isAsc
        //         ? (a.Date__c > b.Date__c ? 1 : -1)
        //         : (a.Date__c < b.Date__c ? 1 : -1);
        // }
        public Integer compare(Patient_Notes__c a, Patient_Notes__c b) {

            if (a.Date__c == null && b.Date__c == null) {
                return compareCreatedDate(a, b);
            }

            if (a.Date__c == null) return isAsc ? -1 : 1;
            if (b.Date__c == null) return isAsc ? 1 : -1;

            if (a.Date__c != b.Date__c) {
                return isAsc
                    ? (a.Date__c > b.Date__c ? 1 : -1)
                    : (a.Date__c < b.Date__c ? 1 : -1);
            }

            // Same date -> sort by time created
            return compareCreatedDate(a, b);
        }

        private Integer compareCreatedDate(
            Patient_Notes__c a,
            Patient_Notes__c b
        ) {
            if (a.CreatedDate == b.CreatedDate) return 0;

            return isAsc
                ? (a.CreatedDate > b.CreatedDate ? 1 : -1)
                : (a.CreatedDate < b.CreatedDate ? 1 : -1);
        }
    }

    @AuraEnabled
    public static Patient_Notes__c saveNote(String name, String description, Id accountId) {

        Account acc = [
            SELECT Id, Is_Deactivated__c
            FROM Account
            WHERE Id = :accountId
            LIMIT 1
        ];

        Patient_Notes__c note = new Patient_Notes__c();
        note.Name = name;
        note.Descriptions__c = description;
        note.Account__c = accountId;
        note.Date__c = System.today();

        insert note;

        return note;
    }
}