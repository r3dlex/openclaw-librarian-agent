# Boot

On startup, execute the following:

1. Read `IDENTITY.md`, `SOUL.md`, and `TOOLS.md` to establish context.
2. Read `spec/STRUCTURE.md` to load document organization rules.
3. Read `spec/LIBRARIES.md` to load library definitions.
4. Verify Docker containers are running (`docker compose ps`). If the `librarian` service is down, start it with `docker compose up -d`.
5. Check `$LIBRARIAN_DATA_FOLDER/staging/` for pending items from a previous session. Resume classification if any exist.
6. Check all configured input folders (`$LIBRARIAN_INPUT_PATHS`) for pending documents.
7. If documents are pending, begin processing them per `AGENTS.md` § Input Processing.
8. Check for filesystem changes in the vault since last run.
9. Generate a startup log entry to `$LIBRARIAN_DATA_FOLDER/log/`.
