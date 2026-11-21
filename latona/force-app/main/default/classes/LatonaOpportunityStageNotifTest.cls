/**
 * Tests for the Latona_Opportunity_Stage_Notifications Flow (stage change / won / lost notifications).
 * Custom notifications and emails are not delivered in tests, so the tests verify that every path
 * runs without blocking the Opportunity save, including bulk updates.
 */
@IsTest
private class LatonaOpportunityStageNotifTest {
    @TestSetup
    static void setup() {
        Id profileId = [SELECT Id FROM Profile WHERE Name = 'Latona Sales' LIMIT 1].Id;
        Map<String, Id> roleIds = new Map<String, Id>();
        for (UserRole r : [SELECT Id, DeveloperName FROM UserRole WHERE DeveloperName IN ('Sales_Manager', 'Sales_Rep')]) {
            roleIds.put(r.DeveloperName, r.Id);
        }
        String suffix = String.valueOf(Crypto.getRandomInteger()).remove('-');
        insert new List<User>{
            newUser('mgr', 'Manager' + suffix, profileId, roleIds.get('Sales_Manager')),
            newUser('rep', 'Rep' + suffix, profileId, roleIds.get('Sales_Rep'))
        };
    }

    private static User newUser(String alias, String lastName, Id profileId, Id roleId) {
        String username = lastName.toLowerCase() + '@latona-test.example.com';
        return new User(
            LastName = lastName, Email = username, Username = username, Alias = alias,
            ProfileId = profileId, UserRoleId = roleId, TimeZoneSidKey = 'Europe/Kyiv',
            LocaleSidKey = 'uk_UA', LanguageLocaleKey = 'en_US', EmailEncodingKey = 'UTF-8'
        );
    }

    private static User userByAlias(String alias) {
        return [SELECT Id FROM User WHERE Alias = :alias AND Email LIKE '%@latona-test.example.com' LIMIT 1];
    }

    private static List<Opportunity> newOpportunities(Integer count, Id ownerId) {
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < count; i++) {
            opps.add(new Opportunity(
                Name = 'Business cards ' + i, StageName = 'Request', CloseDate = Date.today().addDays(14),
                Amount = 900, OwnerId = ownerId
            ));
        }
        insert opps;
        return opps;
    }

    private static void assertStage(List<Opportunity> opps, String stage) {
        for (Opportunity o : [SELECT StageName FROM Opportunity WHERE Id IN :opps]) {
            Assert.areEqual(stage, o.StageName);
        }
    }

    @IsTest
    static void repChangesOwnStageNotifiesManagers() {
        User rep = userByAlias('rep');
        List<Opportunity> opps;
        System.runAs(rep) {
            opps = newOpportunities(1, rep.Id);
            Test.startTest();
            opps[0].StageName = 'Quote Sent';
            update opps;
            Test.stopTest();
        }
        assertStage(opps, 'Quote Sent');
    }

    @IsTest
    static void managerWinsRepOpportunityNotifiesOwner() {
        User rep = userByAlias('rep');
        List<Opportunity> opps = newOpportunities(1, rep.Id);
        System.runAs(userByAlias('mgr')) {
            Test.startTest();
            opps[0].StageName = 'Closed Won';
            update opps;
            Test.stopTest();
        }
        assertStage(opps, 'Closed Won');
    }

    @IsTest
    static void lostOpportunityNotifies() {
        List<Opportunity> opps = newOpportunities(1, userByAlias('rep').Id);
        Test.startTest();
        opps[0].StageName = 'Closed Lost';
        update opps;
        Test.stopTest();
        assertStage(opps, 'Closed Lost');
    }

    @IsTest
    static void unrelatedEditDoesNotTrigger() {
        List<Opportunity> opps = newOpportunities(1, userByAlias('rep').Id);
        Test.startTest();
        opps[0].Amount = 1200;
        update opps;
        Test.stopTest();
        assertStage(opps, 'Request');
    }

    @IsTest
    static void bulkStageChange() {
        List<Opportunity> opps = newOpportunities(200, userByAlias('rep').Id);
        Test.startTest();
        for (Opportunity o : opps) o.StageName = 'Done';
        update opps;
        Test.stopTest();
        assertStage(opps, 'Done');
    }
}
