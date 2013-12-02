//
//  KXContactsViewController.m
//  KuXue
//
//  Created by Yang Yi Feng on 11/12/13.
//  Copyright (c) 2013 kuxue.me. All rights reserved.
//

#import "KXContactsTableViewController.h"

@interface KXContactsTableViewController ()

@end

@protocol KXContact
- (NSString *)getSortableName;
@end

@implementation KXContactsTableViewController

@synthesize contacts = _contacts;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    [self initMockData];
    
    KXAppDelegate *delegate = [self appDelegate];
    delegate.chatDelegate = self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if ([[self appDelegate] connect]) {
        [[self appDelegate] goOnline];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

#pragma mark - Initializations

- (void)initMockData
{
    // Fetches the application mock data.
    
    NSManagedObjectContext *context = [self managedObjectContext];
    
    NSFetchRequest *request = [[NSFetchRequest alloc] initWithEntityName:@"KXContact"];
    NSMutableArray *raw = [[context executeFetchRequest:request error:nil] mutableCopy];
    self.contacts = [self partitionObjects:raw collationStringSelector:@selector(getSortableName)];
    
    // Reloads table data every time this view appears.
    
    [self.tableView reloadData];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return [[[UILocalizedIndexedCollation currentCollation] sectionTitles] count];
}

- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    return [[UILocalizedIndexedCollation currentCollation] sectionIndexTitles];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    BOOL showSection = [[self.contacts objectAtIndex:section] count] != 0;
    return showSection ? [[[UILocalizedIndexedCollation currentCollation] sectionTitles] objectAtIndex:section] : nil;
}

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index
{
    return [[UILocalizedIndexedCollation currentCollation] sectionForSectionIndexTitleAtIndex:index];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[self.contacts objectAtIndex:section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"contactsTableViewCell";
    KXContactsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier forIndexPath:indexPath];
    
    KXContact *contact = [[self.contacts objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
    cell.contactAvatarImageView.image = [UIImage imageNamed:contact.contactAvatar];
    cell.contactNameLabel.text = contact.contactName;
    
    return cell;
}

#pragma mark - Navigation

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"pushContactFromContacts"]) {
        NSIndexPath *indexPath = [self.tableView indexPathForSelectedRow];
        KXContact *contact = [[self.contacts objectAtIndex:indexPath.section] objectAtIndex:indexPath.row];
        
        KXContactTableViewController *contactTableViewController = segue.destinationViewController;
        contactTableViewController.theme = contact.theme;
        contactTableViewController.contactName = contact.contactName;
        contactTableViewController.contactAvatar = contact.contactAvatar;
        
        contactTableViewController.hidesBottomBarWhenPushed = YES;
    }
}

#pragma mark - Core Data

- (NSManagedObjectContext *)managedObjectContext
{
    NSManagedObjectContext *context = nil;
    id delegate = [[UIApplication sharedApplication] delegate];
    if ([delegate performSelector:@selector(managedObjectContext)]) {
        context = [delegate managedObjectContext];
    }
    
    return context;
}

#pragma mark - Contacts Partition

-(NSMutableArray *)partitionObjects:(NSArray *)array collationStringSelector:(SEL)selector
{
    UILocalizedIndexedCollation *collation = [UILocalizedIndexedCollation currentCollation];
    
    // Section count is taken from sectionTitles, not sectionIndexTitles.
    NSInteger sectionCount = [[collation sectionTitles] count];
    NSMutableArray *unsortedSections = [NSMutableArray arrayWithCapacity:sectionCount];
    
    // Creates an array to hold the data for each section.
    for (int i = 0; i < sectionCount; i++) {
        [unsortedSections addObject:[NSMutableArray array]];
    }
    
    // Puts each object into a section.
    for (id object in array) {
        NSInteger index = [collation sectionForObject:object collationStringSelector:selector];
        [[unsortedSections objectAtIndex:index] addObject:object];
    }
    
    NSMutableArray *sections = [NSMutableArray arrayWithCapacity:sectionCount];
    
    // Sorts each section.
    for (NSMutableArray *section in unsortedSections) {
        [sections addObject:[collation sortedArrayFromArray:section collationStringSelector:selector]];
    }
    
    return sections;
}

#pragma mark - XMPP

- (KXAppDelegate *)appDelegate
{
    return (KXAppDelegate *)[[UIApplication sharedApplication] delegate];
}

- (XMPPStream *)xmppStream
{
    return [[self appDelegate] xmppStream];
}

- (XMPPRoster *)xmppRoster
{
    return [[self appDelegate] xmppRoster];
}

#pragma mark - Chat Delegate

- (void)newContactOnline:(NSString *)contactName
{
    for (KXContact *contact in self.contacts) {
        if ([contact.contactName isEqualToString:contactName]) {
            return;
        }
    }
    
    NSManagedObjectContext *context = [self managedObjectContext];
    KXContact *newContact = [NSEntityDescription insertNewObjectForEntityForName:@"KXContact" inManagedObjectContext:context];
    newContact.contactAvatar = @"liukun.jpg";
    newContact.contactName = contactName;
    newContact.mobile = @"13810502314";
    newContact.theme = @"theme-3.jpg";
    
    [context insertObject:newContact];
    NSError *error;
    if (![context save:&error]) {
        NSLog(@"Data not inserted. %@, %@", error, [error userInfo]);
        return;
    }
    [self.contacts addObject:newContact];
    [self.tableView reloadData];
}

- (void)contactWentOffline:(NSString *)contactName
{
    [self.contacts removeObject:contactName];
    [self.tableView reloadData];
}

- (void)didDisconnect
{
    [self.contacts removeAllObjects];
    [self.tableView reloadData];
}

@end
