import 'package:cached_query/cached_query.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  group("delete timer", () {
    test(
      "a query is not deleted while listened to after a refetch while inactive",
      () {
        fakeAsync((async) {
          final cache = CachedQuery.asNewInstance()
            ..config(
              config: GlobalQueryConfig(
                cacheDuration: const Duration(minutes: 5),
              ),
            );
          var fetches = 0;
          final query = Query<int>(
            key: "leak",
            queryFn: () async => ++fetches,
            cache: cache,
          );

          // Listen, then stop listening: a delete timer is armed.
          var sub = query.stream.listen((_) {});
          async.flushMicrotasks();
          sub.cancel();
          async.flushMicrotasks();

          // Refetch while nothing listens. Before the fix this replaced the
          // pending timer without cancelling it.
          query.refetch();
          async.flushMicrotasks();

          // Listen again and stay subscribed past the cache duration.
          sub = query.stream.listen((_) {});
          async
            ..flushMicrotasks()
            ..elapse(const Duration(minutes: 6));

          expect(cache.getQuery("leak"), same(query));

          sub.cancel();
          async.elapse(const Duration(minutes: 6));
        });
      },
    );

    test("a query nobody listens to is still deleted after cacheDuration", () {
      fakeAsync((async) {
        final cache = CachedQuery.asNewInstance()
          ..config(
            config: GlobalQueryConfig(
              cacheDuration: const Duration(minutes: 5),
            ),
          );
        final query = Query<int>(
          key: "idle",
          queryFn: () async => 1,
          cache: cache,
        );

        final sub = query.stream.listen((_) {});
        async.flushMicrotasks();
        sub.cancel();
        async
          ..flushMicrotasks()
          ..elapse(const Duration(minutes: 6));

        expect(cache.getQuery("idle"), isNull);
      });
    });
      test(
      "a dropped query's delete timer doesn't remove its replacement",
      () {
        fakeAsync((async) {
          final cache = CachedQuery.asNewInstance()
            ..config(
              config: GlobalQueryConfig(
                cacheDuration: const Duration(minutes: 5),
              ),
            );
          Query<int> create() => Query<int>(
                key: "replaced",
                queryFn: () async => 1,
                cache: cache,
              );

          final old = create();
          final oldSub = old.stream.listen((_) {});
          async.flushMicrotasks();

          // The cache drops the key while a screen still listens to the old
          // query, and a later lookup creates a replacement.
          cache.deleteCache(key: "replaced");
          final replacement = create();
          expect(replacement, isNot(same(old)));
          final newSub = replacement.stream.listen((_) {});
          async.flushMicrotasks();

          // The screen re-binds: the old query loses its last listener and
          // arms its delete timer.
          oldSub.cancel();
          async
            ..flushMicrotasks()
            ..elapse(const Duration(minutes: 6));

          // Before the fix the old timer deleted the key, taking the
          // replacement the screen now shows with it.
          expect(cache.getQuery("replaced"), same(replacement));

          newSub.cancel();
          async.elapse(const Duration(minutes: 6));
          expect(cache.getQuery("replaced"), isNull);
        });
      },
    );
  });
}
