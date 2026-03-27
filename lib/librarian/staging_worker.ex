defmodule Librarian.StagingWorker do
  @moduledoc """
  Periodic worker that processes the staging folder.

  Runs every hour to:
  1. Detect orphaned items (status: "filed" but vault_path is null)
  2. Clean up stale items that have been pending too long
  3. Report staging health via IAMQ

  The actual classification and vault-write is done by the OpenClaw agent
  during its HEARTBEAT loop. This worker handles the housekeeping that
  should happen automatically regardless of agent sessions.
  """
  use GenServer
  require Logger

  @check_interval_ms :timer.minutes(60)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    # First check after 5 minutes (let other services start)
    Process.send_after(self(), :check_staging, :timer.minutes(5))
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_staging, state) do
    try do
      run_checks()
    rescue
      e -> Logger.error("[StagingWorker] Check failed: #{Exception.message(e)}")
    end

    Process.send_after(self(), :check_staging, @check_interval_ms)
    {:noreply, state}
  end

  defp run_checks do
    pending = Librarian.Staging.list_pending()
    filed_orphans = list_filed_orphans()

    if pending != [] do
      Logger.info("[StagingWorker] #{length(pending)} pending item(s) in staging")
    end

    if filed_orphans != [] do
      Logger.warning(
        "[StagingWorker] #{length(filed_orphans)} orphaned item(s) " <>
          "(status: filed, vault_path: null)"
      )

      # Report orphans via IAMQ so the agent and user are aware
      orphan_summary =
        filed_orphans
        |> Enum.map(fn meta ->
          "  - #{meta["id"]}: #{meta["source_file"] || "unknown"} (filed at #{meta["filed_at"] || "?"})"
        end)
        |> Enum.join("\n")

      try do
        Librarian.IAMQ.broadcast(
          "Staging orphans detected",
          "#{length(filed_orphans)} item(s) marked as filed but missing vault_path:\n#{orphan_summary}",
          priority: "HIGH",
          type: "error"
        )
      rescue
        _ -> :ok
      end
    end

    # Run the standard cleanup for filed items older than 24h
    Librarian.Staging.cleanup()

    # Log summary
    total = length(pending) + length(filed_orphans)

    if total == 0 do
      Logger.debug("[StagingWorker] Staging clean — nothing to report")
    end
  end

  defp list_filed_orphans do
    staging_dir = staging_dir()

    if File.dir?(staging_dir) do
      staging_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".meta.json"))
      |> Enum.flat_map(fn file ->
        path = Path.join(staging_dir, file)

        case File.read(path) do
          {:ok, content} when content != "" ->
            case Jason.decode(content) do
              {:ok, meta} ->
                if meta["status"] == "filed" and (meta["vault_path"] == nil or meta["vault_path"] == "") do
                  [meta]
                else
                  []
                end

              _ ->
                []
            end

          _ ->
            []
        end
      end)
    else
      []
    end
  end

  defp staging_dir do
    data_folder = Application.get_env(:librarian, :data_folder, "")
    Path.join(data_folder, "staging")
  end
end
