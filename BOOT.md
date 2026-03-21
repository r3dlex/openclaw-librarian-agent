# Boot

On startup, execute the following:

1. Read `IDENTITY.md`, `SOUL.md`, and `TOOLS.md` to establish context.
2. Read `spec/STRUCTURE.md` to load document organization rules.
3. Read `spec/LIBRARIES.md` to load library definitions.
4. Verify Docker containers are running (`docker compose ps`). If the `librarian` service is down, start it with `docker compose up -d`.
5. **Verify IAMQ registration** — the Elixir service (`Librarian.IAMQ`) handles registration automatically (HTTP primary, file-based fallback). Check logs:
   ```bash
   docker compose logs librarian 2>&1 | grep -i "iamq" | tail -5
   ```
   If registered, you'll see `IAMQ: registered via HTTP` or `IAMQ: using file-based queue`. If failing, check `IAMQ_URL` and `IAMQ_QUEUE_PATH` in `.env`.
6. **Check IAMQ inbox** for messages received while offline:
   ```bash
   curl -s http://127.0.0.1:18790/inbox/librarian_agent?status=unread
   ```
   Process any unread messages. Mark as read/acted via `PATCH /messages/{id}`.
7. **Check workspace inbox** — other agents may write directly to `inbox/`:
   ```bash
   ls inbox/
   ```
   Process any pending messages and act on them.
8. **Discover other agents** — see who's online:
   ```bash
   curl -s http://127.0.0.1:18790/agents
   ```
9. Check `$LIBRARIAN_DATA_FOLDER/staging/` for pending items from a previous session. Resume classification if any exist.
10. Check all configured input folders (`$LIBRARIAN_INPUT_PATHS`) for pending documents.
11. If documents are pending, begin processing them per `AGENTS.md` § Input Processing.
12. Check for filesystem changes in the vault since last run.
13. Generate a startup log entry to `$LIBRARIAN_DATA_FOLDER/log/`.
