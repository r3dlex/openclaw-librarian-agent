defmodule Librarian.Atlassian.Jira do
  @moduledoc """
  Jira and Jira Product Discovery (JPD) API client.

  JPD uses the standard Jira REST API — ideas are regular issue types
  within JPD projects. No separate endpoints are needed.

  ## Usage

      # Search for issues
      Jira.search("project = PROJ ORDER BY updated DESC", account: "work")

      # Get a single issue with all fields
      Jira.get_issue("PROJ-123", account: "work")

      # Get issue comments
      Jira.get_comments("PROJ-123", account: "work")

      # List projects (includes JPD projects)
      Jira.list_projects(account: "work")
  """
  alias Librarian.Atlassian.{Client, Cache}
  require Logger

  @doc """
  Search for issues using JQL.

  Returns a list of issue maps. Paginates automatically.

  Options:
  - `:account` — account label
  - `:fields` — list of fields to return (default: common fields)
  - `:max_results` — max total results (default: all)
  - `:cache_ttl` — cache TTL in seconds (default: 3600)
  """
  def search(jql, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    fields = opts[:fields] || ~w(summary status assignee reporter priority labels created updated issuetype project description)
    cache_ttl = opts[:cache_ttl] || 3600

    cache_key = "search:#{jql}:#{Enum.join(fields, ",")}"

    Cache.fetch(account_label, "jira", cache_key, fn ->
      params = %{
        "jql" => jql,
        "fields" => Enum.join(fields, ","),
        "maxResults" => 50
      }

      Client.get_all_pages("/rest/api/3/search",
        account: account_label,
        params: params,
        results_key: "issues"
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Get a single issue by key (e.g., "PROJ-123").

  Returns the full issue map including all fields.
  Works for both regular Jira issues and JPD ideas.
  """
  def get_issue(issue_key, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "jira", "issue:#{issue_key}", fn ->
      Client.get("/rest/api/3/issue/#{issue_key}",
        account: account_label,
        params: %{"expand" => "renderedFields"}
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Get comments for an issue.
  """
  def get_comments(issue_key, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "jira", "comments:#{issue_key}", fn ->
      Client.get("/rest/api/3/issue/#{issue_key}/comment",
        account: account_label,
        params: %{"maxResults" => 100, "orderBy" => "-created"}
      )
    end, ttl: cache_ttl)
  end

  @doc """
  List all accessible projects (includes JPD projects).
  """
  def list_projects(opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "jira", "projects", fn ->
      Client.get("/rest/api/3/project/search",
        account: account_label,
        params: %{"maxResults" => 100}
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Get issue changelogs (useful for tracking idea progression in JPD).
  """
  def get_changelog(issue_key, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "jira", "changelog:#{issue_key}", fn ->
      Client.get("/rest/api/3/issue/#{issue_key}/changelog",
        account: account_label,
        params: %{"maxResults" => 100}
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Convert a Jira issue to markdown for vault storage.

  Extracts key fields and formats them as a markdown document
  with YAML front matter.
  """
  def issue_to_markdown(issue) when is_map(issue) do
    fields = issue["fields"] || %{}
    rendered = issue["renderedFields"] || %{}

    key = issue["key"] || "UNKNOWN"
    summary = fields["summary"] || "Untitled"
    status = get_in(fields, ["status", "name"]) || "Unknown"
    issue_type = get_in(fields, ["issuetype", "name"]) || "Unknown"
    project_name = get_in(fields, ["project", "name"]) || "Unknown"
    project_key = get_in(fields, ["project", "key"]) || ""
    assignee = get_in(fields, ["assignee", "displayName"]) || "Unassigned"
    reporter = get_in(fields, ["reporter", "displayName"]) || "Unknown"
    priority = get_in(fields, ["priority", "name"]) || "None"
    labels = fields["labels"] || []
    created = fields["created"] || ""
    updated = fields["updated"] || ""

    # Use rendered description (HTML) if available, fall back to plain
    description =
      case rendered["description"] do
        desc when is_binary(desc) and desc != "" ->
          html_to_markdown(desc)

        _ ->
          extract_adf_text(fields["description"])
      end

    front_matter = """
    ---
    title: "#{escape_yaml(summary)}"
    source: jira
    jira_key: #{key}
    project: #{project_key}
    issue_type: #{issue_type}
    status: #{status}
    assignee: #{assignee}
    reporter: #{reporter}
    priority: #{priority}
    labels: #{Jason.encode!(labels)}
    created: #{created}
    updated: #{updated}
    pulled_at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    ---
    """

    body = """
    # #{key}: #{summary}

    | Field | Value |
    |-------|-------|
    | **Project** | #{project_name} (#{project_key}) |
    | **Type** | #{issue_type} |
    | **Status** | #{status} |
    | **Priority** | #{priority} |
    | **Assignee** | #{assignee} |
    | **Reporter** | #{reporter} |
    | **Labels** | #{Enum.join(labels, ", ")} |
    | **Created** | #{created} |
    | **Updated** | #{updated} |

    ## Description

    #{description || "_No description_"}
    """

    {:ok, String.trim(front_matter) <> "\n\n" <> String.trim(body) <> "\n"}
  end

  # --- Private ---

  defp default_account_label do
    case Client.list_accounts() do
      [first | _] -> first.label
      [] -> nil
    end
  end

  defp html_to_markdown(html) do
    case System.cmd("pandoc", ["-f", "html", "-t", "markdown", "--wrap=none"],
           input: html,
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.trim(output)
      _ -> html
    end
  end

  defp extract_adf_text(nil), do: nil

  defp extract_adf_text(%{"content" => content}) when is_list(content) do
    content
    |> Enum.map(&extract_adf_node/1)
    |> Enum.join("\n\n")
  end

  defp extract_adf_text(_), do: nil

  defp extract_adf_node(%{"type" => "text", "text" => text}), do: text

  defp extract_adf_node(%{"content" => content}) when is_list(content) do
    Enum.map_join(content, "", &extract_adf_node/1)
  end

  defp extract_adf_node(_), do: ""

  defp escape_yaml(str) when is_binary(str) do
    str
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
  end

  defp escape_yaml(_), do: ""
end
