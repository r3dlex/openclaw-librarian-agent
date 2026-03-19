defmodule Librarian.Notifier do
  @moduledoc """
  Sends notifications to external services via webhook.

  Posts JSON payloads to a configured webhook URL (e.g., n8n workflow)
  which forwards them to Telegram or other channels.

  Configure via `LIBRARIAN_NOTIFY_WEBHOOK_URL` env variable.
  If unset, notifications are silently skipped (logged at debug level).
  """
  require Logger

  @doc """
  Send a notification with an event type and message body.

  ## Examples

      Librarian.Notifier.notify("document_processed", "Staged report.docx as abc123")
      Librarian.Notifier.notify("archive_created", "Archived 5 files to Week12-2026.tar.gz")
  """
  def notify(event, message) do
    case webhook_url() do
      url when url in [nil, ""] ->
        Logger.debug("Notifier: no webhook URL configured, skipping notification")
        :ok

      url ->
        payload = %{event: event, message: message}

        Task.start(fn ->
          case Req.post(url, json: payload, receive_timeout: 10_000) do
            {:ok, %{status: status}} when status in 200..299 ->
              Logger.debug("Notification sent: #{event}")

            {:ok, %{status: status, body: body}} ->
              Logger.warning("Notification webhook returned #{status}: #{inspect(body)}")

            {:error, reason} ->
              Logger.warning("Notification webhook failed: #{inspect(reason)}")
          end
        end)

        :ok
    end
  end

  @doc "Send a notification about a processed document."
  def notify_processed(filename, staging_id) do
    notify("document_processed", """
    **File:** #{filename}
    **Staging ID:** #{staging_id}
    Document converted and staged for classification.
    """)
  end

  @doc "Send a notification about a generated daily report."
  def notify_report(date, report_path) do
    notify("daily_report", """
    **Date:** #{date}
    **Report:** #{report_path}
    Daily report generated successfully.
    """)
  end

  @doc "Send a notification about a weekly archive."
  def notify_archive(archive_name, file_count, location) do
    notify("weekly_archive", """
    **Archive:** #{archive_name}
    **Files:** #{file_count}
    **Location:** #{location}
    Weekly archive created successfully.
    """)
  end

  @doc "Send a notification about a processing error."
  def notify_error(context, error) do
    notify("error", """
    **Context:** #{context}
    **Error:** #{inspect(error)}
    """)
  end

  defp webhook_url do
    Application.get_env(:librarian, :notify_webhook_url)
  end
end
