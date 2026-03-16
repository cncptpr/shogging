# CalDAV Syncing

This document describes the syncing approaches available in Shogg.

## CTag-based Sync

Shogg implements Apple's ctag extension for calendar synchronization. This is the recommended approach and is widely supported by CalDAV servers.

### How it works

- **CTag (Calendar Collection Tag)**: A string property on a calendar collection that changes whenever *any* calendar object in that collection changes.
- **ETag**: A property on each individual calendar object that changes when that specific object changes.

### Sync Flow

1. **First sync**: Use `fetch_calendars` to get calendars with their ctags, then use `fetch_todos` to get all items
2. **Subsequent syncs**: Check if the ctag has changed, only re-fetch todos if it did

### API

```gleam
// Get calendars with ctags
let assert Ok(calendars) = calendar.fetch_calendars(client, user_info)

// Store the calendar and its ctag locally
let calendar = calendars |> list.first()

// Later, check if calendar changed
let assert Ok(current_ctag) = calendar.get_ctag_request(client, calendar)
  |> client.io.send
  |> result.map(calendar.parse_ctag_response)
let changed = current_ctag != calendar.ctag

// If changed, re-fetch todos
if changed {
  let assert Ok(todos) = vtodo.fetch_todos(client, calendar)
  // Update local store
}
```

### Functions

- `calendar.get_ctag_request(client, calendar)` - Creates a PROPFIND request to get the current ctag for a calendar
- `calendar.parse_ctag_response(response)` - Parses the ctag from the server response

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
