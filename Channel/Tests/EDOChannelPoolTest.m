//
// Copyright 2018 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import <XCTest/XCTest.h>

#import "Channel/Sources/EDOChannelPool.h"
#import "Channel/Sources/EDOHostPort.h"
#import "Channel/Sources/EDOSocket.h"
#import "Channel/Sources/EDOSocketChannel.h"
#import "Channel/Sources/EDOSocketPort.h"

@interface EDOChannelPoolTest : XCTestCase

@end

@implementation EDOChannelPoolTest

- (void)testSimpleFetchAndReleaseAfterCreate {
  EDOSocket *host = [EDOSocket listenWithTCPPort:0 queue:nil connectedBlock:nil];
  EDOChannelPool *channelPool = EDOChannelPool.sharedChannelPool;
  __block NSMutableArray<EDOSocketChannel *> *channels =
      [[NSMutableArray alloc] initWithCapacity:10];
  for (int i = 0; i < 10; i++) {
    XCTestExpectation *fetchExpectation = [self expectationWithDescription:@"Channel fetched"];
    [channelPool
        fetchConnectedChannelWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]
                withCompletionHandler:^(EDOSocketChannel *socketChannel, NSError *error) {
                  [channels addObject:socketChannel];
                  [channelPool addChannel:socketChannel];
                  [fetchExpectation fulfill];
                }];
    [self waitForExpectationsWithTimeout:2 handler:nil];
  }
  XCTAssertEqual(
      [channelPool countChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]],
      1u);
  for (int i = 0; i < 9; i++) {
    XCTAssertEqual(channels[i], channels[i + 1]);
  }
  [channelPool removeChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]];
}

- (void)testAsyncCreateChannels {
  EDOSocket *host1 = [EDOSocket listenWithTCPPort:0 queue:nil connectedBlock:nil];
  EDOSocket *host2 = [EDOSocket listenWithTCPPort:0 queue:nil connectedBlock:nil];
  NSMutableSet<EDOSocketChannel *> *set1 = [[NSMutableSet alloc] init];
  NSMutableSet<EDOSocketChannel *> *set2 = [[NSMutableSet alloc] init];
  dispatch_queue_t queue = dispatch_queue_create("channel set sync queue", DISPATCH_QUEUE_SERIAL);
  EDOChannelPool *channelPool = EDOChannelPool.sharedChannelPool;

  XCTestExpectation *fetchExpectation = [self expectationWithDescription:@"async fetch actions"];
  fetchExpectation.expectedFulfillmentCount = 10;

  for (int i = 0; i < 10; i++) {
    UInt16 port = i % 2 == 0 ? host1.socketPort.port : host2.socketPort.port;
    NSMutableSet *set = i % 2 == 0 ? set1 : set2;
    [channelPool fetchConnectedChannelWithPort:[EDOHostPort hostPortWithLocalPort:port]
                         withCompletionHandler:^(EDOSocketChannel *socketChannel, NSError *error) {
                           [channelPool addChannel:socketChannel];
                           dispatch_sync(queue, ^{
                             [set addObject:socketChannel];
                           });
                           [fetchExpectation fulfill];
                         }];
  }

  [self waitForExpectationsWithTimeout:10 handler:nil];
  NSUInteger host1ChannelCount =
      [channelPool countChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host1.socketPort.port]];
  NSUInteger host2ChannelCount =
      [channelPool countChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host2.socketPort.port]];
  XCTAssertEqual(host1ChannelCount + host2ChannelCount, set1.count + set2.count);
  [channelPool removeChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host1.socketPort.port]];
  [channelPool removeChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host2.socketPort.port]];
}

- (void)testClearChannelWithPort {
  EDOSocket *host = [EDOSocket listenWithTCPPort:0 queue:nil connectedBlock:nil];
  EDOChannelPool *channelPool = EDOChannelPool.sharedChannelPool;
  XCTestExpectation *clearExpectation = [self expectationWithDescription:@"Channel cleared"];
  [channelPool
      fetchConnectedChannelWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]
              withCompletionHandler:^(EDOSocketChannel *socketChannel, NSError *error) {
                [channelPool addChannel:socketChannel];
                [clearExpectation fulfill];
              }];
  [self waitForExpectationsWithTimeout:2 handler:nil];
  [channelPool removeChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]];
  XCTAssertEqual(
      [channelPool countChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]],
      0u);
}

- (void)testReleaseInvalidChannel {
  EDOSocket *host = [EDOSocket listenWithTCPPort:0 queue:nil connectedBlock:nil];
  EDOChannelPool *channelPool = EDOChannelPool.sharedChannelPool;
  XCTestExpectation *fetchExpectation = [self expectationWithDescription:@"Channel fetched"];
  __block EDOSocketChannel *channel = nil;
  [channelPool
      fetchConnectedChannelWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]
              withCompletionHandler:^(EDOSocketChannel *socketChannel, NSError *error) {
                [channel invalidate];
                [fetchExpectation fulfill];
              }];
  [self waitForExpectationsWithTimeout:2 handler:nil];
  [channelPool addChannel:channel];
  XCTAssertEqual(
      [channelPool countChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]],
      0u);
  [channelPool removeChannelsWithPort:[EDOHostPort hostPortWithLocalPort:host.socketPort.port]];
}

- (void)testClearInvalidPort {
  // channel pool should be empty now
  EDOChannelPool *channelPool = EDOChannelPool.sharedChannelPool;
  // trigger two times to make sure clear a non-existing port.
  XCTAssertNoThrow([channelPool removeChannelsWithPort:[EDOHostPort hostPortWithLocalPort:12345]]);
  XCTAssertNoThrow([channelPool removeChannelsWithPort:[EDOHostPort hostPortWithLocalPort:12345]]);
}

@end
