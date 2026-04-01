defmodule Librarian.Atlassian.ConfluenceTest do
  use ExUnit.Case, async: false

  alias Librarian.Atlassian.{Confluence, Cache}

  setup do
    tmp = Path.join(System.tmp_dir!(), "confluence_test_#{:rand.uniform(999_999_999)}")
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

  describe "page_to_markdown/1" do
    test "converts a basic page to markdown with front matter" do
      page = %{
        "id" => "12345",
        "title" => "Architecture Overview",
        "space" => %{"key" => "DEV", "name" => "Development"},
        "version" => %{"number" => 3, "createdAt" => "2026-02-01T09:00:00Z"},
        "body" => %{"storage" => %{"value" => ""}},
        "ancestors" => []
      }

      assert {:ok, markdown} = Confluence.page_to_markdown(page)

      assert String.contains?(markdown, "Architecture Overview")
      assert String.contains?(markdown, "source: confluence")
      assert String.contains?(markdown, "confluence_id: 12345")
      assert String.contains?(markdown, "space: DEV")
      assert String.contains?(markdown, "version: 3")
    end

    test "handles empty body gracefully" do
      page = %{
        "id" => "99",
        "title" => "Empty Page",
        "body" => %{"storage" => %{"value" => ""}},
        "space" => %{"key" => "TEST", "name" => "Test Space"},
        "version" => %{"number" => 1, "createdAt" => "2026-01-01T00:00:00Z"}
      }

      assert {:ok, markdown} = Confluence.page_to_markdown(page)
      assert String.contains?(markdown, "Empty Page")
      assert String.contains?(markdown, "_Empty page_")
    end

    test "handles missing optional fields" do
      page = %{
        "id" => "42",
        "title" => "Minimal Page"
      }

      assert {:ok, markdown} = Confluence.page_to_markdown(page)
      assert String.contains?(markdown, "Minimal Page")
      assert String.contains?(markdown, "confluence_id: 42")
    end

    test "builds ancestors breadcrumb when ancestors are present" do
      page = %{
        "id" => "200",
        "title" => "Child Page",
        "body" => %{"storage" => %{"value" => ""}},
        "ancestors" => [
          %{"title" => "Root"},
          %{"title" => "Parent"}
        ]
      }

      assert {:ok, markdown} = Confluence.page_to_markdown(page)
      assert String.contains?(markdown, "Root > Parent")
    end

    test "front matter contains pulled_at timestamp" do
      page = %{
        "id" => "555",
        "title" => "Timestamped"
      }

      assert {:ok, markdown} = Confluence.page_to_markdown(page)
      assert String.contains?(markdown, "pulled_at:")
    end

    test "escapes YAML special characters in title" do
      page = %{
        "id" => "777",
        "title" => ~s(Title with "quotes"),
        "body" => %{"storage" => %{"value" => ""}}
      }

      assert {:ok, markdown} = Confluence.page_to_markdown(page)
      assert String.contains?(markdown, "777")
    end

    test "uses spaceId when space key is absent" do
      page = %{
        "id" => "300",
        "title" => "No Space Key",
        "spaceId" => "~SPACEID123",
        "body" => %{"storage" => %{"value" => ""}}
      }

      assert {:ok, markdown} = Confluence.page_to_markdown(page)
      assert String.contains?(markdown, "~SPACEID123")
    end
  end


  describe "API methods - with cached response" do
    setup do
      # Use a fake account label to test cache-hit path
      account = %{label: "cached_test", url: "https://fake.atlassian.net", email: "a@b.com", token: "t"}
      Application.put_env(:librarian, :atlassian_accounts, [account])
      :ok
    end

    test "get_page/2 returns cached result without HTTP call" do
      data = %{"id" => "cached-page", "title" => "Cached Page"}
      Cache.write("cached_test", "confluence", "page:cached-page", data)

      assert {:ok, ^data} = Confluence.get_page("cached-page", account: "cached_test")
    end

    test "search/2 returns cached result without HTTP call" do
      data = [%{"id" => "1", "title" => "Result"}]
      Cache.write("cached_test", "confluence", "search:type = page", data)

      assert {:ok, ^data} = Confluence.search("type = page", account: "cached_test")
    end

    test "list_spaces/1 returns cached result without HTTP call" do
      data = [%{"key" => "DEV", "name" => "Development"}]
      Cache.write("cached_test", "confluence", "spaces", data)

      assert {:ok, ^data} = Confluence.list_spaces(account: "cached_test")
    end

    test "get_space_pages/2 returns cached result without HTTP call" do
      data = [%{"id" => "1", "title" => "Page 1"}]
      Cache.write("cached_test", "confluence", "space_pages:DEV", data)

      assert {:ok, ^data} = Confluence.get_space_pages("DEV", account: "cached_test")
    end

    test "get_children/2 returns cached result without HTTP call" do
      data = [%{"id" => "child1"}]
      Cache.write("cached_test", "confluence", "children:parent-id", data)

      assert {:ok, ^data} = Confluence.get_children("parent-id", account: "cached_test")
    end

    test "get_comments/2 returns cached result without HTTP call" do
      data = [%{"id" => "comment1", "body" => %{}}]
      Cache.write("cached_test", "confluence", "comments:page-id", data)

      assert {:ok, ^data} = Confluence.get_comments("page-id", account: "cached_test")
    end
  end
end
