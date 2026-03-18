defmodule Librarian.Archiver do
  @moduledoc """
  Weekly archiver for processed documents.

  Every Sunday at midnight (UTC), compresses all files in each data folder's
  `processed/` directory into `processed-documents-WeekWW-YYYY.tar.gz` and
  removes the archived originals.
  """
  use GenServer
  require Logger

  # Check every hour whether it's time to archive
  @check_interval_ms 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    schedule_check()
    {:ok, %{last_archive_week: nil}}
  end

  @impl true
  def handle_info(:check_archive, state) do
    now = DateTime.utc_now()
    {year, week} = :calendar.iso_week_number({now.year, now.month, now.day})
    day_of_week = Date.day_of_week(Date.utc_today())

    state =
      if day_of_week == 7 and state.last_archive_week != {year, week} do
        archive_all_processed(year, week)
        %{state | last_archive_week: {year, week}}
      else
        state
      end

    schedule_check()
    {:noreply, state}
  end

  @doc "Manually trigger archiving for the current week."
  def archive_now do
    GenServer.cast(__MODULE__, :archive_now)
  end

  @impl true
  def handle_cast(:archive_now, state) do
    now = DateTime.utc_now()
    {year, week} = :calendar.iso_week_number({now.year, now.month, now.day})
    archive_all_processed(year, week)
    {:noreply, %{state | last_archive_week: {year, week}}}
  end

  defp schedule_check do
    Process.send_after(self(), :check_archive, @check_interval_ms)
  end

  defp archive_all_processed(year, week) do
    data_folders = Application.get_env(:librarian, :data_folders, [])

    Enum.each(data_folders, fn df ->
      processed_dir = Path.join(df, "processed")

      if File.dir?(processed_dir) do
        archive_processed_dir(processed_dir, year, week)
      end
    end)
  end

  defp archive_processed_dir(processed_dir, year, week) do
    week_str = week |> Integer.to_string() |> String.pad_leading(2, "0")
    archive_name = "processed-documents-Week#{week_str}-#{year}.tar.gz"
    archive_path = Path.join(processed_dir, archive_name)

    files =
      processed_dir
      |> File.ls!()
      |> Enum.reject(fn f ->
        String.starts_with?(f, ".") or String.ends_with?(f, ".tar.gz")
      end)

    if files == [] do
      Logger.info("No processed files to archive in #{processed_dir}")
    else
      Logger.info("Archiving #{length(files)} processed file(s) to #{archive_name}")

      # Build tar.gz using system tar
      case System.cmd("tar", ["-czf", archive_path | files], cd: processed_dir) do
        {_, 0} ->
          # Remove archived originals
          Enum.each(files, fn f ->
            File.rm(Path.join(processed_dir, f))
          end)

          Logger.info("Archive created: #{archive_path}")
          log_archive(processed_dir, archive_name, length(files))

        {output, code} ->
          Logger.error("Archive failed (exit #{code}): #{output}")
      end
    end
  end

  defp log_archive(processed_dir, archive_name, file_count) do
    log_dir = Application.get_env(:librarian, :log_dir, "")

    if log_dir != "" do
      File.mkdir_p!(log_dir)

      log_entry = """
      ## #{DateTime.utc_now() |> DateTime.to_string()}
      - **Action**: Weekly archive
      - **Location**: #{processed_dir}
      - **Archive**: #{archive_name}
      - **Files archived**: #{file_count}
      """

      log_file = Path.join(log_dir, "archiver.log")
      File.write!(log_file, log_entry, [:append])
    end
  end
end
