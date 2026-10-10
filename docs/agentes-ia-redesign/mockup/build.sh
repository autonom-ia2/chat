#!/bin/bash
# Junta o protótipo num arquivo só (o Artifact publica uma página).
set -euo pipefail
cd "$(dirname "$0")"
{
  echo '<title>Agentes Chat2You — jornada</title>'
  echo '<style>'; /bin/cat src/styles.css; echo '</style>'
  echo '<script src="https://unpkg.com/lucide@0.453.0/dist/umd/lucide.min.js"></script>'
  echo '<script>'
  for f in data kit screens-list screens-build screens-panel screens-extra main; do /bin/cat "src/$f.js"; echo; done
  echo '</script>'
} > jornada.html
