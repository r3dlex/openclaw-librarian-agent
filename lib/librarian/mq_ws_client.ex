defmodule Librarian.MqWsClient do
  @moduledoc """
  WebSocket client for the OpenClaw Inter-Agent Message Queue (IAMQ).

  Connects to `ws://127.0.0.1:18793/ws` for real-time message push.
  On connect, registers with IAMQ and starts a periodic heartbeat.
  Incoming messages are processed immediately without polling delay.

  Configuration via environment variables:
  - IAMQ_WS_URL: WebSocket URL (default: ws://127.0.0.1:18793/ws)
  - IAMQ_AGENT_ID: This agent's ID (default: librarian_agent)
  """
  use WebSockex
  require Logger

  @default_ws_url "ws://127.0.0.1:18793/ws"
  @default_agent_id "librarian_agent"
  @heartbeat_interval 30_000
  @reconnect_interval 15_000

  # --- Public API ---

  def start_link(_opts) do
    ws_url = System.get_env("IAMQ_WS_URL", @default_ws_url)

    state = %{
      agent_id: System.get_env("IAMQ_AGENT_ID", @default_agent_id),
      ws_url: ws_url,
      registered: false
    }

    WebSockex.start_link(ws_url, __MODULE__, state,
      name: __MODULE__,
      handle_initial_conn_failure: true
    )
  end

  @doc "Send a message to another agent via WebSocket."
  def send_message(to, subject, body, opts \\ []) do
    agent_id = System.get_env("IAMQ_AGENT_ID", @default_agent_id)

    payload =
      Jason.encode!(%{
        action: "send",
        from: agent_id,
        to: to,
        type: Keyword.get(opts, :type, "info"),
        priority: Keyword.get(opts, :priority, "NORMAL"),
        subject: subject,
        body: body,
        replyTo: Keyword.get(opts, :reply_to),
        expiresAt: Keyword.get(opts, :expires_at)
      })

    WebSockex.send_frame(__MODULE__, {:text, payload})
  end

  # --- WebSockex Callbacks ---

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("[MQ-WS] Connected to #{state.ws_url}")
    send(self(), :do_register)
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, raw}, state) do
    case Jason.decode(raw) do
      {:ok, %{"event" => "registered", "agent_id" => id}} ->
        Logger.info("[MQ-WS] Registered as #{id}")
        {:ok, %{state | registered: true}}

      {:ok, %{"event" => "heartbeat_ack"}} ->
        Logger.debug("[MQ-WS] Heartbeat acknowledged")
        {:ok, state}

      {:ok, %{"event" => "sent", "id" => msg_id}} ->
        Logger.debug("[MQ-WS] Message sent: #{msg_id}")
        {:ok, state}

      {:ok, %{"event" => "new_message", "message" => message}} ->
        handle_incoming_message(message, state)
        {:ok, state}

      {:ok, %{"event" => "error", "reason" => reason}} ->
        Logger.warning("[MQ-WS] Server error: #{reason}")
        {:ok, state}

      {:ok, other} ->
        Logger.debug("[MQ-WS] Unknown frame: #{inspect(other)}")
        {:ok, state}

      {:error, _} ->
        Logger.warning("[MQ-WS] Invalid JSON frame: #{String.slice(raw, 0, 100)}")
        {:ok, state}
    end
  end

  @impl true
  def handle_frame(_other, state) do
    {:ok, state}
  end

  @impl true
  def handle_info(:do_register, state) do
    frame = Jason.encode!(%{action: "register", agent_id: state.agent_id})
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
    {:reply, {:text, frame}, state}
  end

  @impl true
  def handle_info(:send_heartbeat, state) do
    frame = Jason.encode!(%{action: "heartbeat"})
    Process.send_after(self(), :send_heartbeat, @heartbeat_interval)
    {:reply, {:text, frame}, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:ok, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("[MQ-WS] Disconnected: #{inspect(reason)}. Reconnecting in #{@reconnect_interval}ms...")
    Process.sleep(@reconnect_interval)
    {:reconnect, %{state | registered: false}}
  end

  # --- Internal ---

  defp handle_incoming_message(message, _state) do
    from = message["from"] || "unknown"
    subject = message["subject"] || "(no subject)"
    msg_type = message["type"] || "info"
    msg_id = message["id"]

    Logger.info("[MQ-WS] Received #{msg_type} from #{from}: #{subject}")

    if msg_id do
      ack_frame = Jason.encode!(%{action: "ack", id: msg_id})

      try do
        WebSockex.send_frame(__MODULE__, {:text, ack_frame})
      rescue
        _ -> :ok
      end
    end

    case msg_type do
      "request" ->
        route_request(message)

      "info" ->
        Logger.info("[MQ-WS] Info from #{from}: #{String.slice(message["body"] || "", 0, 200)}")

      "response" ->
        Logger.info("[MQ-WS] Response from #{from}: #{String.slice(message["body"] || "", 0, 200)}")

      "error" ->
        Logger.error("[MQ-WS] Error from #{from}: #{String.slice(message["body"] || "", 0, 200)}")

      _ ->
        Logger.debug("[MQ-WS] Unknown message type: #{msg_type}")
    end
  end

  defp route_request(message) do
    subject = message["subject"] || ""
    from = message["from"] || "unknown"

    cond do
      String.contains?(subject, "search") or String.contains?(subject, "find") ->
        Logger.info("[MQ-WS] Search request from #{from}")

      String.contains?(subject, "archive") or String.contains?(subject, "file") ->
        Logger.info("[MQ-WS] Archive request from #{from}")

      String.contains?(subject, "summarize") or String.contains?(subject, "summary") ->
        Logger.info("[MQ-WS] Summarize request from #{from}")

      String.contains?(subject, "status") ->
        Logger.info("[MQ-WS] Status request from #{from}")

      true ->
        Logger.info("[MQ-WS] Unhandled request from #{from}: #{subject}")
    end
  end
end
