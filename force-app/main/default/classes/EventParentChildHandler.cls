public with sharing class EventParentChildHandler {

    // ── @TestVisible: build seriesMap from a pre-fetched list ──────
    @TestVisible
    private static Map<Id, List<Event>> buildSeriesMap(List<Event> allEvents) {
        Map<Id, List<Event>> seriesMap = new Map<Id, List<Event>>();
        for (Event e : allEvents) {
            if (!seriesMap.containsKey(e.ActivityRecurrence2Id)) {
                seriesMap.put(e.ActivityRecurrence2Id, new List<Event>());
            }
            seriesMap.get(e.ActivityRecurrence2Id).add(e);
        }
        return seriesMap;
    }

    // ── @TestVisible: core assign logic (no SOQL / DML) ───────────
    @TestVisible
    private static List<Event> assignParentChild(Map<Id, List<Event>> seriesMap) {
        List<Event> updateList = new List<Event>();

        for (Id recId : seriesMap.keySet()) {
            List<Event> events = seriesMap.get(recId);
            if (events.isEmpty()) continue;

            // STEP 3: Check if parent already exists
            Event existingParent;
            for (Event e : events) {
                if (e.Event_Type__c == 'Parent') {
                    existingParent = e;
                    break;
                }
            }

            // STEP 4: Parent exists → keep parent, fix children only
            if (existingParent != null) {
                for (Event e : events) {
                    if (e.Id == existingParent.Id) {
                        continue;
                    }
                    if (e.Event_Type__c != 'Child' ||
                        e.Parent_Event_Id__c != existingParent.Id) {
                        e.Event_Type__c      = 'Child';
                        e.Parent_Event_Id__c = existingParent.Id;
                        updateList.add(e);
                    }
                }
            }
            // STEP 5: No parent → promote first event
            else {
                Event parent = events[0];
                for (Event e : events) {
                    if (e.Id == parent.Id) {
                        e.Event_Type__c      = 'Parent';
                        e.Parent_Event_Id__c = null;
                        updateList.add(e);
                    } else {
                        e.Event_Type__c      = 'Child';
                        e.Parent_Event_Id__c = parent.Id;
                        updateList.add(e);
                    }
                }
            }
        }
        return updateList;
    }

    // ── Public entry point (trigger-facing) ───────────────────────
    public static void processEvents(List<Event> newList, Map<Id, Event> oldMap) {
        Set<Id> recurrenceIds = new Set<Id>();

        // Step 1: Collect recurring events
        for (Event e : newList) {
            if (e.ActivityRecurrence2Id != null) {
                recurrenceIds.add(e.ActivityRecurrence2Id);
            }
        }
        if (recurrenceIds.isEmpty()) return;

        // Step 2: Fetch all events in series
        List<Event> allEvents = [
            SELECT Id, ActivityRecurrence2Id, CreatedDate,
                   Parent_Event_Id__c, Event_Type__c
            FROM Event
            WHERE ActivityRecurrence2Id IN :recurrenceIds
            ORDER BY CreatedDate ASC
        ];

        Map<Id, List<Event>> seriesMap = buildSeriesMap(allEvents);
        List<Event> updateList         = assignParentChild(seriesMap);

        if (!updateList.isEmpty()) {
            update updateList;
        }
    }
}