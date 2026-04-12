# Release Checklist (Google TV / Low RAM)

Use this checklist before generating a production build.

## 1) Code Freeze and Scope

- [ ] Confirm only intended files are changed (`git status`).
- [ ] Confirm no debug-only experiments are left in code.
- [ ] Confirm this release contains one feature scope only (auth/home playlist flow).

## 2) Static Validation

- [ ] Run `flutter pub get`.
- [ ] Run `flutter analyze` and resolve all analyzer errors.
- [ ] Run `flutter test` and ensure all tests pass.

## 3) Environment and Secrets

- [ ] Verify production API host/base URL values in config.
- [ ] Verify no secrets/tokens are hardcoded in source files.
- [ ] Verify production signing config is correct (keystore/profiles).

## 4) Critical Functional Flows

### Auth and Session
- [ ] Fresh install -> splash -> auth gate -> pair device -> home.
- [ ] Restart app with valid stored session -> splash -> home (no re-login).
- [ ] Invalid/expired access token -> refresh auth path succeeds.
- [ ] Missing/invalid secret in local session -> app safely returns to auth.

### Playlist and Socket
- [ ] Playlist fetch succeeds with valid token and `vehicleId`.
- [ ] Socket reconnect/refresh does not create duplicate update events.
- [ ] Refresh during active ad applies playlist on boundary (no abrupt cut).
- [ ] 400/401 playlist response triggers auth recovery path.

### Media Rotation
- [ ] Poster-only playlist rotates correctly.
- [ ] Video-only playlist rotates correctly.
- [ ] Mixed poster + video playlist rotates in expected order.
- [ ] Video playback error retries up to configured max, then skips safely.

## 5) Low-RAM and Stability Validation (1 GB Target)

- [ ] Run 4-8 hour soak test with active playlist rotation.
- [ ] Monitor memory for growth/regression during long run.
- [ ] Validate app stability across pause/resume lifecycle cycles.
- [ ] Validate only one active `VideoPlayerController` at a time.
- [ ] Validate controller disposal on transitions and app close.

## 6) Video Cache and Storage Safety

- [ ] Verify cached videos play from local path when present.
- [ ] Verify stale cache purge removes entries not in active playlist.
- [ ] Verify cache eviction respects file/size caps.
- [ ] Verify corrupted or too-small cache files are discarded safely.
- [ ] Verify storage pressure does not crash playback flow.

## 7) TV UX and Input

- [ ] Verify all retry/recovery actions are focusable via remote.
- [ ] Verify focus appears correctly on error/retry button.
- [ ] Verify no touch-only interaction is required.
- [ ] Verify poster/video rendering performance remains smooth on TV device.

## 8) Network Resilience

- [ ] Test startup with no network -> user sees clear recovery path.
- [ ] Test slow network (high latency) -> no fatal startup loops.
- [ ] Test intermittent drops during playback -> playback recovers safely.

## 9) Build and Artifact Verification

- [ ] Build release artifact:
  - [ ] `flutter build apk --release` (or)
  - [ ] `flutter build appbundle --release`
- [ ] Install release artifact on target TV hardware.
- [ ] Validate startup time and first content render time.
- [ ] Validate no debug banners/log spam in release.

## 10) Observability and Rollback Readiness

- [ ] Crash reporting is enabled for release variant.
- [ ] Error logs include enough context for auth/playlist/video failures.
- [ ] Previous stable build artifact is available for rollback.
- [ ] Release notes include known risks and tested scenarios.

## Go / No-Go Decision

Go only when:
- [ ] All mandatory checks above are complete.
- [ ] No blocker severity bugs remain.
- [ ] Stakeholder sign-off is complete.

