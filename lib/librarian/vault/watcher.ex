defmodule Librarian.Vault.Watcher do
  @moduledoc """
  Watches the Obsidian vault for filesystem changes.

  Detects human edits and triggers reindexing. Ignores changes
  made by the Librarian itself (tracked via an internal write log).

  Uses a debounce window to coalesce rapid filesystem events from
  Google Drive sync, which can fire multiple events for a single
  logical change.
  """
  use GenServer
  require Logger

  @debounce_ms 2_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    vault_path = Application.get_env(:librarian, :vault_path, "")

    if vault_path != "" and File.dir?(vault_path) do
      {:ok, pid} = FileSystem.start_link(dirs: [vault_path])
      FileSystem.subscribe(pid)
      Logger.info("Vault watcher started for: #{vault_path}")
      {:ok, %{watcher_pid: pid, own_writes: %{}, pending: %{}}}
    else
      Logger.warning("Vault path not available: #{vault_path}. Watcher in degraded mode.")
      Process.send_after(self(), :retry_watch, 60_000)
      {:ok, %{watcher_pid: nil, own_writes: %{}, pending: %{}}}
    end
  end

  @impl true
  def handle_info({:file_event, _pid, {path, events}}, state) do
    now = System.monotonic_time(:millisecond)

    # Skip own writes within debounce window
    case Map.get(state.own_writes, path) do
      nil ->
        # External change — debounce it
        pending = Map.put(state.pending, path, {events, now})
        timer_ref = Process.send_after(self(), {:debounce_fire, path}, @debounce_ms)
        {:noreply, %{state | pending: Map.put(pending, path, {events, now, timer_ref})}}

      wrote_at when now - wrote_at < @debounce_ms ->
        # Own write within debounce window — ignore
        {:noreply, state}

      _expired ->
        # Own write record expired — treat as external
        own_writes = Map.delete(state.own_writes, path)
        pending = Map.put(state.pending, path, {events, now})
        Process.send_after(self(), {:debounce_fire, path}, @debounce_ms)
        {:noreply, %{state | own_writes: own_writes, pending: pending}}
    end
  end

  @impl true
  def handle_info({:debounce_fire, path}, state) do
    case Map.pop(state.pending, path) do
      {nil, _pending} ->
        {:noreply, state}

      {{events, _timestamp, _timer_ref}, pending} ->
        Logger.info("Vault change detected: #{path} (#{inspect(events)})")
        handle_external_change(path, events)
        {:noreply, %{state | pending: pending}}

      {{events, _timestamp}, pending} ->
        Logger.info("Vault change detected: #{path} (#{inspect(events)})")
        handle_external_change(path, events)
        {:noreply, %{state | pending: pending}}
    end
  end

  @impl true
  def handle_info(:retry_watch, state) do
    vault_path = Application.get_env(:librarian, :vault_path, "")

    if vault_path != "" and File.dir?(vault_path) do
      {:ok, pid} = FileSystem.start_link(dirs: [vault_path])
      FileSystem.subscribe(pid)
      Logger.info("Vault watcher recovered for: #{vault_path}")
      {:noreply, %{state | watcher_pid: pid}}
    else
      Process.send_after(self(), :retry_watch, 60_000)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @doc "Register a path as an own write to suppress reprocessing within the debounce window."
  def register_own_write(path) do
    GenServer.cast(__MODULE__, {:register_write, path})
  end

  @impl true
  def handle_cast({:register_write, path}, state) do
    now = System.monotonic_time(:millisecond)
    {:noreply, %{state | own_writes: Map.put(state.own_writes, path, now)}}
  end

  defp handle_external_change(path, _events) do
    if String.ends_with?(path, ".md") do
      Librarian.Vault.Backup.backup(path)
      Librarian.Indexer.reindex(path)
    end
  end
end
