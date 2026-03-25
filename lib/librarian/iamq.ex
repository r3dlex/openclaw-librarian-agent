defmodule Librarian.IAMQ do
  @moduledoc """
  Inter-Agent Message Queue client.

  Dual-mode: tries HTTP API first, falls back to file-based queue.
  The file-based queue reads/writes JSON files per the IAMQ PROTOCOL.md spec.
  """
  use GenServer
  import Bitwise
  require Logger

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
    queue_path = Application.get_env(:librarian, :iamq_queue_path, "")
    agent_id = Application.get_env(:librarian, :iamq_agent_id, "librarian_agent")

    heartbeat_ms =
      case System.get_env("IAMQ_HEARTBEAT_MS") do
        nil -> :timer.minutes(5)
        val -> String.to_integer(val)
      end

    poll_ms =
      case System.get_env("IAMQ_POLL_MS") do
        nil -> :timer.seconds(60)
        val -> String.to_integer(val)
      end

    state = %{
      base_url: base_url,
      queue_path: queue_path,
      agent_id: agent_id,
      heartbeat_ms: heartbeat_ms,
      poll_ms: poll_ms,
      mode: nil,
      registered: false
    }

    send(self(), :register)
    {:ok, state}
  end

  @impl true
  def handle_call({:send, to, subject, body, opts}, _from, state) do
    msg = build_message(to, subject, body, opts)
    result = do_send(state, msg)
    {:reply, result, state}
  end

  def handle_call(:list_agents, _from, state) do
    result =
      case state.mode do
        :http ->
          case http_get(state.base_url, "/agents") do
            {:ok, %{"agents" => agents}} -> {:ok, agents}
            error -> error
          end

        :file ->
          {:ok, list_agent_dirs(state.queue_path)}

        nil ->
          {:error, :not_registered}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info(:register, state) do
    registration = %{
      agent_id: state.agent_id,
      name: System.get_env("IAMQ_AGENT_NAME", "Librarian"),
      emoji: System.get_env("IAMQ_AGENT_EMOJI", "📚"),
      description: System.get_env("IAMQ_AGENT_DESC", "Document archivist and knowledge organizer — search, summarize, archive"),
      capabilities: parse_caps(System.get_env("IAMQ_AGENT_CAPABILITIES", "search,summarize,archive,knowledge_management")),
      workspace: Application.get_env(:librarian, :workspace_path, "")
    }

    # Try HTTP first
    case http_post(state.base_url, "/register", registration) do
      {:ok, _} ->
        Logger.info("IAMQ: registered via HTTP as #{state.agent_id}")
        schedule(:heartbeat, state.heartbeat_ms)
        schedule(:poll_inbox, state.poll_ms)
        {:noreply, %{state | registered: true, mode: :http}}

      {:error, http_reason} ->
        # Fall back to file-based queue
        if state.queue_path != "" and File.dir?(state.queue_path) do
          inbox = Path.join(state.queue_path, state.agent_id)
          File.mkdir_p!(inbox)
          Logger.info("IAMQ: HTTP unavailable (#{inspect(http_reason)}), using file-based queue at #{state.queue_path}")
          schedule(:poll_inbox, state.poll_ms)
          {:noreply, %{state | registered: true, mode: :file}}
        else
          Logger.warning("IAMQ: registration failed — HTTP unreachable, no queue path configured. Retrying in 30s")
          schedule(:register, :timer.seconds(30))
          {:noreply, state}
        end
    end
  end

  def handle_info(:heartbeat, state) do
    case http_post(state.base_url, "/heartbeat", %{agent_id: state.agent_id}) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end

    schedule(:heartbeat, state.heartbeat_ms)
    {:noreply, state}
  end

  def handle_info(:poll_inbox, state) do
    try do
      case state.mode do
        :http -> poll_inbox_http(state)
        :file -> poll_inbox_file(state)
        _ -> :ok
      end
    rescue
      e -> Logger.error("IAMQ: inbox poll failed: #{Exception.message(e)}")
    end

    schedule(:poll_inbox, state.poll_ms)
    {:noreply, state}
  end

  # ── Message building ──

  defp build_message(to, subject, body, opts) do
    agent_id = Application.get_env(:librarian, :iamq_agent_id, "librarian_agent")

    %{
      id: uuid4(),
      from: agent_id,
      to: to,
      type: Keyword.get(opts, :type, "info"),
      priority: Keyword.get(opts, :priority, "NORMAL"),
      subject: subject,
      body: body,
      replyTo: Keyword.get(opts, :reply_to),
      createdAt: DateTime.utc_now() |> DateTime.to_iso8601(),
      expiresAt: Keyword.get(opts, :expires_at),
      status: "unread"
    }
  end

  # ── Dual-mode send ──

  defp do_send(state, msg) do
    case state.mode do
      :http ->
        case http_post(state.base_url, "/send", msg) do
          {:ok, _} = ok -> ok
          {:error, _} -> file_send(state, msg)
        end

      :file ->
        file_send(state, msg)

      nil ->
        {:error, :not_registered}
    end
  end

  defp file_send(state, msg) do
    if state.queue_path == "" do
      {:error, :no_queue_path}
    else
      target_dir = Path.join(state.queue_path, msg.to)
      File.mkdir_p!(target_dir)

      safe_ts = String.replace(msg.createdAt, ":", "-")
      agent_id = Application.get_env(:librarian, :iamq_agent_id, "librarian_agent")
      filename = "#{safe_ts}-#{agent_id}.json"
      path = Path.join(target_dir, filename)

      case File.write(path, Jason.encode!(msg, pretty: true)) do
        :ok ->
          Logger.info("IAMQ: sent message to #{msg.to} via file (#{filename})")
          {:ok, %{"status" => "sent"}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # ── HTTP inbox polling ──

  defp poll_inbox_http(state) do
    case http_get(state.base_url, "/inbox/#{state.agent_id}?status=unread") do
      {:ok, %{"messages" => messages}} when is_list(messages) and messages != [] ->
        Logger.info("IAMQ: #{length(messages)} unread message(s) via HTTP")

        Enum.each(messages, fn msg ->
          log_message(msg)
          http_patch(state.base_url, "/messages/#{msg["id"]}", %{status: "read"})
        end)

      {:ok, _} ->
        :ok

      {:error, _reason} ->
        # HTTP failed, try file fallback if available
        if state.queue_path != "" and File.dir?(state.queue_path) do
          poll_inbox_file(state)
        end
    end
  end

  # ── File-based inbox polling ──

  defp poll_inbox_file(state) do
    inbox_dir = Path.join(state.queue_path, state.agent_id)
    broadcast_dir = Path.join(state.queue_path, "broadcast")

    messages =
      read_messages_from_dir(inbox_dir) ++ read_messages_from_dir(broadcast_dir)

    unread = Enum.filter(messages, fn {_path, msg} -> msg["status"] == "unread" end)

    if unread != [] do
      Logger.info("IAMQ: #{length(unread)} unread message(s) via file queue")

      Enum.each(unread, fn {path, msg} ->
        log_message(msg)
        mark_file_read(path, msg)
      end)
    end
  end

  defp read_messages_from_dir(dir) do
    if File.dir?(dir) do
      dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.reject(&(&1 == ".gitkeep"))
      |> Enum.map(fn filename ->
        path = Path.join(dir, filename)

        case File.read(path) do
          {:ok, content} when content != "" ->
            case Jason.decode(content) do
              {:ok, msg} -> {path, msg}
              _ -> nil
            end

          _ ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp mark_file_read(path, msg) do
    updated = Map.put(msg, "status", "read")

    case File.write(path, Jason.encode!(updated, pretty: true)) do
      :ok -> :ok
      {:error, reason} -> Logger.warning("IAMQ: failed to mark file read: #{inspect(reason)}")
    end
  end

  # ── Shared message logging ──

  defp log_message(msg) do
    from = msg["from"] || "unknown"
    subject = msg["subject"] || "(no subject)"
    type = msg["type"] || "info"

    Logger.info("IAMQ: [#{type}] from #{from}: #{subject}")

    data_folders = Application.get_env(:librarian, :data_folders, [])

    log_dir =
      case data_folders do
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

  # ── File-based agent discovery ──

  defp list_agent_dirs(queue_path) do
    if File.dir?(queue_path) do
      queue_path
      |> File.ls!()
      |> Enum.filter(fn name ->
        Path.join(queue_path, name) |> File.dir?() and name != "broadcast"
      end)
      |> Enum.map(fn id -> %{"id" => id} end)
    else
      []
    end
  end

  # ── HTTP helpers ──

  defp http_post(base_url, path, payload) do
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

  defp http_get(base_url, path) do
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

  defp http_patch(base_url, path, payload) do
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

  defp parse_caps(s) do
    s |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  defp schedule(message, interval) do
    Process.send_after(self(), message, interval)
  end

  defp uuid4 do
    <<a::48, _::4, b::12, _::2, c::62>> = :crypto.strong_rand_bytes(16)
    hex = :io_lib.format("~12.16.0b~4.16.0b~16.16.0b", [a, b ||| 0x4000, c ||| 0x8000000000000000])
    s = IO.iodata_to_binary(hex)
    <<a1::binary-8, b1::binary-4, c1::binary-4, d1::binary-4, e1::binary-12>> = s
    "#{a1}-#{b1}-#{c1}-#{d1}-#{e1}"
  end
end
