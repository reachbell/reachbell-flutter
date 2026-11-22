import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reachbell/reachbell.dart';
import 'package:reachbell/src/helpers/api_client.dart';
import 'package:reachbell/src/types/config.dart';
import 'package:reachbell/src/utils/device_info.dart';

class FakeTokenSource implements TokenSource {
  FakeTokenSource({this.granted = true, this.token = 'fcm-token-1'});

  final bool granted;
  String? token;
  PushPlatform? requestedFor;
  int permissionRequests = 0;

  /// When set, requestPermission() waits for it.
  Completer<void>? gate;

  /// The next this-many requestPermission() / getToken() calls never complete.
  int hangingPermissionCalls = 0;
  int hangingTokenCalls = 0;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    if (hangingPermissionCalls > 0) {
      hangingPermissionCalls--;
      await Completer<void>().future;
    }
    await gate?.future;
    return granted;
  }

  @override
  Future<String?> getToken(PushPlatform platform) async {
    requestedFor = platform;
    if (hangingTokenCalls > 0) {
      hangingTokenCalls--;
      await Completer<void>().future;
    }
    return token;
  }
}

/// Fails like a real http.Client once closed.
class ClosableClient extends http.BaseClient {
  ClosableClient(this._inner);

  final http.Client _inner;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw http.ClientException('Client is already closed');
    final response = await _inner.send(request);
    if (closed) throw http.ClientException('Client is already closed');
    return response;
  }

  @override
  void close() => closed = true;
}

class Recorded {
  Recorded(this.request, this.body);

  final http.Request request;
  final Map<String, dynamic> body;
}

MockClient mockClient(
  List<Recorded> calls,
  http.Response Function(http.Request request) handler,
) {
  return MockClient((request) async {
    calls.add(
        Recorded(request, jsonDecode(request.body) as Map<String, dynamic>));
    return handler(request);
  });
}

http.Response json(Object body, [int status = 200]) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void setUpSdk({
  required http.Client client,
  TokenSource? tokenSource,
  PushPlatform platform = PushPlatform.android,
  String? apiUrl,
  DeviceInfo? deviceInfo,
}) {
  ReachBell.debugOverride(
    httpClient: client,
    tokenSource: tokenSource ?? FakeTokenSource(),
    platform: platform,
    deviceInfo: deviceInfo ?? testDevice,
  );
  ReachBell.init(apiKey: 'rb_live_test', apiUrl: apiUrl);
}

const testDevice =
    DeviceInfo(os: 'Android', osVersion: '14', device: 'mobile');

Matcher throwsReachBell({int? statusCode, String? message}) {
  var matcher = isA<ReachBellException>();
  if (statusCode != null) {
    matcher = matcher.having((e) => e.statusCode, 'statusCode', statusCode);
  }
  if (message != null) {
    matcher = matcher.having((e) => e.message, 'message', contains(message));
  }
  return throwsA(matcher);
}

void main() {
  late List<Recorded> calls;

  setUp(() {
    calls = [];
    ReachBell.debugReset();
  });

  tearDown(ReachBell.debugReset);

  group('init', () {
    test('rejects empty apiKey', () {
      expect(() => ReachBell.init(apiKey: '  '), throwsReachBell());
    });

    test('methods throw before init', () async {
      expect(ReachBell.register(), throwsReachBell(message: 'init()'));
      expect(ReachBell.identify('u'), throwsReachBell(message: 'init()'));
      expect(ReachBell.tag(['a']), throwsReachBell(message: 'init()'));
    });
  });

  group('register', () {
    test('posts token with fcm tokenType on android', () async {
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 'sub_1'}, 201)),
      );

      final result = await ReachBell.register(externalId: 'user_42');

      expect(result.token, 'fcm-token-1');
      expect(result.tokenType, TokenType.fcm);
      expect(result.platform, PushPlatform.android);
      expect(result.subscriberId, 'sub_1');
      expect(ReachBell.token, 'fcm-token-1');

      expect(calls, hasLength(1));
      final call = calls.single;
      expect(call.request.method, 'POST');
      expect(
          call.request.url.toString(), 'https://api.reachbell.com/subscribers');
      expect(call.request.headers['x-api-key'], 'rb_live_test');
      expect(call.body, {
        'token': 'fcm-token-1',
        'tokenType': 'fcm',
        'platform': 'android',
        'os': 'Android',
        'osVersion': '14',
        'device': 'mobile',
        'externalId': 'user_42',
      });
    });

    test('detects os from the push platform and omits a missing osVersion',
        () async {
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 's'})),
        platform: PushPlatform.ios,
        deviceInfo: const DeviceInfo(os: 'iOS', device: 'tablet'),
      );

      await ReachBell.register();

      expect(calls.single.body['os'], 'iOS');
      expect(calls.single.body.containsKey('osVersion'), isFalse);
      expect(calls.single.body['device'], 'tablet');
      expect(DeviceInfo.detect(PushPlatform.ios).os, 'iOS');
      expect(DeviceInfo.detect(PushPlatform.android).os, 'Android');
    });

    test('classifies tablets by the physical display, not the window', () {
      // A 2560x1600 @2x tablet in split screen: the window is 1280x1600 px.
      expect(
          DeviceInfo.deviceTypeFor(
            displaySize: const Size(2560, 1600),
            displayPixelRatio: 2,
            windowSize: const Size(1000, 1600),
            windowPixelRatio: 2,
          ),
          'tablet');
      expect(
          DeviceInfo.deviceTypeFor(
            displaySize: const Size(1080, 2400),
            displayPixelRatio: 2.75,
            windowSize: const Size(1080, 2400),
            windowPixelRatio: 2.75,
          ),
          'mobile');
      // No display size reported: fall back to the window.
      expect(
          DeviceInfo.deviceTypeFor(
            displaySize: Size.zero,
            windowSize: const Size(2048, 2732),
            windowPixelRatio: 2,
          ),
          'tablet');
      expect(DeviceInfo.deviceTypeFor(), 'mobile');
    });

    test('parses operatingSystemVersion', () {
      expect(
          DeviceInfo.parseOsVersion(
              PushPlatform.ios, 'Version 17.4 (Build 21E213)'),
          '17.4');
      // Android's operatingSystemVersion is not the release: always omitted.
      expect(DeviceInfo.parseOsVersion(PushPlatform.android, '14'), isNull);
      expect(
          DeviceInfo.parseOsVersion(
              PushPlatform.android, 'Linux 5.10.157-android13 #1 SMP'),
          isNull);
      expect(DeviceInfo.parseOsVersion(PushPlatform.ios, null), isNull);
    });

    test('uses fcm tokenType and ios platform on iOS', () async {
      final source = FakeTokenSource();
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 'sub_2'})),
        tokenSource: source,
        platform: PushPlatform.ios,
        apiUrl: 'https://staging.example.com/',
      );

      final result = await ReachBell.register();

      expect(result.tokenType, TokenType.fcm);
      expect(result.platform, PushPlatform.ios);
      expect(source.requestedFor, PushPlatform.ios);
      expect(calls.single.request.url.toString(),
          'https://staging.example.com/subscribers');
      expect(calls.single.body['tokenType'], 'fcm');
      expect(calls.single.body['platform'], 'ios');
      expect(calls.single.body.containsKey('externalId'), isFalse);
    });

    test('throws when permission is denied', () async {
      setUpSdk(
        client: mockClient(calls, (_) => json({})),
        tokenSource: FakeTokenSource(granted: false),
      );

      await expectLater(
          ReachBell.register(), throwsReachBell(message: 'permission denied'));
      expect(calls, isEmpty);
      expect(ReachBell.token, isNull);
    });

    test('throws when no token is available', () async {
      setUpSdk(
        client: mockClient(calls, (_) => json({})),
        tokenSource: FakeTokenSource(token: null),
      );

      await expectLater(
          ReachBell.register(), throwsReachBell(message: 'No push token'));
      expect(calls, isEmpty);
    });

    test('maps non-2xx responses with statusCode and body', () async {
      setUpSdk(
        client: mockClient(
            calls, (_) => json({'message': 'Subscriber limit reached'}, 403)),
      );

      await expectLater(
        ReachBell.register(),
        throwsA(isA<ReachBellException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'Subscriber limit reached')
            .having((e) => e.body, 'body',
                {'message': 'Subscriber limit reached'})),
      );
      expect(ReachBell.token, isNull);
    });

    test('keeps non-json error bodies as text', () async {
      setUpSdk(
        client: mockClient(calls, (_) => http.Response('Bad Gateway', 502)),
      );

      await expectLater(
        ReachBell.register(),
        throwsA(isA<ReachBellException>()
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.body, 'body', 'Bad Gateway')),
      );
    });

    test('maps network errors with null statusCode', () async {
      ReachBell.debugOverride(
        httpClient: MockClient(
            (_) async => throw http.ClientException('connection refused')),
        tokenSource: FakeTokenSource(),
        platform: PushPlatform.android,
      );
      ReachBell.init(apiKey: 'rb_live_test');

      await expectLater(
        ReachBell.register(),
        throwsA(isA<ReachBellException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('Network error'))),
      );
    });

    test('maps timeouts with null statusCode', () async {
      ReachBell.debugOverride(
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return json({});
        }),
        tokenSource: FakeTokenSource(),
        platform: PushPlatform.android,
      );
      ReachBell.init(
          apiKey: 'rb_live_test', timeout: const Duration(milliseconds: 20));

      await expectLater(
        ReachBell.register(),
        throwsA(isA<ReachBellException>()
            .having((e) => e.statusCode, 'statusCode', isNull)
            .having((e) => e.message, 'message', contains('timed out'))),
      );
    });
  });

  group('identify, tag, untag', () {
    test('throw before register', () async {
      setUpSdk(client: mockClient(calls, (_) => json({'success': true})));

      await expectLater(ReachBell.identify('user_42'),
          throwsReachBell(message: 'register()'));
      await expectLater(
          ReachBell.tag(['pro']), throwsReachBell(message: 'register()'));
      await expectLater(
          ReachBell.untag(['pro']), throwsReachBell(message: 'register()'));
      expect(calls, isEmpty);
    });

    test('send token after register', () async {
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          return json({'success': true, 'updated': true});
        }),
      );

      await ReachBell.register();
      await ReachBell.identify('user_42');
      await ReachBell.tag(['pro', ' beta ', 'pro']);
      await ReachBell.untag(['beta']);

      expect(calls.map((c) => c.request.url.path).toList(), [
        '/subscribers',
        '/subscribers/identify',
        '/subscribers/tag',
        '/subscribers/untag',
      ]);
      expect(calls[1].body, {'token': 'fcm-token-1', 'externalId': 'user_42'});
      expect(calls[2].body, {
        'token': 'fcm-token-1',
        'tags': ['pro', 'beta'],
      });
      expect(calls[3].body, {
        'token': 'fcm-token-1',
        'tags': ['beta'],
      });
    });

    test('map success:false to ReachBellException', () async {
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          return json({
            'success': false,
            'updated': false,
            'reason': 'subscriber_not_found',
          });
        }),
      );

      await ReachBell.register();

      for (final action in [
        () => ReachBell.identify('user_42'),
        () => ReachBell.tag(['pro']),
        () => ReachBell.untag(['pro']),
      ]) {
        await expectLater(
          action(),
          throwsA(isA<ReachBellException>()
              .having((e) => e.message, 'message', 'subscriber_not_found')
              .having((e) => e.statusCode, 'statusCode', 200)
              .having((e) => e.body, 'body', isA<Map<String, dynamic>>())),
        );
      }
    });

    test('reject empty arguments without calling the API', () async {
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          return json({'success': true});
        }),
      );
      await ReachBell.register();
      calls.clear();

      await expectLater(ReachBell.identify(' '), throwsReachBell());
      await expectLater(ReachBell.tag(['', ' ']), throwsReachBell());
      expect(calls, isEmpty);
    });
  });

  group('token rotation', () {
    test('sends the last registered token as previousToken', () async {
      final source = FakeTokenSource();
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 's'})),
        tokenSource: source,
      );

      await ReachBell.register(externalId: 'user_42');
      source.token = 'fcm-token-2';
      await ReachBell.register();

      expect(calls, hasLength(2));
      expect(calls[0].body.containsKey('previousToken'), isFalse);
      expect(calls[1].body, {
        'token': 'fcm-token-2',
        'tokenType': 'fcm',
        'platform': 'android',
        'os': 'Android',
        'osVersion': '14',
        'device': 'mobile',
        'previousToken': 'fcm-token-1',
      });
      expect(ReachBell.token, 'fcm-token-2');
    });

    test('omits previousToken when the token did not change', () async {
      setUpSdk(client: mockClient(calls, (_) => json({'_id': 's'})));

      await ReachBell.register();
      await ReachBell.register();

      expect(calls[1].body.containsKey('previousToken'), isFalse);
    });

    test('accepts an explicit previousToken', () async {
      setUpSdk(client: mockClient(calls, (_) => json({'_id': 's'})));

      await ReachBell.register(previousToken: 'persisted-token');

      expect(calls.single.body['previousToken'], 'persisted-token');
    });
  });

  group('serialised register', () {
    test('concurrent calls run one at a time', () async {
      final source = FakeTokenSource()..gate = Completer<void>();
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 's'})),
        tokenSource: source,
      );

      final first = ReachBell.register();
      final second = ReachBell.register();
      await pumpEventQueue();

      expect(source.permissionRequests, 1);
      expect(calls, isEmpty);

      source.gate!.complete();
      await Future.wait([first, second]);

      expect(source.permissionRequests, 2);
      expect(calls, hasLength(2));
    });

    test('a failed register does not block the next one', () async {
      final source = FakeTokenSource(token: null);
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 's'})),
        tokenSource: source,
      );

      await expectLater(ReachBell.register(), throwsReachBell());
      source.token = 'fcm-token-1';
      await ReachBell.register();

      expect(calls, hasLength(1));
    });
  });

  group('token timeout', () {
    test('a permission request that never completes times out', () async {
      final source = FakeTokenSource()..hangingPermissionCalls = 1;
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 's'})),
        tokenSource: source,
      );
      ReachBell.init(
          apiKey: 'rb_live_test',
          tokenTimeout: const Duration(milliseconds: 20));

      final first = ReachBell.register(externalId: 'u1');
      final second = ReachBell.register(externalId: 'u2');
      await expectLater(first, throwsReachBell(message: 'timed out'));
      await second;

      expect(calls, hasLength(1));
      expect(calls.single.body['externalId'], 'u2');
    });

    test('a token read that never completes times out', () async {
      final source = FakeTokenSource()..hangingTokenCalls = 1;
      setUpSdk(
        client: mockClient(calls, (_) => json({'_id': 's'})),
        tokenSource: source,
      );
      ReachBell.init(
          apiKey: 'rb_live_test',
          tokenTimeout: const Duration(milliseconds: 20));

      await expectLater(
          ReachBell.register(), throwsReachBell(message: 'No push token'));
      await ReachBell.register();
      expect(calls, hasLength(1));
    });

    test('rejects a non-positive tokenTimeout', () {
      expect(
          () => ReachBell.init(apiKey: 'k', tokenTimeout: Duration.zero),
          throwsReachBell(message: 'tokenTimeout'));
    });
  });

  group('reset', () {
    test('unidentifies the stored token, then forgets it', () async {
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          return json({'success': true});
        }),
      );
      await ReachBell.register(externalId: 'user_42');

      await ReachBell.reset();

      expect(calls[1].request.url.path, '/subscribers/unidentify');
      expect(calls[1].body, {'token': 'fcm-token-1'});
      expect(ReachBell.token, isNull);
      await expectLater(ReachBell.identify('user_42'),
          throwsReachBell(message: 'register()'));
    });

    test('clears local state even when unidentify fails', () async {
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          return json({'message': 'boom'}, 500);
        }),
      );
      await ReachBell.register();

      await ReachBell.reset();

      expect(calls, hasLength(2));
      expect(ReachBell.token, isNull);
    });

    test('sends nothing without a registration', () async {
      setUpSdk(client: mockClient(calls, (_) => json({'success': true})));

      await ReachBell.reset();

      expect(calls, isEmpty);
    });

    test('waits for a register in progress', () async {
      final source = FakeTokenSource()..gate = Completer<void>();
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          return json({'success': true});
        }),
        tokenSource: source,
      );

      final registering = ReachBell.register(externalId: 'user_42');
      final resetting = ReachBell.reset();
      source.gate!.complete();
      await registering;
      await resetting;

      expect(calls.map((c) => c.request.url.path).toList(),
          ['/subscribers', '/subscribers/unidentify']);
      expect(ReachBell.token, isNull);
    });

    test('next register after reset sends no previousToken', () async {
      final source = FakeTokenSource();
      setUpSdk(
        client: mockClient(calls, (_) => json({'success': true})),
        tokenSource: source,
      );
      await ReachBell.register();
      await ReachBell.reset();
      // A rotated token: had reset() kept fcm-token-1, it would be sent as
      // previousToken.
      source.token = 'fcm-token-2';

      await ReachBell.register(externalId: 'user_9');

      expect(calls.last.body['token'], 'fcm-token-2');
      expect(calls.last.body.containsKey('previousToken'), isFalse);
      expect(calls.last.body['externalId'], 'user_9');
    });

    test('first register after reset sends externalId: null, once', () async {
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          // unidentify fails (offline): the null externalId repairs it.
          return json({'message': 'boom'}, 500);
        }),
      );
      await ReachBell.register(externalId: 'user_42');
      await ReachBell.reset();

      await ReachBell.register();

      expect(calls[2].request.url.path, '/subscribers');
      expect(calls[2].body.containsKey('externalId'), isTrue);
      expect(calls[2].body['externalId'], isNull);
      expect(calls[2].request.body, contains('"externalId":null'));

      await ReachBell.register();
      expect(calls[3].body.containsKey('externalId'), isFalse);
    });

    test('a failed register after reset keeps the null pending', () async {
      var failNext = false;
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path != '/subscribers') {
            return json({'success': true});
          }
          if (failNext) {
            failNext = false;
            return json({'message': 'boom'}, 500);
          }
          return json({'_id': 's'});
        }),
      );
      await ReachBell.register(externalId: 'user_42');
      await ReachBell.reset();
      failNext = true;

      await expectLater(ReachBell.register(), throwsReachBell(statusCode: 500));
      await ReachBell.register();

      expect(calls[2].body['externalId'], isNull);
      expect(calls[3].body.containsKey('externalId'), isTrue);
      expect(calls[3].body['externalId'], isNull);
    });

    test('an explicit externalId after reset is sent instead of null',
        () async {
      setUpSdk(client: mockClient(calls, (_) => json({'success': true})));
      await ReachBell.register(externalId: 'user_42');
      await ReachBell.reset();

      await ReachBell.register(externalId: 'user_9');

      expect(calls.last.body['externalId'], 'user_9');
    });

    test('identify, tag and untag queue behind reset and register', () async {
      setUpSdk(
        client: mockClient(calls, (request) {
          if (request.url.path == '/subscribers') return json({'_id': 's'});
          return json({'success': true, 'updated': true});
        }),
      );
      await ReachBell.register(externalId: 'user_1');

      // Not awaited: each call must still run in call order.
      final resetting = ReachBell.reset();
      // Runs after reset(), so the token is gone. Listened to straight away
      // so the error is not reported as unhandled.
      final identifyBeforeRegister = expectLater(
          ReachBell.identify('user_2'), throwsReachBell(message: 'register()'));
      final registering = ReachBell.register();
      final identifying = ReachBell.identify('user_2');
      final tagging = ReachBell.tag(['pro']);

      await resetting;
      await identifyBeforeRegister;
      await registering;
      await identifying;
      await tagging;

      expect(calls.map((c) => c.request.url.path).toList(), [
        '/subscribers',
        '/subscribers/unidentify',
        '/subscribers',
        '/subscribers/identify',
        '/subscribers/tag',
      ]);
      expect(calls[2].body['externalId'], isNull);
      expect(calls[3].body, {'token': 'fcm-token-1', 'externalId': 'user_2'});
    });
  });

  group('ApiClient', () {
    const config = ReachBellConfig(
      apiKey: 'rb_live_test',
      apiUrl: 'https://api.example.test',
      timeout: Duration(seconds: 5),
    );

    test('closeWhenIdle waits for in-flight requests', () async {
      final release = Completer<void>();
      final client = ClosableClient(MockClient((_) async {
        await release.future;
        return json({'ok': true});
      }));
      final api = ApiClient(config, client, ownsClient: true);

      final pending = api.post('/subscribers', {});
      await pumpEventQueue();
      api.closeWhenIdle();
      expect(client.closed, isFalse);

      release.complete();
      final response = await pending;

      expect(response.statusCode, 200);
      expect(client.closed, isTrue);
    });

    test('does not close a client it does not own', () async {
      final client = ClosableClient(MockClient((_) async => json({})));
      ApiClient(config, client).closeWhenIdle();

      expect(client.closed, isFalse);
    });

    test('wraps non-Exception errors as ReachBellException', () async {
      final api = ApiClient(
          config, MockClient((_) async => throw ArgumentError('bad header')));

      await expectLater(
        api.post('/subscribers', {}),
        throwsA(isA<ReachBellException>()
            .having((e) => e.message, 'message', contains('bad header'))),
      );
    });

    test('joins NestJS array messages', () async {
      final api = ApiClient(
        config,
        MockClient((_) async => json({
              'statusCode': 400,
              'message': ['token must be a string', 'tags must be an array'],
              'error': 'Bad Request',
            }, 400)),
      );

      await expectLater(
        api.post('/subscribers', {}),
        throwsA(isA<ReachBellException>().having((e) => e.message, 'message',
            'token must be a string; tags must be an array')),
      );
    });
  });
}
