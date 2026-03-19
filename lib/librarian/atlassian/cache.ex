defmodule Librarian.Atlassian.Cache do
  @moduledoc """
  Filesystem-based cache for Atlassian API responses.

  Stores JSON responses under `$LIBRARIAN_DATA_FOLDER/cache/atlassian/`
  with a configurable TTL (default: 1 hour).

  ## Cache key structure

      cache/atlassian/<account_label>/<product>/<hashed_key>.json

  Each cached file includes a `_cached_at` timestamp for TTL checks.
  """
  require Logger

  @default_ttl_seconds 3600

  @doc """
  Fetch from cache or execute the given function.

  Returns cached result if fresh, otherwise calls `fun`, caches the result, and returns it.

      Cache.fetch("work", "jira", "issue-PROJ-123", fn ->
        Client.get("/rest/api/3/issue/PROJ-123", account: "work")
      end)
  """
  def fetch(account_label, product, key, fun, opts \\ []) do
    ttl = opts[:ttl] || @default_ttl_seconds

    case read(account_label, product, key, ttl) do
      {:ok, cached} ->
        {:ok, cached}

      :miss ->
        case fun.() do
          {:ok, result} ->
            write(account_label, product, key, result)
            {:ok, result}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Read a cached value if it exists and hasn't expired.
  """
  def read(account_label, product, key, ttl \\ @default_ttl_seconds) do
    path = cache_path(account_label, product, key)

    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, %{"_cached_at" => cached_at, "data" => data}} ->
            case DateTime.from_iso8601(cached_at) do
              {:ok, cached_dt, _} ->
                age = DateTime.diff(DateTime.utc_now(), cached_dt)

                if age < ttl do
                  {:ok, data}
                else
                  :miss
                end

              _ ->
                :miss
            end

          _ ->
            :miss
        end

      {:error, _} ->
        :miss
    end
  end

  @doc """
  Write a value to the cache.
  """
  def write(account_label, product, key, data) do
    path = cache_path(account_label, product, key)
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    envelope = %{
      "_cached_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "data" => data
    }

    File.write!(path, Jason.encode!(envelope, pretty: true))
  rescue
    e ->
      Logger.warning("Failed to write Atlassian cache: #{Exception.message(e)}")
      :ok
  end

  @doc """
  Invalidate a specific cache entry.
  """
  def invalidate(account_label, product, key) do
    path = cache_path(account_label, product, key)
    File.rm(path)
  end

  @doc """
  Invalidate all cache entries for a product (e.g., "jira" or "confluence").
  """
  def invalidate_product(account_label, product) do
    dir = cache_dir(account_label, product)

    if File.dir?(dir) do
      File.rm_rf!(dir)
      Logger.info("Invalidated Atlassian cache for #{account_label}/#{product}")
    end
  end

  @doc """
  Invalidate the entire Atlassian cache.
  """
  def invalidate_all do
    dir = base_cache_dir()

    if File.dir?(dir) do
      File.rm_rf!(dir)
      Logger.info("Invalidated entire Atlassian cache")
    end
  end

  # --- Private ---

  defp cache_path(account_label, product, key) do
    hashed = :crypto.hash(:sha256, key) |> Base.url_encode64(padding: false)
    Path.join(cache_dir(account_label, product), "#{hashed}.json")
  end

  defp cache_dir(account_label, product) do
    Path.join([base_cache_dir(), account_label, product])
  end

  defp base_cache_dir do
    data_folder = Application.get_env(:librarian, :data_folder, "")
    Path.join(data_folder, "cache/atlassian")
  end
end
