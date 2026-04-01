defmodule Librarian.Application do
  @moduledoc """
  OTP Application for the Librarian agent.

  Supervises: Repo, Vault.Watcher, Input monitor, Reporter, and Archiver.
  """
  use Application

  # MQ processes are skipped in test env (no IAMQ available, would block/reconnect-loop)
  @start_mq Mix.env() != :test

  @impl true
  def start(_type, _args) do
    mq_children =
      if @start_mq do
        [Librarian.IAMQ, Librarian.MqWsClient]
      else
        []
      end

    children =
      [
        Librarian.Repo,
        Librarian.Vault.Watcher,
        Librarian.Input,
        Librarian.Reporter,
        Librarian.Archiver
      ] ++
        mq_children ++
        [Librarian.StagingWorker]

    opts = [strategy: :one_for_one, name: Librarian.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
