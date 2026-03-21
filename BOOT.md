# Boot

On startup, execute the following:

1. Read `IDENTITY.md`, `SOUL.md`, and `TOOLS.md` to establish context.
2. Read `spec/STRUCTURE.md` to load document organization rules.
3. Read `spec/LIBRARIES.md` to load library definitions.
4. Verify Docker containers are running (`docker compose ps`). If the `librarian` service is down, start it with `docker compose up -d`.
5. **Register with IAMQ** — the Elixir service handles this automatically (`Librarian.IAMQ`), but verify registration succeeded:
   ```bash
   curl -s http://127.0.0.1:18790/agents | grep librarian_agent
   ```
   If not registered, the service will retry every 30s. Check logs for errors.
6. **Check IAMQ inbox** for messages received while offline:
   ```bash
   curl -s http://127.0.0.1:18790/inbox/librarian_agent?status=unread
   ```
   Process any unread messages. Mark as read/acted via `PATCH /messages/{id}`.
7. **Discover other agents** — see who's online:
   ```bash
   curl -s http://127.0.0.1:18790/agents
   ```
8. Check `$LIBRARIAN_DATA_FOLDER/staging/` for pending items from a previous session. Resume classification if any exist.
9. Check all configured input folders (`$LIBRARIAN_INPUT_PATHS`) for pending documents.
10. If documents are pending, begin processing them per `AGENTS.md` § Input Processing.
11. Check for filesystem changes in the vault since last run.
12. Generate a startup log entry to `$LIBRARIAN_DATA_FOLDER/log/`.
