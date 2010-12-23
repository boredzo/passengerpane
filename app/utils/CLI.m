#import "CLI.h"

@implementation CLI

static id sharedCLI = nil;

+ (id)sharedInstance{
  if (sharedCLI == nil) {
    sharedCLI = [[CLI alloc] init];
  }
  return sharedCLI;
}

@synthesize appDelegate, pathToCLI;

- (id)init {
  if ((self = [super init])) {
    authorizationRef = NULL;
  }
  return self;
}

- (NSMutableArray *)listApplications {
  NSArray *result;
  Application *application;
  NSDictionary *attributes;
  NSMutableArray *applications;
  
  NSLog(@"Retrieving a list of configured applications");
  result = [self execute:[NSArray arrayWithObjects:@"list", @"-m", nil] elevated:NO];
  applications = [NSMutableArray arrayWithCapacity:[result count]];
  
  for (attributes in result) {
    application = [[Application alloc] initWithAttributes:attributes];
    [application setDelegate:appDelegate];
    [applications addObject:application];
  }
  
  return applications;
}

- (void) add:(Application *)application {
  NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"add", application.path, nil];
  [arguments addObjectsFromArray:[application toArgumentArray]];
  NSLog(@"Adding application with hostname %@ using %@", application.host, arguments);
  [self execute:arguments elevated:YES];
  [application didApplyChanges];
}

- (void) update:(Application *)application {
  NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"update", application.host, nil];
  [arguments addObjectsFromArray:[application toArgumentArray]];
  NSLog(@"Updating application with hostname %@ using %@", application.host, arguments);
  [self execute:arguments elevated:YES];
  [application didApplyChanges];
}

- (void) delete:(Application *)application {
  NSLog(@"Deleting application with hostname: %@", application.host);
  [self execute:[NSArray arrayWithObjects:@"delete", application.host, nil] elevated:YES];
}

- (void) restart:(Application *)application {
  NSLog(@"Restarting application with hostname: %@", application.host);
  [self execute:[NSArray arrayWithObjects:@"restart", application.host, nil] elevated:NO];
}

- (void) restart {
  NSLog(@"Restarting Apache");
  [self execute:[NSArray arrayWithObject:@"restart"] elevated:YES];
}

// Inspired by: http://svn.kismac-ng.org/kmng/trunk/Subprojects/BIGeneric/BLAuthentication.m
- (id) execute:(NSArray *)arguments elevated:(BOOL)elevated {
  OSStatus status;
  char **argumentsAsCArray = NULL;
  unsigned int index;
  
  FILE *communicationPipe;
  NSString *data;
  NSFileHandle *file;
  
  if (elevated) {
    if ([self isAuthorized]) {
      if ([arguments count] > 0) {
        index = 0;
        argumentsAsCArray = malloc(sizeof(char*)*[arguments count]);
        while(index < [arguments count]) {
          argumentsAsCArray[index++] = (char*)[[arguments objectAtIndex:index] UTF8String];
        }
        argumentsAsCArray[index] = NULL;
      }
      
      status = AuthorizationExecuteWithPrivileges(authorizationRef, [pathToCLI UTF8String],
                                                  kAuthorizationFlagDefaults, argumentsAsCArray,
                                                  &communicationPipe);
      free(argumentsAsCArray);
      
      if (status == PPANE_SUCCESS) {
        if (communicationPipe) {
          file = [[NSFileHandle alloc] initWithFileDescriptor:fileno(communicationPipe)];
          data = [[NSString alloc] initWithData:[file readDataToEndOfFile] encoding:NSUTF8StringEncoding];
          [file closeFile];
          if ([data isEqual:@""]) {
            NSLog(@"ppane didn't return any information");
          } else {
            NSLog(@"ppane returned: %@", data);
            return yaml_parse(data);
          }
        }
      } else {
        NSLog(@"AuthorizationExecuteWithPrivileges failed to execute ppane (%d)", status);
      }
    } else {
      NSLog(@"Ignoring a privileged command because the pane isn't authorized");
    }
    return [NSDictionary dictionary];
  } else {
    return [self execute:arguments];
  }
}

- (id)execute:(NSArray *)arguments {
  NSString *data;
  NSPipe *stdout = [NSPipe pipe];
  NSTask *ppane;
  
  ppane = [[NSTask alloc] init];
  [ppane setLaunchPath:pathToCLI];
  [ppane setArguments:arguments];
  [ppane setStandardOutput:stdout];
  [ppane launch];
  [ppane waitUntilExit];
  
  if ([ppane terminationStatus] == PPANE_SUCCESS) {
    data = [[NSString alloc] initWithData:[[stdout fileHandleForReading] readDataToEndOfFile] encoding:NSUTF8StringEncoding];
    return yaml_parse(data);
  } else {
    NSLog(@"NSTask failed to execute the command");
    return [NSDictionary dictionary];
  }
}

- (AuthorizationRef) authorizationRef {
  return authorizationRef;
}

- (void) setAuthorizationRef:(AuthorizationRef)ref {
  authorizationRef = ref;
}

-(void)deauthorize {
  authorizationRef = NULL;
}

-(BOOL)isAuthorized {
  if (authorizationRef == NULL) {
    return NO;
  } else  {
    return YES;
  }
}


@end
