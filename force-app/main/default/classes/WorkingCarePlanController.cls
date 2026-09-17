/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : WorkingCarePlanController
 * Author          : <YourName>
 * Created Date    : Apr 28, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Apr 28, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Apr 28, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class WorkingCarePlanController {

	@AuraEnabled(cacheable=false)
public static Id getLatestCarePlanId(Id accountId) {
 
    
    List<Case> cases = [
        SELECT Id
        FROM   Case
        WHERE  AccountId = :accountId
          AND  RecordType.DeveloperName = 'CarePlan'   
        ORDER BY CreatedDate DESC
        LIMIT  1
    ];
 
    return cases.isEmpty() ? null : cases[0].Id;
}

}