// Creates the two Latona sales users (spec, section 1) and assigns roles + permission sets.
// Prerequisites (deploy first): profile "Latona Sales", roles Sales_Manager / Sales_Rep,
// permission sets Latona_Sales_Manager / Latona_Sales_Rep.
// Idempotent: skips users whose Username already exists. No welcome e-mail is sent here;
// use "Reset Password" in Setup > Users when the users should get their login link.

Id profileId = [SELECT Id FROM Profile WHERE Name = 'Latona Sales' LIMIT 1].Id;
Map<String, Id> roleIds = new Map<String, Id>();
for (UserRole r : [SELECT Id, DeveloperName FROM UserRole WHERE DeveloperName IN ('Sales_Manager', 'Sales_Rep')]) {
    roleIds.put(r.DeveloperName, r.Id);
}
Map<String, Id> psIds = new Map<String, Id>();
for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('Latona_Sales_Manager', 'Latona_Sales_Rep')]) {
    psIds.put(ps.Name, ps.Id);
}

// firstName, lastName, email, alias, role, permission set
List<List<String>> specs = new List<List<String>>{
    new List<String>{ 'Olena',  'Kovalenko', 'olena.kovalenko@latona.lviv.ua', 'okova', 'Sales_Manager', 'Latona_Sales_Manager' },
    new List<String>{ 'Maksym', 'Tkachuk',   'maksym.tkachuk@latona.lviv.ua',  'mtkac', 'Sales_Rep',     'Latona_Sales_Rep' }
};

Set<String> usernames = new Set<String>();
for (List<String> s : specs) usernames.add(s[2]);
Set<String> existing = new Set<String>();
for (User u : [SELECT Username FROM User WHERE Username IN :usernames]) existing.add(u.Username);

List<User> toInsert = new List<User>();
Map<String, String> psByUsername = new Map<String, String>();
for (List<String> s : specs) {
    if (existing.contains(s[2])) { System.debug('SKIP existing user ' + s[2]); continue; }
    toInsert.add(new User(
        FirstName = s[0], LastName = s[1], Email = s[2], Username = s[2], Alias = s[3],
        CommunityNickname = s[3], ProfileId = profileId, UserRoleId = roleIds.get(s[4]),
        TimeZoneSidKey = 'Europe/Kyiv', LocaleSidKey = 'uk_UA', LanguageLocaleKey = 'en_US',
        EmailEncodingKey = 'UTF-8'
    ));
    psByUsername.put(s[2], s[5]);
}
insert toInsert;

List<PermissionSetAssignment> psas = new List<PermissionSetAssignment>();
for (User u : toInsert) {
    psas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = psIds.get(psByUsername.get(u.Username))));
}
insert psas;
System.debug('Created users: ' + toInsert.size());
