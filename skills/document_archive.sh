#!/bin/bash
# document_archive - Archive a document to the Obsidian vault with metadata
INPUT=$(cat)
echo "{\"result\": \"ok\", \"skill\": \"document_archive\", \"input\": $INPUT}"
