/// Returns whether a development-only feature may be enabled for this build.
///
/// A supplied `--dart-define` must never turn authentication bypasses or UI
/// previews on in a release binary, including an accidentally misconfigured
/// CI build.
bool developmentFeatureEnabled({
  required bool requested,
  required bool releaseMode,
}) {
  return requested && !releaseMode;
}
