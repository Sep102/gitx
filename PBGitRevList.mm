//
//  PBGitRevList.m
//  GitX
//
//  Created by Pieter de Bie on 17-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRevList.h"
#import "PBGitRepository.h"
#import "PBGitCommit.h"
#import "PBGitGrapher.h"
#import "PBGitRevSpecifier.h"

#include <iostream>
#include <string>
#include <map>

using namespace std;


@interface PBGitRevList ()

@property (assign) BOOL isParsing;

@end


#define kRevListThreadKey @"thread"
#define kRevListRevisionsKey @"revisions"


@implementation PBGitRevList

@synthesize commits;
@synthesize isParsing;


- (id) initWithRepository:(PBGitRepository *)repo rev:(PBGitRevSpecifier *)rev shouldGraph:(BOOL)graph
{
	repository = repo;
	isGraphing = graph;
	currentRev = [rev copy];

	return self;
}


- (void) loadRevisons
{
	[parseThread cancel];

	parseThread = [[NSThread alloc] initWithTarget:self selector:@selector(walkRevisionListWithSpecifier:) object:currentRev];
	self.isParsing = YES;
	resetCommits = YES;
	[parseThread start];
}


- (void)cancel
{
	[parseThread cancel];
}


- (void) finishedParsing
{
	self.isParsing = NO;
}


- (void) updateCommits:(NSDictionary *)update
{
	if ([update objectForKey:kRevListThreadKey] != parseThread)
		return;

	NSArray *revisions = [update objectForKey:kRevListRevisionsKey];
	if (!revisions || [revisions count] == 0)
		return;

	if (resetCommits) {
		self.commits = [NSMutableArray array];
		resetCommits = NO;
	}

	NSRange range = NSMakeRange([commits count], [revisions count]);
	NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:range];

	[self willChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"commits"];
	[commits addObjectsFromArray:revisions];
	[self didChange:NSKeyValueChangeInsertion valuesAtIndexes:indexes forKey:@"commits"];
}


NSString *getLine(FILE *f, int delim = '\1')
{
    static char *s = NULL;
    static size_t len = 0;

    if (f == NULL) {
        return nil;
    }

    ssize_t read = getdelim(&s, &len, delim, f);
    if (read <= 0) {
        return nil;
    }

    s[read - 1] = '\0';
    return [NSString stringWithUTF8String:s];
}

- (void) walkRevisionListWithSpecifier:(PBGitRevSpecifier*)rev
{
	NSDate *start = [NSDate date];
	NSDate *lastUpdate = [NSDate date];
	NSMutableArray *revisions = [NSMutableArray array];
	PBGitGrapher *g = [[PBGitGrapher alloc] initWithRepository:repository];
	std::map<string, NSStringEncoding> encodingMap;
	NSThread *currentThread = [NSThread currentThread];

	NSString *formatString = @"--pretty=format:%H\01%e\01%aN\01%cN\01%s\01%P\01%at";
	BOOL showSign = [rev hasLeftRight];

	if (showSign)
		formatString = [formatString stringByAppendingString:@"\01%m"];
	
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"log", @"-z", @"--topo-order", @"--children", formatString, nil];

	if (!rev)
		[arguments addObject:@"HEAD"];
	else
		[arguments addObjectsFromArray:[rev parameters]];

	NSString *directory = rev.workingDirectory ? rev.workingDirectory.path : repository.fileURL.path;
	NSTask *task = [PBEasyPipe taskForCommand:[PBGitBinary path] withArgs:arguments inDir:directory];
	[task launch];
	NSFileHandle *handle = [task.standardOutput fileHandleForReading];
	
	int fd = [handle fileDescriptor];
    FILE *f = fdopen(fd, "r");

	int num = 0;
	while (true) {
		if ([currentThread isCancelled])
			break;

        NSString *sha = getLine(f);
		if (sha == nil || [sha length] == 0)
			break;

        // From now on, 1.2 seconds
        NSString *encoding_str = getLine(f);
		NSStringEncoding encoding = NSUTF8StringEncoding;
		if (encoding_str != nil && [encoding_str length] > 0)
		{
            auto encodingIter = encodingMap.find([encoding_str UTF8String]);
            if (encodingIter != encodingMap.end()) {
                encoding = encodingIter->second;
			} else {
                encoding = [encoding_str fastestEncoding];
				encodingMap[[encoding_str UTF8String]] = encoding;
			}
		}

		git_oid oid;
		git_oid_fromstr(&oid, [sha UTF8String]);
		PBGitCommit *newCommit = [PBGitCommit commitWithRepository:repository andSha:[PBGitSHA shaWithOID:oid]];

        NSString *author = getLine(f);
        NSString *committer = getLine(f);
        NSString *subject = getLine(f);
        NSString *parentString = getLine(f);

		if (parentString != nil && [parentString length] > 0)
		{
			if ((([parentString length] + 1) % 41) != 0) {
				NSLog(@"invalid parents: %zu", [parentString length]);
				continue;
			}
			int nParents = ([parentString length] + 1) / 41;
			NSMutableArray *parents = [NSMutableArray arrayWithCapacity:nParents];
			int parentIndex;
			for (parentIndex = 0; parentIndex < nParents; ++parentIndex)
                [parents addObject:[PBGitSHA shaWithString:[parentString substringWithRange:NSMakeRange(parentIndex * 41, 40)]]];

			[newCommit setParents:parents];
		}

		int time;
        fscanf(f, "%d", &time);

		[newCommit setSubject:subject];
		[newCommit setAuthor:author];
		[newCommit setCommitter:committer];
		[newCommit setTimestamp:time];
		
		if (showSign)
		{
            char c = fgetc(f); // Remove separator

            c = fgetc(f);
			if (c != '>' && c != '<' && c != '^' && c != '-')
				NSLog(@"Error loading commits: sign not correct");
			[newCommit setSign: c];
		}

        char c = fgetc(f);
		if (c != '\0')
			cout << "Error" << endl;

		[revisions addObject: newCommit];
		if (isGraphing)
			[g decorateCommit:newCommit];

		if (++num % 100 == 0) {
			if ([[NSDate date] timeIntervalSinceDate:lastUpdate] > 0.1) {
				NSDictionary *update = [NSDictionary dictionaryWithObjectsAndKeys:currentThread, kRevListThreadKey, revisions, kRevListRevisionsKey, nil];
				[self performSelectorOnMainThread:@selector(updateCommits:) withObject:update waitUntilDone:NO];
				revisions = [NSMutableArray array];
				lastUpdate = [NSDate date];
			}
		}
	}
	
	if (![currentThread isCancelled]) {
		NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
		NSLog(@"Loaded %i commits in %f seconds (%f/sec)", num, duration, num/duration);

		// Make sure the commits are stored before exiting.
		NSDictionary *update = [NSDictionary dictionaryWithObjectsAndKeys:currentThread, kRevListThreadKey, revisions, kRevListRevisionsKey, nil];
		[self performSelectorOnMainThread:@selector(updateCommits:) withObject:update waitUntilDone:YES];

		[self performSelectorOnMainThread:@selector(finishedParsing) withObject:nil waitUntilDone:NO];
	}
	else {
		NSLog(@"[%@ %@] thread has been canceled", [self class], NSStringFromSelector(_cmd));
	}

	[task terminate];
	[task waitUntilExit];
}

@end
