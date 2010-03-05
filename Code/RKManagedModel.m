//
//  RKManagedModel.m
//  RestKit
//
//  Created by Blake Watters on 8/14/09.
//  Copyright 2009 Two Toasters. All rights reserved.
//

#import "RKManagedModel.h"
#import "NSString+InflectionSupport.h"
#import <objc/runtime.h>

@implementation RKManagedModel

#pragma mark -
#pragma mark NSManagedObject helper methods

+ (NSManagedObjectContext*)managedObjectContext {
	return [[[RKModelManager manager] objectStore] managedObjectContext];
}

+ (NSEntityDescription*)entity {
	NSString* className = [NSString stringWithCString:class_getName([self class]) encoding:NSASCIIStringEncoding];
	return [NSEntityDescription entityForName:className inManagedObjectContext:[self managedObjectContext]];
}

+ (NSFetchRequest*)request {
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	NSEntityDescription *entity = [self entity];
	[request setEntity:entity];
	[request autorelease];
	return request;
}

+ (NSArray*)collectionWithRequest:(NSFetchRequest*)request {
	NSError* error = nil;
//	NSLog(@"About to perform a collection request: %@", request);
	NSArray* collection = [[self managedObjectContext] executeFetchRequest:request error:&error];
	if (error != nil) {
		NSLog(@"Error: %@", [error localizedDescription]);
		// TODO: Error handling
	}
	return collection;
}

+ (id)objectWithRequest:(NSFetchRequest*)request {
	[request setFetchLimit:1];
	NSArray* collection = [self collectionWithRequest:request];
	if ([collection count] == 0) {
		return nil;
	} else {
		return [collection objectAtIndex:0];
	}	
}

+ (NSArray*)collectionWithPredicate:(NSPredicate*)predicate {
	NSFetchRequest* request = [self request];
	[request setPredicate:predicate];
	return [self collectionWithRequest:request];
}

+ (id)objectWithPredicate:(NSPredicate*)predicate {
	NSFetchRequest* request = [self request];
	[request setPredicate:predicate];
	return [self objectWithRequest:request];
}

+ (NSArray*)allObjects {
	return [self collectionWithPredicate:nil];
}

+ (NSUInteger)count {
	NSFetchRequest *request = [self request];	
	NSError *error = nil;
	NSUInteger count = [[self managedObjectContext] countForFetchRequest:request error:&error];
	// TODO: Error handling...
	return count;
}

+ (id)newObject {
	id model = [[self alloc] initWithEntity:[self entity] insertIntoManagedObjectContext:[self managedObjectContext]];
	return [model autorelease];
}

#pragma mark -
#pragma mark Object Cacheing

+ (NSArray*)objectsForResourcePath:(NSString*)resourcePath {
	return nil;
}

+ (RKManagedModel*)objectForResourcePath:(NSString*)resourcePath {
	return nil;
}

#pragma mark -
#pragma mark RKModelMappable

// TODO: All this path shit needs cleaning up...
- (NSString*)resourcePath {
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

- (NSString*)collectionPath {
	return [NSString stringWithFormat:@"%@", [self resourcePath]];
}

- (NSString*)memberPath {
	NSLog(@"Was asked for memberPath. primaryKeyValue is %@. self = %@", [self valueForKey:[[self class] primaryKey]], self);
	return [NSString stringWithFormat:@"%@/%@", [self resourcePath], [self valueForKey:[[self class] primaryKey]]];
}

// TODO: Would be nice to specify this via an annotation in the mappings definition...
+ (NSString*)primaryKey {
	return @"railsID";
}

// TODO: Would be nice to specify this via an annotation in the mappings definition...
+ (NSString*)primaryKeyElement {
	return @"id";
}

/**
 * TODO: Unwind assumptions about the primaryKey
 *
 * Right now we make the blanket assumption that Primary Keys are stored as NSNumber values. We
 * cast from NSStrings into NSNumbers to fix a weird bug Jeremy encountered with the subtle predicate
 * differences causes nil return values in some cases. This needs to be better understood and the assumptions
 * unwound.
 */
+ (id)findByPrimaryKey:(id)value {
	id primaryKeyValue = nil;
	if ([value isKindOfClass:[NSString class]]) {
		// Cast from string to a number
		primaryKeyValue = [NSNumber numberWithInt:[(NSString*)value integerValue]];
	} else {
		// Make blind assumption here.
		primaryKeyValue = value;
	}
	NSPredicate* predicate = [NSPredicate predicateWithFormat:@"%K = %@", [self primaryKey], primaryKeyValue];
 	return [self objectWithPredicate:predicate];
}

+ (NSDictionary*)elementToPropertyMappings {
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

+ (NSDictionary*)elementToRelationshipMappings {
	return [NSDictionary dictionary];
}

+ (NSArray*)elementNames {
	return [[self elementToPropertyMappings] allKeys];
}

+ (NSArray*)propertyNames {
	return [[self elementToPropertyMappings] allValues];
}

+ (NSString*)formatElementName:(NSString*)elementName forMappingFormat:(RKMappingFormat)format {
	if (RKMappingFormatXML == format) {
		return [[elementName camelize] dasherize];
	} else if (RKMappingFormatJSON == format) {
		return [[elementName camelize] underscore];
	}
	
	return elementName;
}

// TODO: I get eliminated...
+ (NSString*)modelName {
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

#pragma mark Helpers

- (NSDictionary*)elementNamesAndPropertyValues {
	NSDictionary* mappings = [[self class] elementToPropertyMappings];
	NSMutableDictionary* elementsAndPropertyValues = [NSMutableDictionary dictionaryWithCapacity:[mappings count]];
	// Return all the properties of this model in a dictionary under their element names
	for (NSString* elementName in mappings) {
		NSString* propertyName = [mappings valueForKey:elementName];
		id propertyValue = [self valueForKey:propertyName];
		[elementsAndPropertyValues setValue:propertyValue forKey:elementName];
	}
	
	return (NSDictionary*) elementsAndPropertyValues;
}

// TODO: This implementation is Rails specific. Consider using an adapter approach.
// TODO: Gets handled in a Rails adapter, moved completely off the model itself...
- (NSDictionary*)resourceParams {
	NSDictionary* elementsAndProperties = [self elementNamesAndPropertyValues];
	NSMutableDictionary* resourceParams = [NSMutableDictionary dictionaryWithCapacity:[elementsAndProperties count]];
	// TODO: Eliminate modelName somehow... should be using the name of the element this class was registered for!
	NSString* underscoredModelName = [[[self class] modelName] underscore];
	for (NSString* elementName in [elementsAndProperties allKeys]) {
		id value = [elementsAndProperties valueForKey:elementName];
		NSString* attributeName = [elementName stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
		if (![attributeName isEqualToString:@"id"]) {
			NSString* keyName = [NSString stringWithFormat:@"%@[%@]", underscoredModelName, attributeName];
			[resourceParams setValue:value forKey:keyName];
		}
	}
	
	return resourceParams;
}

// TODO: Gets moved off of the model itself.
- (NSError*)save {
	NSError* error = nil;
	[[self managedObjectContext] save:&error];
	if (nil != error) {
		NSLog(@"Error saving persistent store: %@", error);
	}
	return error;
}

// TODO: Delete on the server also? See above.
// TODO: Gets moved off of the model itself...
- (void)destroy {	
	[[self managedObjectContext] deleteObject:self];
}

@end
