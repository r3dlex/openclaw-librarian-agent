defmodule Librarian.ProcessorTest do
  use ExUnit.Case, async: true

  alias Librarian.Processor

  describe "supported?/1" do
    test "returns true for supported document formats" do
      assert Processor.supported?("document.docx")
      assert Processor.supported?("slides.pptx")
      assert Processor.supported?("file.txt")
      assert Processor.supported?("notes.md")
      assert Processor.supported?("file.pdf")
      assert Processor.supported?("page.html")
      assert Processor.supported?("doc.rtf")
      assert Processor.supported?("file.odt")
      assert Processor.supported?("book.epub")
    end

    test "returns true for image formats (OCR)" do
      assert Processor.supported?("photo.png")
      assert Processor.supported?("image.jpg")
      assert Processor.supported?("image.jpeg")
      assert Processor.supported?("anim.gif")
      assert Processor.supported?("bitmap.bmp")
      assert Processor.supported?("scan.tiff")
    end

    test "returns false for unsupported formats" do
      refute Processor.supported?("archive.zip")
      refute Processor.supported?("video.mp4")
      refute Processor.supported?("script.sh")
      refute Processor.supported?("data.csv")
      refute Processor.supported?("exec.exe")
    end

    test "is case-insensitive for extensions" do
      assert Processor.supported?("FILE.DOCX")
      assert Processor.supported?("IMAGE.PNG")
      refute Processor.supported?("ARCHIVE.ZIP")
    end

    test "returns false for files with no extension" do
      refute Processor.supported?("noextension")
    end

    test "handles paths with directories" do
      assert Processor.supported?("/some/path/to/file.docx")
      refute Processor.supported?("/some/path/to/file.zip")
    end
  end

  describe "convert/1 - plain text and markdown" do
    test "reads .txt file directly without pandoc" do
      path = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(999_999)}.txt")
      File.write!(path, "Hello, world!")

      assert {:ok, content} = Processor.convert(path)
      assert content == "Hello, world!"

      File.rm(path)
    end

    test "reads .md file directly without pandoc" do
      path = Path.join(System.tmp_dir!(), "test_#{:rand.uniform(999_999)}.md")
      File.write!(path, "# Heading\n\nContent here.")

      assert {:ok, content} = Processor.convert(path)
      assert content == "# Heading\n\nContent here."

      File.rm(path)
    end

    test "returns error for txt file that does not exist" do
      assert {:error, _reason} = Processor.convert("/nonexistent/path/file.txt")
    end
  end

  describe "convert/1 - unsupported format" do
    test "returns error for unsupported extension" do
      assert {:error, "Unsupported format: .zip"} = Processor.convert("archive.zip")
    end

    test "returns error for .exe files" do
      assert {:error, "Unsupported format: .exe"} = Processor.convert("app.exe")
    end
  end
end
