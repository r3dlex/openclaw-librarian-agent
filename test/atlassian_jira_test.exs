defmodule Librarian.Atlassian.JiraTest do
  use ExUnit.Case, async: false

  alias Librarian.Atlassian.{Jira, Cache}

  setup do
    tmp = Path.join(System.tmp_dir!(), "jira_test_#{:rand.uniform(999_999_999)}")
    File.mkdir_p!(tmp)

    prev_accounts = Application.get_env(:librarian, :atlassian_accounts, [])
    prev_data_folder = Application.get_env(:librarian, :data_folder, "")

    Application.put_env(:librarian, :data_folder, tmp)
    Application.put_env(:librarian, :atlassian_accounts, [])

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:librarian, :atlassian_accounts, prev_accounts)
      Application.put_env(:librarian, :data_folder, prev_data_folder)
    end)

    %{tmp: tmp}
  end

  describe "issue_to_markdown/1" do
    test "converts a basic issue to markdown with front matter" do
      issue = %{
        "key" => "PROJ-123",
        "fields" => %{
          "summary" => "Fix the login bug",
          "status" => %{"name" => "In Progress"},
          "issuetype" => %{"name" => "Bug"},
          "project" => %{"name" => "My Project", "key" => "PROJ"},
          "assignee" => %{"displayName" => "Alice Smith"},
          "reporter" => %{"displayName" => "Bob Jones"},
          "priority" => %{"name" => "High"},
          "labels" => ["backend", "auth"],
          "created" => "2026-01-01T10:00:00Z",
          "updated" => "2026-01-15T12:30:00Z",
          "description" => nil
        },
        "renderedFields" => %{}
      }

      assert {:ok, markdown} = Jira.issue_to_markdown(issue)

      assert String.contains?(markdown, "PROJ-123")
      assert String.contains?(markdown, "Fix the login bug")
      assert String.contains?(markdown, "In Progress")
      assert String.contains?(markdown, "Bug")
      assert String.contains?(markdown, "Alice Smith")
      assert String.contains?(markdown, "Bob Jones")
      assert String.contains?(markdown, "High")
      assert String.contains?(markdown, "backend")
      assert String.contains?(markdown, "auth")
      assert String.contains?(markdown, "source: jira")
      assert String.contains?(markdown, "jira_key: PROJ-123")
    end

    test "handles issue with empty fields gracefully" do
      issue = %{
        "key" => "UNKNOWN-0",
        "fields" => %{},
        "renderedFields" => %{}
      }

      assert {:ok, markdown} = Jira.issue_to_markdown(issue)
      assert String.contains?(markdown, "UNKNOWN-0")
      # Defaults
      assert String.contains?(markdown, "Untitled")
      assert String.contains?(markdown, "Unassigned")
    end

    test "handles nil fields map" do
      issue = %{
        "key" => "PROJ-1",
        "fields" => nil,
        "renderedFields" => nil
      }

      assert {:ok, markdown} = Jira.issue_to_markdown(issue)
      assert String.contains?(markdown, "PROJ-1")
    end

    test "escapes YAML special characters in summary" do
      issue = %{
        "key" => "PROJ-456",
        "fields" => %{
          "summary" => ~s(Title with "quotes" and\nnewlines),
          "labels" => []
        },
        "renderedFields" => %{}
      }

      assert {:ok, markdown} = Jira.issue_to_markdown(issue)
      # Should not blow up with bad YAML
      assert String.contains?(markdown, "PROJ-456")
    end

    test "uses ADF text extraction when rendered description is absent" do
      issue = %{
        "key" => "PROJ-789",
        "fields" => %{
          "summary" => "ADF test",
          "labels" => [],
          "description" => %{
            "content" => [
              %{
                "type" => "paragraph",
                "content" => [
                  %{"type" => "text", "text" => "This is ADF text"}
                ]
              }
            ]
          }
        },
        "renderedFields" => %{}
      }

      assert {:ok, markdown} = Jira.issue_to_markdown(issue)
      assert String.contains?(markdown, "ADF test")
    end

    test "includes empty labels list gracefully" do
      issue = %{
        "key" => "PROJ-10",
        "fields" => %{
          "summary" => "No labels",
          "labels" => []
        },
        "renderedFields" => %{}
      }

      assert {:ok, markdown} = Jira.issue_to_markdown(issue)
      assert String.contains?(markdown, "PROJ-10")
    end

    test "front matter contains pulled_at timestamp" do
      issue = %{
        "key" => "TS-1",
        "fields" => %{"summary" => "Timestamp test", "labels" => []},
        "renderedFields" => %{}
      }

      assert {:ok, markdown} = Jira.issue_to_markdown(issue)
      assert String.contains?(markdown, "pulled_at:")
    end
  end


  describe "API methods - with cached response" do
    setup do
      account = %{label: "jira_cached", url: "https://fake.atlassian.net", email: "a@b.com", token: "t"}
      Application.put_env(:librarian, :atlassian_accounts, [account])
      :ok
    end

    test "get_issue/2 returns cached result without HTTP call" do
      data = %{"key" => "PROJ-1", "fields" => %{"summary" => "Cached issue"}}
      Cache.write("jira_cached", "jira", "issue:PROJ-1", data)

      assert {:ok, ^data} = Jira.get_issue("PROJ-1", account: "jira_cached")
    end

    test "get_comments/2 returns cached result without HTTP call" do
      data = [%{"id" => "c1", "body" => "Nice"}]
      Cache.write("jira_cached", "jira", "comments:PROJ-1", data)

      assert {:ok, ^data} = Jira.get_comments("PROJ-1", account: "jira_cached")
    end

    test "list_projects/1 returns cached result without HTTP call" do
      data = [%{"key" => "PROJ", "name" => "My Project"}]
      Cache.write("jira_cached", "jira", "projects", data)

      assert {:ok, ^data} = Jira.list_projects(account: "jira_cached")
    end

    test "get_changelog/2 returns cached result without HTTP call" do
      data = [%{"id" => "cl1", "items" => []}]
      Cache.write("jira_cached", "jira", "changelog:PROJ-5", data)

      assert {:ok, ^data} = Jira.get_changelog("PROJ-5", account: "jira_cached")
    end

    test "search/2 returns cached result without HTTP call" do
      fields = ~w(summary status assignee reporter priority labels created updated issuetype project description)
      cache_key = "search:project = PROJ ORDER BY updated DESC:#{Enum.join(fields, ",")}"
      data = [%{"key" => "PROJ-1", "fields" => %{"summary" => "Cached result"}}]
      Cache.write("jira_cached", "jira", cache_key, data)

      assert {:ok, ^data} =
               Jira.search("project = PROJ ORDER BY updated DESC", account: "jira_cached")
    end

    test "search/2 with custom fields returns cached result" do
      custom_fields = ["summary", "status"]
      cache_key = "search:project = X:#{Enum.join(custom_fields, ",")}"
      data = [%{"key" => "X-1"}]
      Cache.write("jira_cached", "jira", cache_key, data)

      assert {:ok, ^data} =
               Jira.search("project = X",
                 account: "jira_cached",
                 fields: custom_fields
               )
    end
  end
end
