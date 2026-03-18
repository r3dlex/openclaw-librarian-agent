defmodule Librarian.Processor do
  @moduledoc """
  Converts documents from various formats to markdown using Pandoc.
  """
  require Logger

  @supported_formats ~w(.docx .pptx .txt .md .pdf .html .rtf .odt .epub)

  @doc "Convert a document to markdown. Returns {:ok, markdown} or {:error, reason}."
  def convert(source_path) do
    ext = Path.extname(source_path) |> String.downcase()

    cond do
      ext in [".md", ".txt"] ->
        File.read(source_path)

      ext in @supported_formats ->
        pandoc_convert(source_path, ext)

      ext in ~w(.png .jpg .jpeg .gif .bmp .tiff) ->
        ocr_extract(source_path)

      true ->
        {:error, "Unsupported format: #{ext}"}
    end
  end

  defp pandoc_convert(source_path, _ext) do
    case System.cmd("pandoc", ["-t", "markdown", "--wrap=none", source_path],
           stderr_to_stdout: true
         ) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, "Pandoc conversion failed: #{error}"}
    end
  end

  defp ocr_extract(source_path) do
    case System.cmd("tesseract", [source_path, "stdout"], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, "OCR extraction failed: #{error}"}
    end
  end

  @doc "Check if a file format is supported."
  def supported?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in @supported_formats or ext in ~w(.png .jpg .jpeg .gif .bmp .tiff)
  end
end
