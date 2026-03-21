defmodule Librarian.IAMQ do
  @moduledoc """
  Inter-Agent Message Queue client.

  Registers the Librarian with the Openclaw IAMQ service, sends periodic
  heartbeats, and polls the inbox for messages from other agents.
  """
  use GenServer
  require Logger

  @agent_id "librarian_agent"
  @heartbeat_interval :timer.minutes(2)
  @poll_interval :timer.seconds(30)

  # ── Public API ──

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc "Send a message to another agent via IAMQ."
  def send_message(to, subject, body, opts \\ []) do
    GenServer.call(__MODULE__, {:send, to, subject, body, opts})
  end

  @doc "Broadcast a message to all agents."
  def broadcast(subject, body, opts \\ []) do
    send_message("broadcast", subject, body, opts)
  end

  @doc "List all currently online agents."
  def list_agents do
    GenServer.call(__MODULE__, :list_agents)
  end

  # ── GenServer callbacks ──

  @impl true
  def init(:ok) do
    base_url = Application.get_env(:librarian, :iamq_url, "http://127.0.0.1:18790")

    state = %{
      base_url: base_url,
      registered: false
    }

    send(self(), :register)
    {:ok, state}
  end

  @impl true
  def handle_call({:send, to, subject, body, opts}, _from, state) do
    payload = %{
      from: @agent_id,
      to: to,
      type: Keyword.get(opts, :type, "info"),
      priority: Keyword.get(opts, :priority, "NORMAL"),
      subject: subject,
      body: body,
      replyTo: Keyword.get(opts, :reply_to),
      expiresAt: Keyword.get(opts, :expires_at)
    }

    result = post(state.base_url, "/send", payload)
    {:reply, result, state}
  end

  def handle_call(:list_agents, _from, state) do
    result =
      case get(state.base_url, "/agents") do
        {:ok, %{"agents" => agents}} -> {:ok, agents}
        error -> error
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:register, state) do
    registration = %{
      agent_id: @agent_id,
      name: "Librarian",
      emoji: "📚",
      description: "Document archivist and knowledge organizer — search, summarize, archive",
      capabilities: ["search", "summarize", "archive", "knowledge_management"],
      workspace: Application.get_env(:librarian, :workspace_path, "")
    }

    case post(state.base_url, "/register", registration) do
      {:ok, _} ->
        Logger.info("IAMQ: registered as #{@agent_id}")
        schedule(:heartbeat, @heartbeat_interval)
        schedule(:poll_inbox, @poll_interval)
        {:noreply, %{state | registered: true}}

      {:error, reason} ->
        Logger.warning("IAMQ: registration failed (#{inspect(reason)}), retrying in 30s")
        schedule(:register, :timer.seconds(30))
        {:noreply, state}
    end
  end

  def handle_info(:heartbeat, state) do
    case post(state.base_url, "/heartbeat", %{agent_id: @agent_id}) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("IAMQ: heartbeat failed (#{inspect(reason)})")
    end

    schedule(:heartbeat, @heartbeat_interval)
    {:noreply, state}
  end

  def handle_info(:poll_inbox, state) do
    try do
      process_inbox(state.base_url)
    rescue
      e -> Logger.error("IAMQ: inbox poll failed: #{Exception.message(e)}")
    end

    schedule(:poll_inbox, @poll_interval)
    {:noreply, state}
  end

  # ── Inbox Processing ──

  defp process_inbox(base_url) do
    case get(base_url, "/inbox/#{@agent_id}?status=unread") do
      {:ok, %{"messages" => messages}} when is_list(messages) and messages != [] ->
        Logger.info("IAMQ: #{length(messages)} unread message(s)")

        Enum.each(messages, fn msg ->
          handle_message(msg)
          mark_read(base_url, msg["id"])
        end)

      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("IAMQ: inbox fetch failed (#{inspect(reason)})")
    end
  end

  defp handle_message(msg) do
    from = msg["from"] || "unknown"
    subject = msg["subject"] || "(no subject)"
    type = msg["type"] || "info"

    Logger.info("IAMQ: [#{type}] from #{from}: #{subject}")

    # Log the full message for the agent to pick up in its next heartbeat
    data_folders = Application.get_env(:librarian, :data_folders, [])
    log_dir = case data_folders do
      [primary | _] -> Path.join(primary, "log")
      _ -> nil
    end

    if log_dir do
      File.mkdir_p!(log_dir)
      timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
      safe_ts = String.replace(timestamp, ":", "-")
      log_file = Path.join(log_dir, "iamq-#{safe_ts}-#{from}.json")

      File.write!(log_file, Jason.encode!(msg, pretty: true))
    end
  end

  defp mark_read(_base_url, nil), do: :ok
  defp mark_read(base_url, message_id) do
    patch(base_url, "/messages/#{message_id}", %{status: "read"})
  end

  # ── HTTP helpers ──

  defp post(base_url, path, payload) do
    url = base_url <> path

    case Req.post(url, json: payload, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp get(base_url, path) do
    url = base_url <> path

    case Req.get(url, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp patch(base_url, path, payload) do
    url = base_url <> path

    case Req.request(method: :patch, url: url, json: payload, receive_timeout: 5_000) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp schedule(message, interval) do
    Process.send_after(self(), message, interval)
  end
end
