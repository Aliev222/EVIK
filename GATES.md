# Gates: production order tracking completion

OWNS: backend/internal/config/**, backend/internal/transport/http/routing_handler*, backend/internal/transport/http/router.go, backend/internal/transport/ws/**, backend/internal/usecase/driver/**, frontend/lib/core/constants/app_constants.dart, frontend/lib/core/services/map_api.dart, frontend/lib/core/services/openstreetmap_service.dart, frontend/lib/core/services/realtime_location_service.dart, frontend/lib/features/client/presentation/providers/real_time_driver_provider.dart, frontend/lib/features/client/presentation/screens/driver_info_screen.dart, frontend/lib/features/client/presentation/screens/driver_search_screen.dart, frontend/lib/features/client/presentation/screens/tracking_screen.dart, frontend/lib/features/driver/presentation/providers/driver_realtime_provider.dart, frontend/lib/features/driver/presentation/screens/active_order_screen.dart, frontend/lib/features/map/**, frontend/lib/main.dart, frontend/test/**

Scope: verify and finish the client-visible tow-truck journey from assignment through terminal cleanup, with truthful telemetry, shared EVIK routing, resilient camera/UI behavior, and explicit external blockers. Preserve every unrelated dirty-worktree change.

- [x] G1: backend telemetry regressions cover small movement, stationary freshness, phase-at-same-point, stale/duplicate samples, foreign/closed orders, mixed publishers, and GPS outliers
  CHECK: go test ./internal/transport/ws ./internal/usecase/driver -count=1
  EXPECT: evik/backend/internal/transport/ws
  CWD: backend
  EVIDENCE: automatic-evidence=v1; definition-sha256=1756f04f0436a00451662f86a0c213d7d17b4ca3564ab440212d1a310d07d3df; exit=0; EXPECT=matched; output-sha256=0447bfd8d4655ede4716883f60012a98f4bf6ab33eb0f800b6150d9e89bc50e6; output-bytes=96; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/backend; path=330df7af71d3/20 entries

- [x] G2: backend route contract is participant-authorized, phase-targeted, versioned, and production config rejects the public OSRM demo
  CHECK: go test ./internal/transport/http ./internal/config ./internal/domain/routing -count=1
  EXPECT: evik/backend/internal/transport/http
  CWD: backend
  EVIDENCE: automatic-evidence=v1; definition-sha256=c0c17fde19ace59d2be117b1d557032d916b62f654459a2c9ecaf62d8749e9b3; exit=0; EXPECT=matched; output-sha256=d9b4481b3bf4c377578e269053e8b9ff0295e4fe1d2415c9136e867145841023; output-bytes=148; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/backend; path=330df7af71d3/20 entries

- [x] G3: backend race checks pass for live telemetry and status publication
  CHECK: go test -race ./internal/transport/ws ./internal/usecase/driver -count=1
  EXPECT: evik/backend/internal/transport/ws
  CWD: backend
  EVIDENCE: automatic-evidence=v1; definition-sha256=e67741a033d3593469b441184d329abc28839433aed38943757d5c8ba3145560; exit=0; EXPECT=matched; output-sha256=7c250d56fc75c167b0d4471f72285f0b54ab193db9bd22956fa6356e7a46a166; output-bytes=96; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/backend; path=330df7af71d3/20 entries

- [x] G4: complete Go suite passes
  CHECK: go test ./... -count=1
  EXPECT: evik/backend/internal/transport/ws
  CWD: backend
  EVIDENCE: automatic-evidence=v1; definition-sha256=3c7950bcd7594ed388731ea2d003c5936229bce78f99d81d5c619cbe186d1a9b; exit=0; EXPECT=matched; output-sha256=6ac875c4c50919eec5bc5ba52c01180a5a4f61671a01c2f293b21a345827e469; output-bytes=1595; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/backend; path=330df7af71d3/20 entries

- [x] G5: client session lifecycle, snapshot, identity filtering, reconnect state, nullable clearing, terminal cleanup, and driver background telemetry regressions pass
  CHECK: flutter test test/driver_location_tracking_test.dart test/driver_realtime_tracking_test.dart --reporter compact
  EXPECT: All tests passed
  CWD: frontend
  EVIDENCE: automatic-evidence=v1; definition-sha256=9cd8a9558a86678215fec307b42cc3b237d358cd4b57b5872d61d049fa23b48d; exit=0; EXPECT=matched; output-sha256=6d5382e10350411e52701b8f56b4e68cd9fd094532f094f9280af996fb122bce; output-bytes=4157; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/frontend; path=330df7af71d3/20 entries

- [x] G6: canonical route parsing, camera ownership, distinct location/recenter actions, marker motion, shortest bearing turn, and standing-course stability regressions pass
  CHECK: flutter test test/map_api_test.dart test/evik_osm_map_view_location_test.dart test/driver_motion_test.dart --reporter compact
  EXPECT: All tests passed
  CWD: frontend
  EVIDENCE: automatic-evidence=v1; definition-sha256=c8fa128fda8c1cb84b9f6e1efe4a851ddd5177f74b7351aa7ea0cf51a604c783; exit=0; EXPECT=matched; output-sha256=fea30bcb52adfab7239e19177b3c458abdbe67f7f2fd19b2fb4848b17f4c2994; output-bytes=5315; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/frontend; path=330df7af71d3/20 entries

- [x] G7: real TrackingScreen renders compact/expanded states and remains usable at 320 logical pixels with 200 percent text
  CHECK: flutter test test/ui_audit_screens_test.dart --reporter compact
  EXPECT: All tests passed
  CWD: frontend
  EVIDENCE: automatic-evidence=v1; definition-sha256=e7dc9327700f91c1472714a0860c042158ab60102aa82a197fc88eacab24b9cb; exit=0; EXPECT=matched; output-sha256=b2c1bd0986eaa97e5f14b98aabd27044b37060016b91d987b800fae3375c0869; output-bytes=4972; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/frontend; path=330df7af71d3/20 entries

- [x] G8: internal order chat and client/driver navigation regressions pass without SMS substitution
  CHECK: flutter test test/chat_controller_test.dart test/chat_message_test.dart test/chat_screen_test.dart test/client_chat_navigation_test.dart test/driver_chat_navigation_test.dart --reporter compact
  EXPECT: All tests passed
  CWD: frontend
  EVIDENCE: automatic-evidence=v1; definition-sha256=15b7250b0d4a89d041858add0cd84ef2f9388af1c64c2aa3ce70891049bef306; exit=0; EXPECT=matched; output-sha256=7ad94de60928b079be67f957eaac41b90f9ad9c58bf98196287e498b09b6b60e; output-bytes=7601; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/frontend; path=330df7af71d3/20 entries

- [x] G9: Flutter static analysis passes
  CHECK: flutter analyze --no-pub
  EXPECT: No issues found
  CWD: frontend
  EVIDENCE: automatic-evidence=v1; definition-sha256=c41f846c2637751edfd4e294b977a126ce2612ddae0761cf671a2ffbfa67dd2f; exit=0; EXPECT=matched; output-sha256=8ac60db1740ae5412f4ee2fecc16d8205bf4be1cb10f387ae31778525fbcf478; output-bytes=96; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/frontend; path=330df7af71d3/20 entries

- [x] G10: complete Flutter suite passes, including current goldens
  CHECK: flutter test --reporter compact
  EXPECT: All other tests passed
  CWD: frontend
  EVIDENCE: automatic-evidence=v1; definition-sha256=dd7c79875bd97f83e15bbb00d628f916f0ad154c506b325c99354ff2469c0b67; exit=0; EXPECT=matched; output-sha256=5824d89c51e7b74b0d3d1f5464b619cea0d3bf01c8c1857077f07df9e9464430; output-bytes=59706; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK/frontend; path=330df7af71d3/20 entries

- [x] G11: current working-tree diff has no whitespace errors
  CHECK: sh -c 'git diff --check && echo DIFF_CHECK_OK'
  EXPECT: DIFF_CHECK_OK
  EVIDENCE: automatic-evidence=v1; definition-sha256=4a47cb3be51b6864e4a97f9412fa38da3c930831024073a5d9c313bdc4e068e6; exit=0; EXPECT=matched; output-sha256=feec8486656b648336339cd5da9eb6ef1512a1bb4470510a27158354525dbc4e; output-bytes=14; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK; path=330df7af71d3/20 entries

- [x] G12: final GitNexus change analysis is complete and neither partial nor truncated
  CHECK: node .gitnexus/run.cjs detect-changes --scope all --repo .
  EXPECT: Changes:
  EVIDENCE: automatic-evidence=v1; definition-sha256=db8d53139cd97cf7c357b17feaf23832e6b355938cbe4d194e297236468e15c0; exit=0; EXPECT=matched; output-sha256=d405986399df8b17fb94f69b3137a056788503d31b65a0055cd4ed5f64402f5c; output-bytes=2145; shell=/bin/sh; cwd=/Users/rasul/Documents/EVIK; path=330df7af71d3/20 entries

- [x] G13: simulator visual QA records real OSM tiles and visible attribution for overview/close zoom and compact/expanded sheet, without creating an order
  EVIDENCE: real audit-fixture screen captured from `flutter run` on iPhone 17 simulator with no order creation; compact overview `/tmp/evik-tracking-current.png`, expanded sheet `/tmp/evik-tracking-expanded-accepted.png`, close zoom/manual-camera `/tmp/evik-tracking-close-accepted.png`; all show live `tile.openstreetmap.org` tiles and visible `© OpenStreetMap contributors`; `flutter test integration_test/tracking_visual_test.dart -d 99BB40BF-9AF4-4A44-B222-811713DBDB01 --dart-define=EVIK_UI_AUDIT=true --dart-define=EVIK_SKIP_AUTH=true --dart-define=EVIK_UI_AUDIT_START=/order/tracking --reporter expanded` passed and exercised expand/collapse, zoom, and recenter availability

- [ ] G14: physical client plus driver walkthrough covers accept, movement, deviation, stop, background, network loss/recovery, transport, and completion
  EVIDENCE: pending

- [ ] G15: physical measurements record GPS-to-screen latency, routeVersion convergence, stale frequency, routing request count, frame performance, and battery usage
  EVIDENCE: pending
