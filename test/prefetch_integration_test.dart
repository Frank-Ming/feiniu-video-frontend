import 'dart:async';
import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import 'package:feiniu_video/services/prefetch_manager.dart';

class _MockPathProvider extends PathProviderPlatform {
  _MockPathProvider(this.tempDir);
  final String tempDir;

  @override
  Future<String?> getTemporaryPath() async => tempDir;

  @override
  Future<String?> getApplicationDocumentsPath() async => tempDir;
}

void main() {
  late io.Directory tmpRoot;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tmpRoot = io.Directory.systemTemp.createTempSync('feiniu_prefetch_test_');
    PathProviderPlatform.instance = _MockPathProvider(tmpRoot.path);
    PrefetchManager.instance.setClientFactory(null);
    PrefetchManager.instance.cancelAll();
    await PrefetchManager.instance.clear();
  });

  tearDown(() async {
    PrefetchManager.instance.cancelAll();
    PrefetchManager.instance.setClientFactory(null);
    if (await tmpRoot.exists()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  test('prefetchRange：mock server 接受 Range 头并写入 .cache', () async {
    final fakeBody = List<int>.generate(100, (i) => i);
    final mock = MockClient((req) async {
      expect(req.headers['Range'], 'bytes=0-9');
      return http.Response.bytes(fakeBody.sublist(0, 10), 206,
          headers: {'content-range': 'bytes 0-9/100'});
    });
    PrefetchManager.instance.setClientFactory(() => mock);

    await PrefetchManager.instance.prefetchRange(
      videoId: 'video-A',
      url: 'http://test/video-A',
      token: 'tok',
      bytes: 10,
    );

    final p = await PrefetchManager.instance.localCachePath('video-A');
    expect(p, isNotNull);
    final content = await io.File(p!).readAsBytes();
    expect(content, fakeBody.sublist(0, 10));
  });

  test('prefetchFull：mock server 全量下载并写入 .full', () async {
    final fakeBody = 'hello world hello world'.codeUnits;
    final mock = MockClient((req) async {
      expect(req.headers.containsKey('Range'), false);
      return http.Response.bytes(fakeBody, 200);
    });
    PrefetchManager.instance.setClientFactory(() => mock);

    await PrefetchManager.instance.prefetchFull(
      videoId: 'video-B',
      url: 'http://test/video-B',
      token: null,
    );

    final p = await PrefetchManager.instance.localCachePath('video-B', full: true);
    expect(p, isNotNull);
    expect(await io.File(p!).readAsBytes(), fakeBody);
  });

  test('prefetchFull 已有 .cache：会删除 .cache 并真正下载 .full', () async {
    // 1) 先 prefetchRange 写 .cache
    final mock1 = MockClient((req) async {
      return http.Response.bytes(List.filled(10, 7), 206,
          headers: {'content-range': 'bytes 0-9/100'});
    });
    PrefetchManager.instance.setClientFactory(() => mock1);
    await PrefetchManager.instance.prefetchRange(
      videoId: 'video-C', url: 'http://test/video-C',
      token: null, bytes: 10,
    );
    expect(await PrefetchManager.instance.localCachePath('video-C'), isNotNull);

    // 2) 再 prefetchFull，应当真请求
    bool fullRequested = false;
    final mock2 = MockClient((req) async {
      expect(req.headers.containsKey('Range'), false);
      fullRequested = true;
      return http.Response.bytes(List.filled(50, 9), 200);
    });
    PrefetchManager.instance.setClientFactory(() => mock2);
    await PrefetchManager.instance.prefetchFull(
      videoId: 'video-C', url: 'http://test/video-C', token: null,
    );

    expect(fullRequested, true, reason: '应真请求全量，不应被 .cache 短路');
    expect(await PrefetchManager.instance.localCachePath('video-C', full: true),
        isNotNull);
    expect(await PrefetchManager.instance.localCachePath('video-C'),
        isNull, reason: '.cache 应当被清掉');
  });

  test('重复 prefetchRange 同一 id：第二次不再发起请求', () async {
    int calls = 0;
    final mock = MockClient((req) async {
      calls++;
      return http.Response.bytes(List.filled(10, 1), 206,
          headers: {'content-range': 'bytes 0-9/100'});
    });
    PrefetchManager.instance.setClientFactory(() => mock);

    await PrefetchManager.instance.prefetchRange(
      videoId: 'video-D', url: 'http://test/video-D',
      token: null, bytes: 10,
    );
    await PrefetchManager.instance.prefetchRange(
      videoId: 'video-D', url: 'http://test/video-D',
      token: null, bytes: 10,
    );
    expect(calls, 1, reason: '第二次应被早返回拦截');
  });

  test('cancel 不存在的 id：activeIds 立即为空，不抛错', () async {
    // MockClient 不会真的运行，因为我们立刻 cancel
    final mock = MockClient((req) async => http.Response.bytes([], 200));
    PrefetchManager.instance.setClientFactory(() => mock);

    // 启动下载但还没等 await
    final fut = PrefetchManager.instance.prefetchRange(
      videoId: 'video-E',
      url: 'http://test/video-E',
      token: null,
      bytes: 10,
    );
    PrefetchManager.instance.cancel('video-E');
    try {
      await fut;
    } catch (_) {}
    expect(PrefetchManager.instance.activeIds(), isEmpty);
  });
}
