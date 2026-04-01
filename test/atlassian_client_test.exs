defmodule Librarian.Atlassian.ClientTest do
  use ExUnit.Case, async: true

  alias Librarian.Atlassian.Client

  # Restore atlassian_accounts after each test
  setup do
    previous = Application.get_env(:librarian, :atlassian_accounts, [])

    on_exit(fn ->
      Application.put_env(:librarian, :atlassian_accounts, previous)
    end)

    :ok
  end

  describe "list_accounts/0" do
    test "returns empty list when no accounts configured" do
      Application.put_env(:librarian, :atlassian_accounts, [])
      assert Client.list_accounts() == []
    end

    test "returns configured accounts" do
      accounts = [
        %{label: "work", url: "https://work.atlassian.net", email: "user@work.com", token: "tok1"},
        %{label: "personal", url: "https://me.atlassian.net", email: "me@me.com", token: "tok2"}
      ]

      Application.put_env(:librarian, :atlassian_accounts, accounts)
      assert Client.list_accounts() == accounts
    end
  end

  describe "get_account/1" do
    test "returns account by label" do
      account = %{label: "work", url: "https://work.atlassian.net", email: "a@b.com", token: "t"}
      Application.put_env(:librarian, :atlassian_accounts, [account])

      assert {:ok, ^account} = Client.get_account("work")
    end

    test "returns error when label not found" do
      Application.put_env(:librarian, :atlassian_accounts, [
        %{label: "work", url: "https://work.atlassian.net", email: "a@b.com", token: "t"}
      ])

      assert {:error, {:account_not_found, "other"}} = Client.get_account("other")
    end

    test "returns error when no accounts configured" do
      Application.put_env(:librarian, :atlassian_accounts, [])
      assert {:error, :no_atlassian_accounts_configured} = Client.get_account(nil)
    end
  end

  describe "get/2 - error when no accounts" do
    test "returns error when no accounts configured" do
      Application.put_env(:librarian, :atlassian_accounts, [])
      assert {:error, :no_atlassian_accounts_configured} = Client.get("/some/path")
    end

    test "returns error when account label not found" do
      Application.put_env(:librarian, :atlassian_accounts, [
        %{label: "work", url: "https://work.atlassian.net", email: "a@b.com", token: "t"}
      ])

      assert {:error, {:account_not_found, "nonexistent"}} =
               Client.get("/some/path", account: "nonexistent")
    end
  end
end
