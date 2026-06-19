#!/usr/bin/env bash
set -e

echo "=== Breezy Wiki ==="
echo "Lancement du serveur de prévisualisation MkDocs..."
echo "Ouvrez http://127.0.0.1:8000 dans votre navigateur."
echo ""

mkdocs serve
