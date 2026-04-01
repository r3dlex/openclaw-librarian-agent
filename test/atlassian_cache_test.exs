defmodule Librarian.Atlassian.CacheTest do
  use ExUnit.Case, async: false

  alias Librarian.Atlassian.Cache

  setup do
    tmp = Path.join(System.tmp_dir!(), "cache_test_#{:rand.uniform(999_999_999)}")
    File.mkdir_p!(tmp)
    Application.put_env(:librarian, :data_folder, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.delete_env(:librarian, :data_folder)
    end)

    %{tmp: tmp}
  end

  describe "write/4 and read/4" do
    test "write then read returns the cached value" do
      data = %{"key" => "value", "count" => 42}
      Cache.write("work", "jira", "issue:PROJ-1", data)

      assert {:ok, ^data} = Cache.read("work", "jira", "issue:PROJ-1", 3600)
    end

    test "read returns :miss for non-existent key" do
      assert :miss = Cache.read("work", "jira", "nonexistent:key", 3600)
    end

    test "read returns :miss for expired entry" do
      data = %{"title" => "old data"}
      Cache.write("work", "jira", "expired:key", data)

      # TTL of 0 means immediately expired
      assert :miss = Cache.read("work", "jira", "expired:key", 0)
    end

    test "read returns :ok for fresh entry within TTL" do
      data = %{"fresh" => true}
      Cache.write("work", "confluence", "fresh:key", data)

      assert {:ok, ^data} = Cache.read("work", "confluence", "fresh:key", 3600)
    end

    test "write handles lists as data" do
      data = [%{"id" => 1}, %{"id" => 2}]
      Cache.write("work", "jira", "projects:list", data)

      assert {:ok, ^data} = Cache.read("work", "jira", "projects:list", 3600)
    end

    test "separate cache namespaces don't collide" do
      Cache.write("work", "jira", "item:1", %{"source" => "jira"})
      Cache.write("work", "confluence", "item:1", %{"source" => "confluence"})

      assert {:ok, %{"source" => "jira"}} = Cache.read("work", "jira", "item:1", 3600)
      assert {:ok, %{"source" => "confluence"}} = Cache.read("work", "confluence", "item:1", 3600)
    end

    test "different account labels don't collide" do
      Cache.write("work", "jira", "key:1", %{"account" => "work"})
      Cache.write("personal", "jira", "key:1", %{"account" => "personal"})

      assert {:ok, %{"account" => "work"}} = Cache.read("work", "jira", "key:1", 3600)
      assert {:ok, %{"account" => "personal"}} = Cache.read("personal", "jira", "key:1", 3600)
    end
  end

  describe "fetch/5" do
    test "calls function and caches on cache miss" do
      counter = :counters.new(1, [])

      result =
        Cache.fetch("work", "jira", "fetch:new:key", fn ->
          :counters.add(counter, 1, 1)
          {:ok, %{"data" => "fetched"}}
        end)

      assert {:ok, %{"data" => "fetched"}} = result
      assert :counters.get(counter, 1) == 1
    end

    test "returns cached value without calling function on hit" do
      Cache.write("work", "jira", "fetch:cached:key", %{"cached" => true})

      counter = :counters.new(1, [])

      result =
        Cache.fetch("work", "jira", "fetch:cached:key", fn ->
          :counters.add(counter, 1, 1)
          {:ok, %{"cached" => false}}
        end)

      assert {:ok, %{"cached" => true}} = result
      # Function should NOT have been called
      assert :counters.get(counter, 1) == 0
    end

    test "propagates error from function without caching" do
      result =
        Cache.fetch("work", "jira", "fetch:error:key", fn ->
          {:error, :connection_failed}
        end)

      assert {:error, :connection_failed} = result
      # Should not be cached
      assert :miss = Cache.read("work", "jira", "fetch:error:key", 3600)
    end

    test "respects custom TTL option" do
      Cache.fetch("work", "jira", "fetch:ttl:key", fn ->
        {:ok, %{"ttl" => "custom"}}
      end, ttl: 7200)

      # With a short TTL check it would be a miss
      assert :miss = Cache.read("work", "jira", "fetch:ttl:key", 0)
      # With the normal TTL it should be fresh
      assert {:ok, _} = Cache.read("work", "jira", "fetch:ttl:key", 7200)
    end
  end

  describe "invalidate/3" do
    test "removes a specific cache entry" do
      Cache.write("work", "jira", "invalidate:me", %{"data" => 1})
      assert {:ok, _} = Cache.read("work", "jira", "invalidate:me", 3600)

      Cache.invalidate("work", "jira", "invalidate:me")
      assert :miss = Cache.read("work", "jira", "invalidate:me", 3600)
    end

    test "does not fail when key doesn't exist" do
      assert _ = Cache.invalidate("work", "jira", "no:such:key")
    end
  end

  describe "invalidate_product/2" do
    test "removes all entries for a product" do
      Cache.write("work", "jira", "key1", %{"a" => 1})
      Cache.write("work", "jira", "key2", %{"b" => 2})
      Cache.write("work", "confluence", "key1", %{"c" => 3})

      Cache.invalidate_product("work", "jira")

      assert :miss = Cache.read("work", "jira", "key1", 3600)
      assert :miss = Cache.read("work", "jira", "key2", 3600)
      # Confluence entries should be untouched
      assert {:ok, _} = Cache.read("work", "confluence", "key1", 3600)
    end

    test "does nothing when product cache dir does not exist" do
      # invalidate_product returns nil when dir doesn't exist — just verify no crash
      Cache.invalidate_product("work", "nonexistent_product")
      :ok
    end
  end

  describe "invalidate_all/0" do
    test "removes all cache entries" do
      Cache.write("work", "jira", "key:all1", %{"x" => 1})
      Cache.write("personal", "confluence", "key:all2", %{"y" => 2})

      Cache.invalidate_all()

      assert :miss = Cache.read("work", "jira", "key:all1", 3600)
      assert :miss = Cache.read("personal", "confluence", "key:all2", 3600)
    end

    test "does nothing when cache dir does not exist" do
      Application.put_env(:librarian, :data_folder, "/nonexistent/cache/path")
      # invalidate_all returns nil when dir doesn't exist — just verify no crash
      Cache.invalidate_all()
      :ok
    end
  end
end
