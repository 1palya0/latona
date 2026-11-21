/**
 * Tests for the Latona_Website_Request_Intake Flow (website request routing).
 */
@IsTest
private class LatonaWebsiteRequestIntakeTest {
    private static Map<String, Object> runIntake(Map<String, Object> inputs) {
        Flow.Interview interview = Flow.Interview.createInterview('Latona_Website_Request_Intake', inputs);
        interview.start();
        return new Map<String, Object>{
            'result' => interview.getVariableValue('outResult'),
            'recordId' => interview.getVariableValue('outRecordId')
        };
    }

    private static Map<String, Object> request(String email) {
        return new Map<String, Object>{
            'inFirstName' => 'Iryna',
            'inLastName' => 'Shevchenko',
            'inEmail' => email,
            'inPhone' => '+380501234567',
            'inProductRequested' => 'Business cards',
            'inFormat' => '90x50 mm',
            'inQuantity' => 500,
            'inDeadline' => Date.today().addDays(7),
            'inComment' => 'Matte coating, please'
        };
    }

    @IsTest
    static void createsLeadWhenEmailIsUnknown() {
        Test.startTest();
        Map<String, Object> out = runIntake(request('new.customer@example.com'));
        Test.stopTest();

        Assert.areEqual('LeadCreated', out.get('result'));
        Lead created = [
            SELECT LeadSource, Status, Company, Product_Requested__c, Format__c, Quantity__c, Deadline__c, Comment__c
            FROM Lead
            WHERE Id = :(Id) out.get('recordId')
        ];
        Assert.areEqual('Website', created.LeadSource);
        Assert.areEqual('New', created.Status);
        Assert.areEqual('Iryna Shevchenko', created.Company, 'Company falls back to the person name');
        Assert.areEqual('Business cards', created.Product_Requested__c);
        Assert.areEqual('90x50 mm', created.Format__c);
        Assert.areEqual(500, created.Quantity__c);
        Assert.areEqual(Date.today().addDays(7), created.Deadline__c);
        Assert.areEqual('Matte coating, please', created.Comment__c);
    }

    @IsTest
    static void updatesOpenLeadAndAddsTask() {
        Lead existing = new Lead(
            LastName = 'Shevchenko',
            Company = 'Old Co',
            Email = 'repeat@example.com',
            Status = 'Working',
            Product_Requested__c = 'Flyers',
            Comment__c = 'First comment'
        );
        insert existing;

        Map<String, Object> inputs = request('REPEAT@example.com');
        inputs.remove('inComment');

        Test.startTest();
        Map<String, Object> out = runIntake(inputs);
        Test.stopTest();

        Assert.areEqual('LeadUpdated', out.get('result'));
        Assert.areEqual(existing.Id, (Id) out.get('recordId'));
        Assert.areEqual(1, [SELECT COUNT() FROM Lead], 'No new Lead is created');

        Lead updated = [SELECT Product_Requested__c, Quantity__c, Comment__c FROM Lead WHERE Id = :existing.Id];
        Assert.areEqual('Business cards', updated.Product_Requested__c);
        Assert.areEqual(500, updated.Quantity__c);
        Assert.areEqual('First comment', updated.Comment__c, 'Blank comment keeps the previous one');

        Task t = [SELECT Subject, Description, OwnerId, Status FROM Task WHERE WhoId = :existing.Id];
        Assert.areEqual('New website request', t.Subject);
        Assert.areEqual(UserInfo.getUserId(), t.OwnerId);
        Assert.isTrue(t.Description.contains('Business cards'));
    }

    @IsTest
    static void replacesLeadCommentWhenProvided() {
        Lead existing = new Lead(LastName = 'Shevchenko', Company = 'Old Co', Email = 'again@example.com', Comment__c = 'Old');
        insert existing;

        Test.startTest();
        runIntake(request('again@example.com'));
        Test.stopTest();

        Assert.areEqual('Matte coating, please', [SELECT Comment__c FROM Lead WHERE Id = :existing.Id].Comment__c);
    }

    @IsTest
    static void ignoresUnqualifiedLead() {
        insert new Lead(LastName = 'Old', Company = 'Old Co', Email = 'cold@example.com', Status = 'Unqualified');

        Test.startTest();
        Map<String, Object> out = runIntake(request('cold@example.com'));
        Test.stopTest();

        Assert.areEqual('LeadCreated', out.get('result'));
        Assert.areEqual(2, [SELECT COUNT() FROM Lead WHERE Email = 'cold@example.com']);
    }

    @IsTest
    static void createsOpportunityForExistingContact() {
        Account acc = new Account(Name = 'Druk LLC');
        insert acc;
        Contact con = new Contact(LastName = 'Shevchenko', Email = 'client@example.com', AccountId = acc.Id);
        insert con;

        Test.startTest();
        Map<String, Object> out = runIntake(request('client@example.com'));
        Test.stopTest();

        Assert.areEqual('OpportunityCreated', out.get('result'));
        Assert.areEqual(0, [SELECT COUNT() FROM Lead], 'No Lead is created for a known Contact');

        Opportunity opp = [
            SELECT Name, AccountId, StageName, LeadSource, CloseDate, OwnerId, Description
            FROM Opportunity
            WHERE Id = :(Id) out.get('recordId')
        ];
        Assert.areEqual(acc.Id, opp.AccountId);
        Assert.areEqual('Request', opp.StageName);
        Assert.areEqual('Website', opp.LeadSource);
        Assert.areEqual('Druk LLC - Business cards', opp.Name);
        Assert.areEqual(Date.today().addDays(7), opp.CloseDate);
        Assert.isTrue(opp.Description.contains('Matte coating'));

        OpportunityContactRole role = [SELECT ContactId, IsPrimary FROM OpportunityContactRole WHERE OpportunityId = :opp.Id];
        Assert.areEqual(con.Id, role.ContactId);
        Assert.isTrue(role.IsPrimary);
    }

    @IsTest
    static void createsLeadWhenEmailIsMissing() {
        Map<String, Object> inputs = request(null);
        inputs.put('inLastName', null);

        Test.startTest();
        Map<String, Object> out = runIntake(inputs);
        Test.stopTest();

        Assert.areEqual('LeadCreated', out.get('result'));
        Lead created = [SELECT LastName FROM Lead WHERE Id = :(Id) out.get('recordId')];
        Assert.areEqual('Website visitor', created.LastName);
    }
}
