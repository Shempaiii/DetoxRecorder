//
//  GBOptionsHelper.h
//  GBCli
//
//  Created by Tomaž Kragelj on 3/15/12.
//  Copyright (c) 2012 Tomaz Kragelj. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GBCommandLineParser.h"

@class GBCommandLineParser;
@class GBSettings;

/** Various option flags. You can also use GBValueRequirement values here! */
typedef NS_OPTIONS(NSUInteger, GBOptionFlags) {
	GBOptionRequiredValue = 0, ///< Command line argument requires a value.
	GBOptionOptionalValue = 1 << 0, ///< Command line argument can optionally have a value, but is not required.
	GBOptionNoValue = 1 << 1,///< Command line argument is on/off switch.
	GBOptionSeparator = 1 << 3, ///< Option is separator, not real option definition.
	GBOptionGroup = 1 << 4,	///< Option is an option gorup, not actual option definition.
	GBOptionNoCmdLine = 1 << 5, ///< Option is not used on command line, don't register to parser.
	GBOptionNoPrint = 1 << 6, ///< Option should be excluded from print settings display.
	GBOptionNoHelp = 1 << 7, ///< Option should be excluded from help display.
	GBOptionInvisible = GBOptionNoPrint | GBOptionNoHelp,
};

/** Description of a single option or separator. */
typedef struct {
	__unsafe_unretained NSString *shortOption; ///< Short option char or `0` if not used.
	__unsafe_unretained NSString *longOption; ///< Long option name - required for options.
	__unsafe_unretained NSString *description; ///< Description of the option.
	GBOptionFlags flags; ///< Various flags.
} GBOptionDefinition;

/** Block used to fetch strings from user code. */
typedef NSString *(^GBOptionStringBlock)(void);

#pragma mark - 

/** Helper class for nicer integration between GBSettings and GBCommandLineParser.
 
 Although using this class is optional, it provides several nice features and automations out of the box (although you can subclass if your want to customize):
 
 - Registration of options to GBCommandLineParser.
 - Print version information (subclass to customize).
 - Print help (subclass to customize).
 - Print values, preserving their GBSettings level hierarchy (subclass to customize).
 
 One example of usage:
 
 ```
 int main(int argc, char **argv) {
 	GBSettings *factory = [GBSettings settingsWithName:@"Factory" parent:nil];
 	GBSettings *settings = [GBSettings settingsWithName@"CmdLine" parent:factory];
 
 	OptionsHelper *options = [[OptionsHelper alloc] init];
 	[options registerSeparator:@"PATHS"];
 	[options registerOption:'i' long:@"input" description:@"Input path" flags:GBValueRequired];
 	[options registerOption:'o' long:@"output" description:@"Output path" flags:GBValueRequired];
 	[options registerSeparator:@"MISCELLANEOUS"];
 	[options registerOption:0 long:@"version" description:@"Display version and exit" flags:GBValueNone|GBOptionNoPrint];
 	[options registerOption:'?' long:@"help" description:@"Display this help and exit" flags:GBValueNone|GBOptionNoPrint];
 
 	GBCommandLineParser *parser = [[GBCommandLineParser alloc] init];
 	[options registerOptionsToCommandLineParser:parser];
 	__block BOOL commandLineValid = YES;
 	__block BOOL finished = NO;
 	[parser parseOptionsWithArguments:argv count:argc block:^(NSString *argument, id value, BOOL *stop) {
 		if (value == GBCommandLineArgumentResults.unknownArgument) {
 			// unknown argument
 			commandLineValid = NO;
 			*stop = YES;
 		} else if (value == GBCommandLineArgumentResults.missingValue) {
 		// known argument but missing value
 		commandLineValid = NO;
 		*stop = YES;
 		} else if ([argument isEqualToString:@"version"]) {
 			[options printVersion];
 			finished = YES;
 			*stop = YES;
 		} else if ([argument isEqualToString:@"help"]) {
 			[options printHelp];
 			finished = YES;
 			*stop = YES;
 		} else {
 			[settings setObject:value forKey:argument];
 		}
 	}];
 
 	if (finished) return 0;
 	if (!commandLineValue) return 1;
 
 	[options printValuesFromSettings:settings];
 	return 0;
 }
 ```
 
 There are several hooks by which you can inject text into default output. The hooks use block API, for example printValuesHeader, printHelpHeader etc. An example:
 
 ```
 int main(int argc, char **argv) {
	...
	GBOptionsHelper *options = [[OptionsHelper alloc] init];
	options.printHelpHeader = ^{ return @"Usage: MyTool [OPTIONS] <arguments separated by space>"; };
	options.printHelpFooter = ^{ return @"Thanks to everyone for their help..."; };
	...
 }
 ```
 
 These blocks are automatically invoked when and if necessary. The strings you return from them can contain several placeholders:
 
 - `%APPNAME` is replaced by the application name, either the value returned from applicationName, or auto-generated by GBOptionsHelper itself.
 - `%APPVERSION` is replaced by the application version, if given via applicationVersion block or empty string otherwise.
 - `%APPBUILD` is replaced by the application build number, if given via applicationBuild block or empty strings otherwise.
 
 @warning **Note:** Only values from blocks related to printing text are checked for placeholders, applicationName, applicationVersion and applicationBuild aren't!
 */
@interface GBOptionsHelper : NSObject

#pragma mark - Options registration

- (void)registerOptionsFromDefinitions:(GBOptionDefinition *)definitions; // this mode doesn't support option groups at this moment!
- (void)registerSeparator:(NSString *)description;
- (void)registerGroup:(NSString *)name description:(NSString *)description optionsBlock:(void(^)(GBOptionsHelper *options))block;
- (void)registerGroup:(NSString *)name description:(NSString *)description flags:(GBOptionFlags)flags optionsBlock:(void(^)(GBOptionsHelper *options))block;
- (void)registerOption:(NSString *)shortName long:(NSString *)longName description:(NSString *)description flags:(GBOptionFlags)flags;

#pragma mark - Integration with other components

- (void)registerOptionsToCommandLineParser:(GBCommandLineParser *)parser;

#pragma mark - Diagnostic info

- (void)printValuesFromSettings:(GBSettings *)settings;
- (void)printVersion;
- (void)printHelp;

#pragma mark - Getting information from user

@property (nonatomic, copy) GBOptionStringBlock applicationName;
@property (nonatomic, copy) GBOptionStringBlock applicationVersion;
@property (nonatomic, copy) GBOptionStringBlock applicationBuild;

#pragma mark - Hooks for injecting text to output

@property (nonatomic, copy) GBOptionStringBlock printValuesHeader;
@property (nonatomic, copy) GBOptionStringBlock printValuesArgumentsHeader;
@property (nonatomic, copy) GBOptionStringBlock printValuesOptionsHeader;
@property (nonatomic, copy) GBOptionStringBlock printValuesFooter;

@property (nonatomic, copy) GBOptionStringBlock printHelpHeader;
@property (nonatomic, copy) GBOptionStringBlock printHelpFooter;

@end

#pragma mark - 

@interface GBCommandLineParser (GBOptionsHelper)
- (void)registerOptions:(GBOptionsHelper *)options;
@end