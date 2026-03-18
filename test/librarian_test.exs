defmodule LibrarianTest do
  use ExUnit.Case

  describe "Processor" do
    test "identifies supported formats" do
      assert Librarian.Processor.supported?("document.docx")
      assert Librarian.Processor.supported?("slides.pptx")
      assert Librarian.Processor.supported?("notes.md")
      assert Librarian.Processor.supported?("photo.png")
      refute Librarian.Processor.supported?("archive.zip")
    end
  end
end
