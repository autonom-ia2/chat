#!/bin/bash
# #1431 — baixa os documentos reais e públicos da régua para fora do repositório (são grandes e de terceiros).
#   script/rag_placar/baixar_reais.sh [pasta]     padrão: $TMPDIR/rag_placar/reais
set -euo pipefail
pasta=${1:-${TMPDIR:-/tmp}/rag_placar/reais}
mkdir -p "$pasta"
# PDF Mapfre: Condições Contratuais do Seguro Residencial v3.0 (gabarito pdf-real2.yml).
curl -fsSL -o "$pasta/pdf-real2.pdf" https://www.mapfre.com.br/media/cg_residencial_3-0.pdf
# XLSX da Prefeitura de Curitiba: Tabela de Custos Unitários da SMOP, abril/2022 (gabarito xlsx-real.yml).
curl -fsSL -o "$pasta/xlsx-real.xlsx" https://mid.curitiba.pr.gov.br/2024/00443250.xlsx
# PDF Suhai: Condição Geral do seguro auto, 74 páginas (gabaritos pdf.yml e perguntas-suhai.yml). A URL pública ainda
# não foi registrada aqui; quando for, entra nesta lista.
ls -l "$pasta"
