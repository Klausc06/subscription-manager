# TB-17 Calendar Preview and ICS Design

- Date: 2026-07-29
- Issue: #18 — Preview Calendar events and export a permission-free ICS
- Status: Approved for autonomous implementation

## Decision

Add a pure Calendar-projection query to `SubscriptionWorkspace`. It reads the
same subscription and preference repositories as the rest of the app and
returns sorted `CalendarProjectionEvent` values. The UI preview and the ICS
encoder consume that one projection, so event count, day, title, amount
visibility, URL, notes, UID, and alarms cannot drift apart.

The query starts at the billing-local day containing the injected `now`, ends
at the billing-local end of the selected six- or twelve-month horizon, and
emits only future expected charges in that inclusive range. It excludes
archived subscriptions and every cancelled or expired lifecycle because those
states have no future expected charges. A deleted subscription is absent from
the repository and therefore cannot appear. The existing Gregorian,
locale-stable schedule calculation remains the source of renewal dates.

## Event representation

Each event carries a stable UID derived from its subscription UUID and the
scheduled billing-local date, the all-day start/end dates, localized title and
notes, optional management URL, and alarm offsets. Active renewals receive
`-P7D` and `-P1D`; trial renewals receive `-P3D` and `-P1D`. The title is the
service name plus the formatted original amount unless the synced
`hideAmountsInCalendar` preference is true. Notes retain the plan and original
amount only when amounts are visible; management links remain `URL` properties
instead of being sent to any service.

`UserPreferences` gains the additive `hideAmountsInCalendar` Boolean, default
`false`, and the SwiftData record gets the matching defaulted field. Settings
lets a person change it before previewing or exporting. Existing stores decode
the missing field as false.

## ICS encoding and native export

The encoder produces a UTF-8 RFC 5545 `VCALENDAR` with CRLF line endings,
`PRODID`, `VERSION:2.0`, `CALSCALE:GREGORIAN`, one `VEVENT` per projection,
`UID`, deterministic `DTSTAMP`, date-value `DTSTART` and next-day exclusive
`DTEND`, escaped `SUMMARY`/`DESCRIPTION`, optional `URL`, and two display
`VALARM`s. It escapes backslash, comma, semicolon, and line breaks in TEXT
values and folds each content line at the UTF-8 75-octet boundary using
CRLF-plus-space continuation. The file is an offline export; no EventKit,
Calendar authorization, account, or network adapter is introduced.

`CalendarProjectionView` shows an accessible textual list and the current
horizon/amount-visibility state. Its Export button writes the in-memory ICS
payload via a `FileDocument` and the native `fileExporter`, exposing the
standard share/save sheet on each supported platform. The preview is reachable
from Settings on iPhone, iPad, and Mac.

## Verification

- Core workspace tests prove selected horizon boundaries, lifecycle exclusion,
  stable UIDs, hidden amounts, localized fields, and trial/ordinary alarms.
- Encoder tests independently parse the resulting fixture with a strict
  iCalendar parser, checking events, date values, UIDs, URL, alarm triggers,
  escaping, and folded UTF-8 content lines.
- UI tests prove preview/export needs neither Calendar authorization nor an
  EventKit adapter and retain English/Simplified Chinese accessibility labels.
