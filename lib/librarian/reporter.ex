defmodule Librarian.Reporter do
  @moduledoc """
  Generates daily reports of processed documents and activity.
  """
  use GenServer
  require Logger

  # Check for end-of-day at 23:00 UTC
  @daily_check_ms 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    schedule_check()
    {:ok, %{last_report_date: nil}}
  end

  @impl true
  def handle_info(:check_daily, state) do
    today = Date.utc_today()

    state =
      if state.last_report_date != today do
        generate_daily_report(today)
        Librarian.Vault.Backup.prune()
        %{state | last_report_date: today}
      else
        state
      end

    schedule_check()
    {:noreply, state}
  end

  @doc "Manually generate today's report."
  def generate_now do
    generate_daily_report(Date.utc_today())
  end

  defp schedule_check do
    Process.send_after(self(), :check_daily, @daily_check_ms)
  end

  defp generate_daily_report(date) do
    data_folder = Application.get_env(:librarian, :data_folder, "")
    reports_dir = Path.join([data_folder, "logs", "reports"])
    File.mkdir_p!(reports_dir)

    report_path = Path.join(reports_dir, "#{date}.md")

    report = """
    ---
    title: Daily Report
    date: #{date}
    type: report
    ---

    # Librarian Daily Report — #{date}

    ## Documents Processed

    #{fetch_daily_activity(data_folder, date)}

    ## Summary

    Report generated at #{DateTime.utc_now() |> DateTime.to_string()}.
    """

    File.write!(report_path, report)
    Logger.info("Daily report generated: #{report_path}")
  end

  defp fetch_daily_activity(data_folder, _date) do
    log_file = Path.join(data_folder, "logs/processing.log")

    if File.exists?(log_file) do
      case File.read(log_file) do
        {:ok, content} -> content
        _ -> "*No activity recorded.*"
      end
    else
      "*No activity recorded.*"
    end
  end
end
