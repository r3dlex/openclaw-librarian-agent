ExUnit.start()

{:ok, _} = Application.ensure_all_started(:librarian)

Ecto.Migrator.with_repo(Librarian.Repo, &Ecto.Migrator.run(&1, :up, all: true))

Ecto.Adapters.SQL.Sandbox.mode(Librarian.Repo, :manual)
