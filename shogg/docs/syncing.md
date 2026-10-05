# CalDAV Syncing

This document describes the syncing approaches available in Shogg.

## CTag-based Sync

Shogg implements Apple's ctag extension for calendar synchronization. This is the recommended approach and is widely supported by CalDAV servers.

### How it works

- **CTag (Calendar Collection Tag)**: A string property on a calendar collection that changes whenever *any* calendar object in that collection changes.
- **ETag**: A property on each individual calendar object that changes when that specific object changes.

### Sync Flow

1. **First sync**: Use `fetch_calendars` to get calendars with their ctags, then use `fetch_tasks` to get all items
2. **Subsequent syncs**: Check if the ctag has changed, only re-fetch tasks if it did

### API

```gleam
// Get calendars with ctags
let assert Ok(calendars) = calendar.fetch_calendars(client, home_set)

// Store the calendar and its ctag locally
let assert Ok(current) = list.first(calendars)

// Later, check if the calendar changed: this sends the getctag PROPFIND
// and compares the answer with the ctag stored on the calendar.
case calendar.has_changed(client, current) {
  Ok(calendar.Changed(new_calendar)) -> {
    // Something changed: re-fetch tasks
    let assert Ok(tasks) = task.fetch_tasks(client, new_calendar)
    // Update local store
  }
  Ok(calendar.Unchanged) -> Nil
  Error(_) -> Nil
}
```

### Functions

- `calendar.fetch_calendars(client, home_set)` - Lists the calendars with their ctags via a PROPFIND over the calendar home set
- `calendar.changed_request(client, calendar)` - Creates a PROPFIND request for the current ctag of a calendar
- `calendar.parse_changed(calendar, response)` - Parses the ctag response and compares it with the stored ctag, giving `Changed(new_calendar)` or `Unchanged`
- `calendar.has_changed(client, calendar)` - Convenience around the two above: sends the request and parses the response; this is what the server's change polling uses

---

## Sync-Collection (RFC 6578)

An alternative, more efficient approach defined in RFC 6578. This is the standardized way to sync collections but is less widely supported than ctags.

### How it works

- Server provides a `sync-token` on the collection
- Client sends `sync-collection` REPORT with the token
- Server returns only changes since last sync

### Status

Not currently implemented in Shogg. Would require:
- `sync_token` property on Calendar
- `sync_collection_request(client, calendar, sync_token)` 
- Parser for sync-response (returns created/modified/deleted items)

---

## Comparison

| Feature        | CTag                             | Sync-Collection      |
|----------------|----------------------------------|----------------------|
| Standard       | Apple extension                  | RFC 6578             |
| Server support | Wide                             | Limited              |
| Efficiency     | Requires full re-fetch on change | Returns only changes |
| Implementation | Simple                           | Complex              |

## Recommendation

Use the **CTag approach** for now. It works with most CalDAV servers (including Radicale, Nextcloud, Apple Calendar Server, etc.) and is simpler to implement.
