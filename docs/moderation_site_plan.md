# EVIK Moderation Site Plan

## Goal

Create an internal web moderation console for EVIK operators. The console must show the operational state of the app, let moderators review driver verification requests, react to user reports, inspect orders, and leave an auditable trail for every decision.

## Phase 1: Driver Moderation MVP

Core scope:
- Admin web entry at `/admin`.
- Secure admin-only access.
- Dashboard with pending checks, overdue checks, active orders, blocked users, and recent decisions.
- Driver verification queue with filters by status, risk, vehicle type, and submission time.
- Case detail view with driver profile, vehicle data, document list, risk signals, and moderation history.
- Approve, reject, request changes, and block actions.
- Required rejection reason and visible success/error feedback.
- Empty, loading, error, offline, and retry states.

Production data needed:
- `driver_verifications`
- `driver_verification_documents`
- `moderation_decisions`
- `moderation_audit_log`

## Phase 2: Operational Moderation

Add:
- Live orders board with status, route, assigned driver, client, price, and incident flags.
- Manual order intervention: cancel, reassign, mark issue, contact user.
- Driver online map/list with stale location warnings.
- User and driver profiles with order history and moderation notes.
- Payment and promocode review for suspicious activity.

## Phase 3: Trust And Safety

Add:
- Reports queue for complaints, bad documents, fraud, unsafe behavior, and payment disputes.
- Risk scoring signals and duplicate detection.
- Escalation workflow for high-risk cases.
- Internal comments and assignment to moderators.
- SLA tracking and moderator performance metrics.

## UX System

Layout:
- Desktop-first admin layout with left navigation, top status bar, main queue, and detail panel.
- Tablet support with stacked queue and detail.
- Mobile fallback with a single-column queue and drill-in details.

Spacing:
- 8px grid, dense but readable admin surfaces.
- 16px minimum card padding, 44px minimum touch targets.

Typography:
- 12px labels and metadata.
- 14px body/table text.
- 16px section titles.
- 24px dashboard page title.

Colors:
- Neutral background for focus.
- Orange for primary EVIK action.
- Green for approved/safe.
- Amber for pending/risk.
- Red for rejected/blocked.
- Blue for informational operational state.

States:
- Loading skeletons for queue and detail.
- Empty states per filter.
- Error state with retry.
- Disabled actions while a decision is being saved.
- Optimistic status update only after server confirmation in production.

Motion:
- Short 160-220ms transitions for panel selection and status changes.
- No decorative motion in admin workflows.

Accessibility:
- Keyboard navigable controls.
- Visible focus states.
- Color is never the only status indicator.
- Table/list content readable at 14px+.

## API Plan

Initial admin endpoints:
- `GET /api/v1/admin/moderation/driver-verifications?status=pending&limit=50`
- `GET /api/v1/admin/moderation/driver-verifications/{id}`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/approve`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/reject`
- `POST /api/v1/admin/moderation/driver-verifications/{id}/request-changes`
- `GET /api/v1/admin/audit-log?entity_type=driver_verification&entity_id=...`

Security:
- Admin role required on every endpoint.
- All decisions written to audit log.
- No raw sensitive document URLs in general lists.
- Short-lived signed URLs for document previews.
- Structured logs without document contents or tokens.

