defmodule Librarian.IAMQTest do
  use ExUnit.Case, async: true

  @agent_id "librarian_agent"

  setup do
    bypass = Bypass.open()
    base_url = "http://localhost:#{bypass.port}"
    {:ok, bypass: bypass, base_url: base_url}
  end

  defp start_iamq(base_url, opts \\ []) do
    name = Keyword.get(opts, :name, :"iamq_#{System.unique_integer([:positive])}")
    auto_register = Keyword.get(opts, :auto_register, false)

    start_supervised!(
      {Librarian.IAMQ, [base_url: base_url, name: name, auto_register: auto_register]}
    )

    name
  end

  describe "registration" do
    test "registers with the IAMQ service on startup", %{bypass: bypass, base_url: base_url} do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/register", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        send(test_pid, {:registration, payload})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      # Allow heartbeat and poll to hit bypass without failing the test
      Bypass.stub(bypass, "POST", "/heartbeat", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      Bypass.stub(bypass, "GET", "/inbox/#{@agent_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{messages: []}))
      end)

      start_iamq(base_url, auto_register: true)

      assert_receive {:registration, payload}, 2_000
      assert payload["agent_id"] == @agent_id
      assert payload["name"] == "Librarian"
      assert is_list(payload["capabilities"])
      assert "search" in payload["capabilities"]
    end

    test "retries registration on failure", %{bypass: bypass, base_url: base_url} do
      # Return 500 on first attempt
      Bypass.expect(bypass, "POST", "/register", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(500, Jason.encode!(%{error: "unavailable"}))
      end)

      name = start_iamq(base_url, auto_register: false)

      # Trigger registration manually and check it handles error gracefully
      send(GenServer.whereis(name), :register)

      # Give it time to process — GenServer should survive the failure
      Process.sleep(100)
      assert Process.alive?(GenServer.whereis(name))
    end
  end

  describe "send_message/4" do
    test "sends a message to another agent", %{bypass: bypass, base_url: base_url} do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/send", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:sent, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "msg-123"}))
      end)

      name = start_iamq(base_url)

      result = GenServer.call(name, {:send, "mail_agent", "Test subject", "Test body", []})
      assert {:ok, %{"id" => "msg-123"}} = result

      assert_receive {:sent, payload}
      assert payload["from"] == @agent_id
      assert payload["to"] == "mail_agent"
      assert payload["subject"] == "Test subject"
      assert payload["body"] == "Test body"
      assert payload["type"] == "info"
      assert payload["priority"] == "NORMAL"
    end

    test "sends with custom type and reply_to", %{bypass: bypass, base_url: base_url} do
      test_pid = self()

      Bypass.expect_once(bypass, "POST", "/send", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:sent, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{id: "msg-456"}))
      end)

      name = start_iamq(base_url)

      GenServer.call(name, {:send, "journalist_agent", "Re: Research", "Results here",
        [type: "response", reply_to: "orig-789"]})

      assert_receive {:sent, payload}
      assert payload["type"] == "response"
      assert payload["replyTo"] == "orig-789"
    end

    test "returns error on HTTP failure", %{bypass: bypass, base_url: base_url} do
      Bypass.expect_once(bypass, "POST", "/send", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(503, Jason.encode!(%{error: "service unavailable"}))
      end)

      name = start_iamq(base_url)

      result = GenServer.call(name, {:send, "mail_agent", "Test", "Body", []})
      assert {:error, {:http, 503, _}} = result
    end
  end

  describe "list_agents/0" do
    test "returns list of online agents", %{bypass: bypass, base_url: base_url} do
      agents = [
        %{"agent_id" => "mail_agent", "name" => "Mail Agent", "status" => "online"},
        %{"agent_id" => "librarian_agent", "name" => "Librarian", "status" => "online"}
      ]

      Bypass.expect_once(bypass, "GET", "/agents", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{agents: agents}))
      end)

      name = start_iamq(base_url)

      assert {:ok, ^agents} = GenServer.call(name, :list_agents)
    end

    test "returns error when service is down", %{bypass: bypass, base_url: base_url} do
      Bypass.down(bypass)

      name = start_iamq(base_url)

      assert {:error, _} = GenServer.call(name, :list_agents)
    end
  end

  describe "heartbeat" do
    test "sends heartbeat with agent_id", %{bypass: bypass, base_url: base_url} do
      test_pid = self()

      Bypass.expect(bypass, "POST", "/heartbeat", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:heartbeat, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      name = start_iamq(base_url)

      # Trigger heartbeat manually
      send(GenServer.whereis(name), :heartbeat)

      assert_receive {:heartbeat, payload}, 2_000
      assert payload["agent_id"] == @agent_id
    end
  end

  describe "inbox polling" do
    test "processes unread messages and marks them as read", %{bypass: bypass, base_url: base_url} do
      test_pid = self()

      messages = [
        %{
          "id" => "msg-001",
          "from" => "mail_agent",
          "subject" => "New document",
          "type" => "info",
          "body" => "A new document arrived"
        }
      ]

      Bypass.expect_once(bypass, "GET", "/inbox/#{@agent_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{messages: messages}))
      end)

      Bypass.expect_once(bypass, "PATCH", "/messages/msg-001", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:marked_read, Jason.decode!(body)})

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      name = start_iamq(base_url)

      # Trigger inbox poll manually
      send(GenServer.whereis(name), :poll_inbox)

      assert_receive {:marked_read, %{"status" => "read"}}, 2_000
    end

    test "writes messages to log directory", %{bypass: bypass, base_url: base_url} do
      log_dir = Path.join(System.tmp_dir!(), "iamq_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(log_dir)

      on_exit(fn -> File.rm_rf!(log_dir) end)

      # Configure data_folders to use our temp dir
      parent = Path.dirname(log_dir)
      Application.put_env(:librarian, :data_folders, [parent])

      messages = [
        %{
          "id" => "msg-log-001",
          "from" => "journalist_agent",
          "subject" => "Research request",
          "type" => "request",
          "body" => "Need info on topic X"
        }
      ]

      Bypass.expect_once(bypass, "GET", "/inbox/#{@agent_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{messages: messages}))
      end)

      Bypass.stub(bypass, "PATCH", "/messages/msg-log-001", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{status: "ok"}))
      end)

      name = start_iamq(base_url)
      send(GenServer.whereis(name), :poll_inbox)

      # Wait for processing
      Process.sleep(200)

      # Check that a log file was written
      log_files = Path.join(parent, "log") |> File.ls!()
      iamq_logs = Enum.filter(log_files, &String.starts_with?(&1, "iamq-"))
      assert length(iamq_logs) >= 1

      # Verify log content
      log_content =
        Path.join([parent, "log", hd(iamq_logs)])
        |> File.read!()
        |> Jason.decode!()

      assert log_content["from"] == "journalist_agent"
      assert log_content["subject"] == "Research request"

      # Cleanup
      Application.put_env(:librarian, :data_folders, [System.tmp_dir!()])
    end

    test "handles empty inbox gracefully", %{bypass: bypass, base_url: base_url} do
      Bypass.expect_once(bypass, "GET", "/inbox/#{@agent_id}", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{messages: []}))
      end)

      name = start_iamq(base_url)
      send(GenServer.whereis(name), :poll_inbox)

      # Should not crash
      Process.sleep(100)
      assert Process.alive?(GenServer.whereis(name))
    end

    test "survives inbox poll failure", %{bypass: bypass, base_url: base_url} do
      Bypass.down(bypass)

      name = start_iamq(base_url)
      send(GenServer.whereis(name), :poll_inbox)

      Process.sleep(100)
      assert Process.alive?(GenServer.whereis(name))
    end
  end
end
