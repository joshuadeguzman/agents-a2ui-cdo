import 'package:flutter_test/flutter_test.dart';
import 'package:siargao_genui/a2ui/a2ui_surface_view.dart';
import 'package:siargao_genui/config.dart';
import 'package:siargao_genui/deep_link.dart';
import 'package:siargao_genui/features/chat/chat_screen.dart';
import 'package:siargao_genui/features/chat/demo_prompts.dart';
import 'package:siargao_genui/services/demo_backend.dart';
import 'package:siargao_genui/services/fixture_service.dart';
import 'package:siargao_genui/services/models.dart';
import 'package:siargao_genui/services/offline_stays.dart';

import '../support/test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final FixtureService fixtures = FixtureService(bundle: DiskAssetBundle());
  final OfflineBackend backend = OfflineBackend(fixtures);

  test('demo prompt chips match the fixture prompts', () async {
    expect(demoPrompts.map((p) => p.intent), [
      'first_time_trip',
      'returning_flexible',
      'flights_under_8000',
      'surf_this_week',
    ]);
    for (final DemoPrompt p in demoPrompts) {
      final Fixture f = await fixtures.load(p.intent);
      expect(p.prompt, f.prompt, reason: p.intent);
      expect(f.path, DeliveryPath.a2a);
    }
  });

  test('chat returns the fixture surface or its markdown', () async {
    final SurfaceResponse a2ui = await backend.chat(
      prompt: 'x',
      intent: 'surf_this_week',
      format: ResponseFormat.a2ui,
    );
    expect(a2ui.messages, hasLength(3));
    expect(a2ui.meta?.label, '0 model calls · template');
    final SurfaceResponse text = await backend.chat(
      prompt: 'x',
      intent: 'surf_this_week',
      format: ResponseFormat.text,
    );
    expect(text.messages, isEmpty);
    expect(text.text, startsWith('##'));
  });

  test('typed prompts are routed by keywords or rejected kindly', () async {
    expect(
      routeOfflineIntent('Cheap flights from Cebu?'),
      'flights_under_8000',
    );
    expect(routeOfflineIntent('Is the surf good?'), 'surf_this_week');
    expect(
      routeOfflineIntent("I've been there, dates flexible"),
      'returning_flexible',
    );
    expect(routeOfflineIntent('Plan a trip'), 'first_time_trip');
    expect(routeOfflineIntent('What is the capital of France'), isNull);
    final SurfaceResponse r = await backend.chat(
      prompt: 'any flights?',
      format: ResponseFormat.a2ui,
    );
    expect(r.note, contains('matched'));
    await expectLater(
      backend.chat(prompt: 'hello', format: ResponseFormat.a2ui),
      throwsA(isA<OfflineNoMatch>()),
    );
  });

  test('home and default search are the fixtures as recorded', () async {
    final SurfaceResponse home = await backend.home();
    expect(home.path, DeliveryPath.mcpResource);
    final Fixture homeFixture = await fixtures.load('home_first_run');
    expect(home.messages, homeFixture.messages);

    final SurfaceResponse search = await backend.searchStays(
      StayQuery.fixtureDefault,
    );
    expect(search.path, DeliveryPath.mcpTool);
    expect(search.note, isNull);
    final Fixture stays = await fixtures.load('stays_near_cloud9');
    expect(search.messages, stays.messages);
  });

  test('the search_stays rule reproduces the fixture data', () async {
    final List<Stay> all = await fixtures.stays();
    final List<Stay> hits = filterStays(all, StayQuery.fixtureDefault);
    final Fixture f = await fixtures.load('stays_near_cloud9');
    final Map<Object?, Object?> value =
        (f.messages[2]['updateDataModel']! as Map)['value']! as Map;
    expect(hits.map((s) => s.toJson()).toList(), value['stays']);
  });

  test('other queries rebuild the template with fewer cards', () async {
    const StayQuery q = StayQuery(
      area: 'general luna',
      nights: 2,
      maxPrice: 1000,
    );
    final SurfaceResponse r = await backend.searchStays(q);
    expect(r.note, contains('filtered'));
    final List<Object?> components =
        (r.messages[1]['updateComponents']! as Map)['components']! as List;
    final List<Object?> ids = components.map((c) => (c! as Map)['id']).toList();
    expect(ids, contains('stay-1'));
    expect(ids, isNot(contains('stay-2')));
    final Map<Object?, Object?> grid =
        components.firstWhere((c) => (c! as Map)['id'] == 'stays-grid')! as Map;
    expect(grid['children'], ['stay-1']);
    final Map<Object?, Object?> card =
        components.firstWhere((c) => (c! as Map)['id'] == 'stay-1')! as Map;
    expect(((card['action']! as Map)['event']! as Map)['context'], {
      'stayId': 'general-luna-surf-hostel',
      'nights': 2,
    });
    final Map<Object?, Object?> value =
        (r.messages[2]['updateDataModel']! as Map)['value']! as Map;
    expect((value['hero']! as Map)['title'], '1 stay near general luna');
    expect(value['query'], {
      'area': 'general luna',
      'nights': 2,
      'max_price': 1000,
    });
  });

  test('no results drop the grid but keep the surface valid', () async {
    final SurfaceResponse r = await backend.searchStays(
      const StayQuery(area: 'Burgos', nights: 1, maxPrice: 500),
    );
    final List<Object?> components =
        (r.messages[1]['updateComponents']! as Map)['components']! as List;
    final List<Object?> ids = components.map((c) => (c! as Map)['id']).toList();
    expect(ids, isNot(contains('stays-grid')));
    expect(ids.where((i) => '$i'.startsWith('stay-')), isEmpty);
    final Map<Object?, Object?> root =
        components.firstWhere((c) => (c! as Map)['id'] == 'root')! as Map;
    expect(root['children'], isNot(contains('stays-grid')));
  });

  test('offline actions describe themselves', () async {
    final SurfaceResponse r = await backend.sendAction(
      const SurfaceAction(
        name: 'choose_stay',
        sourceComponentId: 'stay-1',
        surfaceId: 'stays_near_cloud9',
        context: {'stayId': 'boardwalk-homestay', 'nights': 3},
        timestamp: 't',
      ),
    );
    expect(
      r.text,
      'Offline demo: "choose_stay" from stay-1 '
      '(stayId: boardwalk-homestay, nights: 3). '
      'In live mode this goes to the agent.',
    );
  });

  test('config and deep links parse', () {
    expect(DemoMode.parse('live'), DemoMode.live);
    expect(DemoMode.parse('LIVE '), DemoMode.live);
    expect(DemoMode.parse(''), DemoMode.offline);
    expect(const AppConfig().agentUrl, 'http://localhost:10002');
    expect(const AppConfig().mcpUrl, 'http://localhost:10003/mcp');
    expect(AppConfig.fromEnvironment().mode, DemoMode.offline);

    final DeepLink a = DeepLink.fromUri(
      Uri.parse('http://x/?tab=chat&intent=surf_this_week&view=both'),
    );
    expect(a.tab, AppTab.chat);
    expect(a.intent, 'surf_this_week');
    expect(a.view, ChatView.both);
    expect(
      DeepLink.fromUri(Uri.parse('http://x/?tab=gallery')).tab,
      AppTab.gallery,
    );
    expect(
      DeepLink.fromUri(Uri.parse('http://x/?intent=first_time_trip')).tab,
      AppTab.chat,
    );
    final DeepLink none = DeepLink.fromUri(Uri.parse('http://x/?tab=nope'));
    expect(none.tab, isNull);
    expect(none.view, isNull);
  });
}
