public class BillingGroupIterable implements Iterable<List<Billing__c>> {
    private List<Billing__c> billingRecords;

    public BillingGroupIterable(List<Billing__c> billingRecords) {
        this.billingRecords = billingRecords;
    }

    public Iterator<List<Billing__c>> iterator() {
        return new BillingGroupIterator(billingRecords);
    }

    private class BillingGroupIterator implements Iterator<List<Billing__c>> {
        private Map<String, List<Billing__c>> groupedBillingsMap = new Map<String, List<Billing__c>>();
        private List<String> groupKeys = new List<String>();
        private Integer currentIndex = 0;

        public BillingGroupIterator(List<Billing__c> records) {
            for (Billing__c b : records) {
                String groupKey = b.Client__c + '_' + b.Location_g__c;
                if (!groupedBillingsMap.containsKey(groupKey)) {
                    groupedBillingsMap.put(groupKey, new List<Billing__c>());
                    groupKeys.add(groupKey);
                }
                groupedBillingsMap.get(groupKey).add(b);
            }
        }

        public Boolean hasNext() {
            return currentIndex < groupKeys.size();
        }

        public List<Billing__c> next() {
            if (!hasNext()) {
                throw new NoSuchElementException('No more billing groups to iterate.');
            }
            String key = groupKeys.get(currentIndex);
            currentIndex++;
            return groupedBillingsMap.get(key);
        }
    }
}