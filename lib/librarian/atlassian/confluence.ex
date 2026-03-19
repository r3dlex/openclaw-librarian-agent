defmodule Librarian.Atlassian.Confluence do
  @moduledoc """
  Confluence API client for fetching pages, spaces, and content.

  Converts Confluence XHTML content to markdown via Pandoc,
  consistent with the existing `Librarian.Processor` approach.

  ## Usage

      # Get a page by ID
      Confluence.get_page("123456", account: "work")

      # Search for pages
      Confluence.search("type = page AND space = DEV AND title ~ 'architecture'", account: "work")

      # List spaces
      Confluence.list_spaces(account: "work")

      # Get page as markdown
      Confluence.page_to_markdown(page_data)
  """
  alias Librarian.Atlassian.{Client, Cache}
  require Logger

  @doc """
  Get a Confluence page by ID.

  Returns the page with body content in storage format (XHTML).
  """
  def get_page(page_id, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "confluence", "page:#{page_id}", fn ->
      Client.get("/wiki/api/v2/pages/#{page_id}",
        account: account_label,
        params: %{"body-format" => "storage"}
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Get child pages of a given page.
  """
  def get_children(page_id, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "confluence", "children:#{page_id}", fn ->
      Client.get("/wiki/api/v2/pages/#{page_id}/children",
        account: account_label,
        params: %{"limit" => 50}
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Search Confluence content using CQL (Confluence Query Language).

  Returns a list of content results.
  """
  def search(cql, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600
    limit = opts[:limit] || 25

    Cache.fetch(account_label, "confluence", "search:#{cql}", fn ->
      Client.get("/wiki/rest/api/content/search",
        account: account_label,
        params: %{
          "cql" => cql,
          "limit" => limit,
          "expand" => "body.storage,space,version,ancestors"
        }
      )
    end, ttl: cache_ttl)
  end

  @doc """
  List all accessible Confluence spaces.
  """
  def list_spaces(opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "confluence", "spaces", fn ->
      Client.get("/wiki/api/v2/spaces",
        account: account_label,
        params: %{"limit" => 100}
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Get all pages in a space.
  """
  def get_space_pages(space_key, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "confluence", "space_pages:#{space_key}", fn ->
      Client.get("/wiki/rest/api/content",
        account: account_label,
        params: %{
          "spaceKey" => space_key,
          "type" => "page",
          "limit" => 100,
          "expand" => "space,version"
        }
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Get page comments.
  """
  def get_comments(page_id, opts \\ []) do
    account_label = opts[:account] || default_account_label()
    cache_ttl = opts[:cache_ttl] || 3600

    Cache.fetch(account_label, "confluence", "comments:#{page_id}", fn ->
      Client.get("/wiki/rest/api/content/#{page_id}/child/comment",
        account: account_label,
        params: %{
          "limit" => 100,
          "expand" => "body.storage"
        }
      )
    end, ttl: cache_ttl)
  end

  @doc """
  Convert a Confluence page response to markdown for vault storage.

  Converts XHTML body to markdown via Pandoc and adds YAML front matter.
  """
  def page_to_markdown(page) when is_map(page) do
    title = page["title"] || "Untitled"
    page_id = page["id"] || ""

    space_key =
      get_in(page, ["space", "key"]) ||
        get_in(page, ["spaceId"]) ||
        ""

    space_name = get_in(page, ["space", "name"]) || space_key

    version = get_in(page, ["version", "number"]) || 1
    created = get_in(page, ["version", "createdAt"]) || ""

    # Extract XHTML body content
    body_xhtml =
      get_in(page, ["body", "storage", "value"]) ||
        ""

    # Convert XHTML → markdown via Pandoc
    body_md = xhtml_to_markdown(body_xhtml)

    # Build ancestors breadcrumb if available
    ancestors =
      case page["ancestors"] do
        list when is_list(list) ->
          list |> Enum.map(& &1["title"]) |> Enum.join(" > ")

        _ ->
          ""
      end

    front_matter = """
    ---
    title: "#{escape_yaml(title)}"
    source: confluence
    confluence_id: #{page_id}
    space: #{space_key}
    space_name: "#{escape_yaml(space_name)}"
    version: #{version}
    created: #{created}
    ancestors: "#{escape_yaml(ancestors)}"
    pulled_at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    ---
    """

    body = """
    # #{title}

    > **Space**: #{space_name} (#{space_key}) | **Version**: #{version}#{if ancestors != "", do: " | **Path**: #{ancestors}", else: ""}

    #{body_md}
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

  defp xhtml_to_markdown(""), do: "_Empty page_"

  defp xhtml_to_markdown(xhtml) do
    case System.cmd("pandoc", ["-f", "html", "-t", "markdown", "--wrap=none"],
           input: xhtml,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        String.trim(output)

      {error, _} ->
        Logger.warning("Pandoc conversion of Confluence XHTML failed: #{error}")
        # Fallback: strip HTML tags
        xhtml
        |> String.replace(~r/<[^>]+>/, "")
        |> String.trim()
    end
  end

  defp escape_yaml(str) when is_binary(str) do
    str
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", " ")
  end

  defp escape_yaml(_), do: ""
end
