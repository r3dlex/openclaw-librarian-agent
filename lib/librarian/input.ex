defmodule Librarian.Input do
  @moduledoc """
  Monitors multiple input folders for new documents to process.

  Converts documents and stages them for the Librarian agent to classify.
  Input paths are configured via `LIBRARIAN_INPUT_PATHS` (comma-separated)
  plus the default `$LIBRARIAN_DATA_FOLDER/input`.

  After processing, source files are moved to the `processed/` directory
  of the data folder that owns the input path (or the primary data folder).
  Checks periodically (every 15 minutes by default).
  """
  use GenServer
  require Logger

  @check_interval_ms 15 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    ensure_directories()
    # Process existing files immediately on startup, then schedule periodic checks
    send(self(), :check_input)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check_input, state) do
    try do
      process_all_input_folders()
      Librarian.Staging.cleanup()
    rescue
      e ->
        Logger.error("Input processing cycle failed: #{Exception.message(e)}")
    end

    schedule_check()
    {:noreply, state}
  end

  @doc "Manually trigger input folder processing."
  def process_now do
    GenServer.cast(__MODULE__, :process_now)
  end

  @impl true
  def handle_cast(:process_now, state) do
    process_all_input_folders()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_input, @check_interval_ms)
  end

  defp ensure_directories do
    data_folders = Application.get_env(:librarian, :data_folders, [])

    Enum.each(data_folders, fn df ->
      Enum.each(~w(input staging processed log backups), fn sub ->
        dir = Path.join(df, sub)
        File.mkdir_p!(dir)
      end)
    end)

    log_dir = Application.get_env(:librarian, :log_dir, "")
    if log_dir != "", do: File.mkdir_p!(Path.join(log_dir, "reports"))
  end

  defp input_paths do
    configured = Application.get_env(:librarian, :input_paths, [])
    data_folder = Application.get_env(:librarian, :data_folder, "")
    default = Path.join(data_folder, "input")
    [default | configured] |> Enum.uniq()
  end

  defp process_all_input_folders do
    paths = input_paths()
    Logger.info("Checking #{length(paths)} input folder(s)")

    Enum.each(paths, fn path ->
      process_input_folder(path)
    end)
  end

  defp process_input_folder(input_path) do
    if File.dir?(input_path) do
      files =
        input_path
        |> File.ls!()
        |> Enum.reject(&String.starts_with?(&1, "."))
        |> Enum.filter(fn file ->
          full = Path.join(input_path, file)
          !File.dir?(full) and Librarian.Processor.supported?(full)
        end)

      Enum.each(files, fn file ->
        full_path = Path.join(input_path, file)
        companion = Path.join(input_path, Path.rootname(file) <> ".md")

        instructions =
          if File.exists?(companion) and Path.basename(companion) != file do
            File.read!(companion)
          else
            nil
          end

        process_file(full_path, instructions)
      end)
    else
      Logger.warning("Input folder not available: #{input_path}")
    end
  end

  defp process_file(path, instructions) do
    Logger.info("Processing input: #{path}")

    case Librarian.Processor.convert(path) do
      {:ok, markdown} ->
        {:ok, id} =
          Librarian.Staging.stage(markdown, %{
            source_file: Path.basename(path),
            source_format: Path.extname(path),
            instructions: instructions
          })

        log_processing(path, :ok, id)

        # Move source and companion to processed/
        move_to_processed(path)
        companion = Path.rootname(path) <> ".md"
        if File.exists?(companion), do: move_to_processed(companion)

        Logger.info("Staged #{Path.basename(path)} as #{id}")

      {:error, reason} ->
        Logger.error("Failed to process #{path}: #{reason}")
        log_processing(path, {:error, reason}, nil)
    end
  end

  defp move_to_processed(path) do
    processed_dir = resolve_processed_dir(path)
    File.mkdir_p!(processed_dir)
    dest = Path.join(processed_dir, Path.basename(path))

    # Avoid overwriting: append timestamp if file exists
    dest =
      if File.exists?(dest) do
        ts = DateTime.utc_now() |> Calendar.strftime("%Y%m%d_%H%M%S")
        ext = Path.extname(dest)
        base = Path.rootname(dest)
        "#{base}_#{ts}#{ext}"
      else
        dest
      end

    case File.rename(path, dest) do
      :ok ->
        Logger.debug("Moved #{Path.basename(path)} to processed/")

      {:error, :exdev} ->
        # Cross-device: copy then delete
        File.cp!(path, dest)
        File.rm!(path)
        Logger.debug("Copied #{Path.basename(path)} to processed/ (cross-device)")

      {:error, reason} ->
        Logger.warning("Failed to move #{path} to processed/: #{inspect(reason)}, removing instead")
        File.rm(path)
    end
  end

  defp resolve_processed_dir(path) do
    data_folders = Application.get_env(:librarian, :data_folders, [])
    input_dir = Path.dirname(path)

    # Find the data folder that owns this input path
    owner =
      Enum.find(data_folders, fn df ->
        String.starts_with?(input_dir, df)
      end)

    case owner do
      nil ->
        # Input not under any data folder — use primary
        primary = Application.get_env(:librarian, :data_folder, "")
        Path.join(primary, "processed")

      df ->
        Path.join(df, "processed")
    end
  end

  defp log_processing(path, result, staging_id) do
    log_dir = Application.get_env(:librarian, :log_dir, "")

    if log_dir != "" do
      File.mkdir_p!(log_dir)

      log_entry = """
      ## #{DateTime.utc_now() |> DateTime.to_string()}
      - **File**: #{Path.basename(path)}
      - **Source folder**: #{Path.dirname(path)}
      - **Result**: #{inspect(result)}
      - **Staging ID**: #{staging_id || "N/A"}
      """

      log_file = Path.join(log_dir, "processing.log")
      File.write!(log_file, log_entry, [:append])
    end
  end
end
