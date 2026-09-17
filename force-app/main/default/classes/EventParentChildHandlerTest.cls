@isTest
private class EventParentChildHandlerTest {

    // ─────────────────────────────────────────────────────────────────────
    // 
    // We use JSON deserialization to stamp system/read-only fields
    // (ActivityRecurrence2Id, Parent_Event_Id__c) onto SObjects in tests.
    // ─────────────────────────────────────────────────────────────────────
    private static final Id RECURRENCE_ID_A = '0HO000000000001AAA';
    private static final Id RECURRENCE_ID_B = '0HO000000000002AAA';

    private static final Id EVT_ID_1 = '00U000000000001AAA';
    private static final Id EVT_ID_2 = '00U000000000002AAA';
    private static final Id EVT_ID_3 = '00U000000000003AAA';
    private static final Id EVT_ID_4 = '00U000000000004AAA';
    private static final Id EVT_ID_5 = '00U000000000005AAA';

    /**
     * Build a fake Event with read-only fields set via JSON deserialize.
     */
    private static Event makeEvent(
        Id recId,
        Id evtId,
        String eventType,
        Id parentEventId
    ) {
        Map<String, Object> raw = new Map<String, Object>{
            'Id'                     => evtId,
            'ActivityRecurrence2Id'  => recId,
            'Event_Type__c'          => eventType,
            'Parent_Event_Id__c'     => parentEventId,
            'CreatedDate'            => System.now()
        };
        return (Event) JSON.deserialize(JSON.serialize(raw), Event.class);
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 1 – processEvents: empty / non-recurring list → early return
    // Ensures the recurrenceIds.isEmpty() guard is hit (no exception).
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_processEvents_noRecurringEvents_earlyReturn() {
        // Insert a plain (non-recurring) event so the newList is not empty
        Event plainEvt = new Event(
            Subject           = 'Non-recurring',
            StartDateTime     = System.now(),
            EndDateTime       = System.now().addHours(1),
            DurationInMinutes = 60
        );
        insert plainEvt;

        List<Event> newList = new List<Event>{ plainEvt };

        Test.startTest();
        // Must NOT throw – returns immediately because recurrenceIds is empty
        EventParentChildHandler.processEvents(newList, null);
        Test.stopTest();

        System.assert(true, 'No exception expected for non-recurring events');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 2 – buildSeriesMap: groups events by ActivityRecurrence2Id
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_buildSeriesMap_groupsCorrectly() {
        List<Event> allEvents = new List<Event>{
            makeEvent(RECURRENCE_ID_A, EVT_ID_1, null, null),
            makeEvent(RECURRENCE_ID_A, EVT_ID_2, null, null),
            makeEvent(RECURRENCE_ID_B, EVT_ID_3, null, null)
        };

        Test.startTest();
        Map<Id, List<Event>> result =
            EventParentChildHandler.buildSeriesMap(allEvents);
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Should have 2 series keys');
        System.assertEquals(2, result.get(RECURRENCE_ID_A).size(),
            'Series A should have 2 events');
        System.assertEquals(1, result.get(RECURRENCE_ID_B).size(),
            'Series B should have 1 event');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 3 – assignParentChild: empty list for a series key → skip
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_assignParentChild_emptySeriesList_noUpdates() {
        Map<Id, List<Event>> seriesMap = new Map<Id, List<Event>>{
            RECURRENCE_ID_A => new List<Event>() // deliberately empty
        };

        Test.startTest();
        List<Event> result = EventParentChildHandler.assignParentChild(seriesMap);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'Empty series should produce zero updates');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 4 – assignParentChild: NO existing parent
    //          → first event becomes Parent, rest become Children
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_assignParentChild_noExistingParent_firstBecomesParent() {
        Event e1 = makeEvent(RECURRENCE_ID_A, EVT_ID_1, null, null);
        Event e2 = makeEvent(RECURRENCE_ID_A, EVT_ID_2, null, null);
        Event e3 = makeEvent(RECURRENCE_ID_A, EVT_ID_3, null, null);

        Map<Id, List<Event>> seriesMap = new Map<Id, List<Event>>{
            RECURRENCE_ID_A => new List<Event>{ e1, e2, e3 }
        };

        Test.startTest();
        List<Event> result = EventParentChildHandler.assignParentChild(seriesMap);
        Test.stopTest();

        // All 3 events should be in the update list
        System.assertEquals(3, result.size(),
            'All 3 events should be queued for update');

        // Find them by Id in the result list
        Map<Id, Event> resultMap = new Map<Id, Event>();
        for (Event e : result) { resultMap.put(e.Id, e); }

        // First event → Parent
        System.assertEquals('Parent', resultMap.get(EVT_ID_1).Event_Type__c,
            'First event should be Parent');
        System.assertEquals(null, resultMap.get(EVT_ID_1).Parent_Event_Id__c,
            'Parent should have null Parent_Event_Id__c');

        // Second event → Child pointing to first
        System.assertEquals('Child', resultMap.get(EVT_ID_2).Event_Type__c,
            'Second event should be Child');
        System.assertEquals(EVT_ID_1, resultMap.get(EVT_ID_2).Parent_Event_Id__c,
            'Second event Parent_Event_Id__c should point to first');

        // Third event → Child pointing to first
        System.assertEquals('Child', resultMap.get(EVT_ID_3).Event_Type__c,
            'Third event should be Child');
        System.assertEquals(EVT_ID_1, resultMap.get(EVT_ID_3).Parent_Event_Id__c,
            'Third event Parent_Event_Id__c should point to first');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 5 – assignParentChild: parent ALREADY EXISTS
    //          → parent untouched; stale children get corrected
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_assignParentChild_existingParent_childrenCorrected() {
        // e1 = already correct Parent
        Event e1 = makeEvent(RECURRENCE_ID_A, EVT_ID_1, 'Parent', null);
        // e2 = correct child (already pointing to e1) → should NOT be re-added
        Event e2 = makeEvent(RECURRENCE_ID_A, EVT_ID_2, 'Child', EVT_ID_1);
        // e3 = stale child (wrong type / wrong parent) → must be corrected
        Event e3 = makeEvent(RECURRENCE_ID_A, EVT_ID_3, null, null);

        Map<Id, List<Event>> seriesMap = new Map<Id, List<Event>>{
            RECURRENCE_ID_A => new List<Event>{ e1, e2, e3 }
        };

        Test.startTest();
        List<Event> result = EventParentChildHandler.assignParentChild(seriesMap);
        Test.stopTest();

        // Only e3 should be in the update list (e1 skipped, e2 already correct)
        System.assertEquals(1, result.size(),
            'Only the stale child should be queued for update');
        System.assertEquals(EVT_ID_3, result[0].Id,
            'The stale event should be EVT_ID_3');
        System.assertEquals('Child', result[0].Event_Type__c,
            'Stale event should be set to Child');
        System.assertEquals(EVT_ID_1, result[0].Parent_Event_Id__c,
            'Stale event Parent_Event_Id__c should point to existing parent');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 6 – assignParentChild: existing parent → ALL children already
    //          correct → updateList stays empty
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_assignParentChild_existingParent_allChildrenCorrect_noUpdates() {
        Event e1 = makeEvent(RECURRENCE_ID_A, EVT_ID_1, 'Parent', null);
        Event e2 = makeEvent(RECURRENCE_ID_A, EVT_ID_2, 'Child', EVT_ID_1);
        Event e3 = makeEvent(RECURRENCE_ID_A, EVT_ID_3, 'Child', EVT_ID_1);

        Map<Id, List<Event>> seriesMap = new Map<Id, List<Event>>{
            RECURRENCE_ID_A => new List<Event>{ e1, e2, e3 }
        };

        Test.startTest();
        List<Event> result = EventParentChildHandler.assignParentChild(seriesMap);
        Test.stopTest();

        System.assertEquals(0, result.size(),
            'No updates needed when all children are already correct');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 7 – assignParentChild: multiple series in one call
    //          Series A has parent, Series B has no parent
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_assignParentChild_multipleSeries() {
        // Series A: parent already set
        Event a1 = makeEvent(RECURRENCE_ID_A, EVT_ID_1, 'Parent', null);
        Event a2 = makeEvent(RECURRENCE_ID_A, EVT_ID_2, null, null); // stale

        // Series B: no parent
        Event b1 = makeEvent(RECURRENCE_ID_B, EVT_ID_3, null, null);
        Event b2 = makeEvent(RECURRENCE_ID_B, EVT_ID_4, null, null);

        Map<Id, List<Event>> seriesMap = new Map<Id, List<Event>>{
            RECURRENCE_ID_A => new List<Event>{ a1, a2 },
            RECURRENCE_ID_B => new List<Event>{ b1, b2 }
        };

        Test.startTest();
        List<Event> result = EventParentChildHandler.assignParentChild(seriesMap);
        Test.stopTest();

        // Series A: 1 stale child corrected
        // Series B: 2 events updated (1 Parent + 1 Child)
        System.assertEquals(3, result.size(),
            'Should have 3 total updates across both series');

        Map<Id, Event> resultMap = new Map<Id, Event>();
        for (Event e : result) { resultMap.put(e.Id, e); }

        // Series A stale child
        System.assertEquals('Child', resultMap.get(EVT_ID_2).Event_Type__c);
        System.assertEquals(EVT_ID_1, resultMap.get(EVT_ID_2).Parent_Event_Id__c);

        // Series B first = Parent
        System.assertEquals('Parent', resultMap.get(EVT_ID_3).Event_Type__c);
        System.assertNotEquals(null, resultMap.get(EVT_ID_3),
            'Series B first event should be in update list as Parent');

        // Series B second = Child
        System.assertEquals('Child', resultMap.get(EVT_ID_4).Event_Type__c);
        System.assertEquals(EVT_ID_3, resultMap.get(EVT_ID_4).Parent_Event_Id__c);
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 8 – assignParentChild: single event in series, no parent
    //          → that single event becomes Parent
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_assignParentChild_singleEventNoParent_becomesParent() {
        Event e1 = makeEvent(RECURRENCE_ID_A, EVT_ID_1, null, null);

        Map<Id, List<Event>> seriesMap = new Map<Id, List<Event>>{
            RECURRENCE_ID_A => new List<Event>{ e1 }
        };

        Test.startTest();
        List<Event> result = EventParentChildHandler.assignParentChild(seriesMap);
        Test.stopTest();

        System.assertEquals(1, result.size(),
            'Single event should be queued for update');
        System.assertEquals('Parent', result[0].Event_Type__c,
            'Single event should be assigned Parent type');
        System.assertEquals(null, result[0].Parent_Event_Id__c,
            'Parent_Event_Id__c should be null for single Parent');
    }

    // ─────────────────────────────────────────────────────────────────────
    // TEST 9 – buildSeriesMap: single series, single event
    // ─────────────────────────────────────────────────────────────────────
    @isTest
    static void test_buildSeriesMap_singleSeries_singleEvent() {
        List<Event> allEvents = new List<Event>{
            makeEvent(RECURRENCE_ID_A, EVT_ID_1, null, null)
        };

        Test.startTest();
        Map<Id, List<Event>> result =
            EventParentChildHandler.buildSeriesMap(allEvents);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'One series key expected');
        System.assertEquals(1, result.get(RECURRENCE_ID_A).size(),
            'One event in series A');
    }
}