defmodule Librarian.Atlassian.Client do
  @moduledoc """
  HTTP client for Atlassian REST APIs.

  Handles authentication, pagination, rate limiting, and retries
  for all Atlassian product APIs (Jira, Confluence, JPD).

  ## Usage

      # Using default (first) account
      Client.get("/rest/api/3/issue/PROJ-123")

      # Using a specific account by label
      Client.get("/rest/api/3/issue/PROJ-123", account: "work")

      # With query parameters
      Client.get("/rest/api/3/search", account: "work", params: %{jql: "project = PROJ"})
  """
  require Logger

  @default_timeout 30_000
  @max_retries 3
  @retry_base_delay 1_000

  @type account :: %{
          label: String.t(),
          url: String.t(),
          email: String.t(),
          token: String.t()
        }

  @doc """
  Make a GET request to an Atlassian API endpoint.

  Options:
  - `:account` — account label (default: first configured account)
  - `:params` — query parameters map
  - `:timeout` — request timeout in ms (default: #{@default_timeout})
  """
  def get(path, opts \\ []) do
    with {:ok, account} <- resolve_account(opts[:account]) do
      url = build_url(account.url, path, opts[:params])
      timeout = opts[:timeout] || @default_timeout

      do_request(:get, url, account, timeout, 0)
    end
  end

  @doc """
  Make a GET request and automatically follow pagination.

  Returns all results concatenated from paginated responses.
  Works with both Jira-style (startAt/maxResults) and Confluence-style (start/limit) pagination.

  Options:
  - `:account` — account label
  - `:params` — base query parameters
  - `:results_key` — key in response containing the results list (default: "issues")
  - `:max_pages` — maximum pages to fetch (default: 20, safety limit)
  """
  def get_all_pages(path, opts \\ []) do
    results_key = opts[:results_key] || "issues"
    max_pages = opts[:max_pages] || 20
    params = opts[:params] || %{}

    do_paginate(path, opts, params, results_key, max_pages, 0, [])
  end

  @doc """
  Make a POST request to an Atlassian API endpoint.
  """
  def post(path, body, opts \\ []) do
    with {:ok, account} <- resolve_account(opts[:account]) do
      url = build_url(account.url, path, nil)
      timeout = opts[:timeout] || @default_timeout

      do_request(:post, url, account, timeout, 0, body)
    end
  end

  @doc """
  List all configured Atlassian accounts.
  """
  def list_accounts do
    Application.get_env(:librarian, :atlassian_accounts, [])
  end

  @doc """
  Get a specific account by label.
  """
  def get_account(label) do
    resolve_account(label)
  end

  # --- Private ---

  defp resolve_account(nil) do
    case list_accounts() do
      [first | _] -> {:ok, first}
      [] -> {:error, :no_atlassian_accounts_configured}
    end
  end

  defp resolve_account(label) when is_binary(label) do
    case Enum.find(list_accounts(), &(&1.label == label)) do
      nil -> {:error, {:account_not_found, label}}
      account -> {:ok, account}
    end
  end

  defp build_url(base_url, path, nil) do
    String.trim_trailing(base_url, "/") <> path
  end

  defp build_url(base_url, path, params) when is_map(params) do
    query = URI.encode_query(params)
    base = String.trim_trailing(base_url, "/") <> path

    if query == "" do
      base
    else
      base <> "?" <> query
    end
  end

  defp auth_header(account) do
    credentials = Base.encode64("#{account.email}:#{account.token}")
    {"authorization", "Basic #{credentials}"}
  end

  defp do_request(method, url, account, timeout, attempt, body \\ nil) do
    headers = [
      auth_header(account),
      {"accept", "application/json"},
      {"content-type", "application/json"}
    ]

    result =
      case method do
        :get ->
          Req.get(url, headers: headers, receive_timeout: timeout)

        :post ->
          json_body = if is_map(body), do: Jason.encode!(body), else: body
          Req.post(url, headers: headers, body: json_body, receive_timeout: timeout)
      end

    case result do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: 429, headers: headers}} ->
        # Rate limited — respect Retry-After header
        retry_after = get_retry_after(headers)
        Logger.warning("Atlassian rate limited, retrying after #{retry_after}ms")
        Process.sleep(retry_after)

        if attempt < @max_retries do
          do_request(method, url, account, timeout, attempt + 1, body)
        else
          {:error, :rate_limited}
        end

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 403}} ->
        {:error, :forbidden}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status, body: resp_body}} ->
        Logger.error("Atlassian API error #{status}: #{inspect(resp_body)}")
        {:error, {:api_error, status, resp_body}}

      {:error, %{reason: reason}} when attempt < @max_retries ->
        delay = @retry_base_delay * :math.pow(2, attempt) |> round()
        Logger.warning("Atlassian request failed (#{inspect(reason)}), retrying in #{delay}ms")
        Process.sleep(delay)
        do_request(method, url, account, timeout, attempt + 1, body)

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp get_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {_, value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds * 1000
          :error -> 5_000
        end

      nil ->
        5_000
    end
  end

  defp do_paginate(_path, _opts, _params, _results_key, max_pages, page, acc)
       when page >= max_pages do
    Logger.warning("Atlassian pagination hit max_pages limit (#{max_pages})")
    {:ok, Enum.reverse(acc) |> List.flatten()}
  end

  defp do_paginate(path, opts, params, results_key, max_pages, page, acc) do
    page_params = Map.merge(params, %{"startAt" => page * 50, "maxResults" => 50})

    case get(path, Keyword.put(opts, :params, page_params)) do
      {:ok, body} when is_map(body) ->
        results = Map.get(body, results_key, [])
        total = Map.get(body, "total", 0)
        fetched = (page * 50) + length(results)

        new_acc = [results | acc]

        if fetched >= total or results == [] do
          {:ok, Enum.reverse(new_acc) |> List.flatten()}
        else
          do_paginate(path, opts, params, results_key, max_pages, page + 1, new_acc)
        end

      {:ok, body} ->
        {:ok, [body | acc] |> Enum.reverse() |> List.flatten()}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
