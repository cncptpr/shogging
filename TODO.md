# Todo
- Use actual timestamps for times
- Parse ical via dynamic

# Done
- ~~Make a backdrop to rename ui, to avoid accidental delete / checking~~ — dialogs are now modal with a backdrop, and delete / check have their own controls.
- ~~Make the create new todo ui a spa / use alpine.~~ — the frontend is a Lustre SPA talking to the server over a WebSocket; Alpine is gone.
- ~~Figure out, how to make the rename a spa / use apline.~~ — same: rename happens in the SPA's dialog.
