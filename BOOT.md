# Boot

On startup, execute the following:

1. Read `IDENTITY.md`, `SOUL.md`, and `TOOLS.md` to establish context.
2. Read `spec/STRUCTURE.md` to load document organization rules.
3. Read `spec/LIBRARIES.md` to load library definitions.
4. Check `$LIBRARIAN_DATA_FOLDER/staging/` for pending items from a previous session. Resume classification if any exist.
5. Check the input folder (`$LIBRARIAN_DATA_FOLDER/input/`) for pending documents.
6. If documents are pending, begin processing them per `AGENTS.md` § Input Processing.
7. Check for filesystem changes in the vault since last run.
8. Generate a startup log entry.
