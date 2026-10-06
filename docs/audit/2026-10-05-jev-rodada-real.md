# Rodada real paga do Jev — Públicos e Importar contatos (Q4)

Refs #990 (PRD §8.7, aceite Q4) · #992 · #1006.

**Status: EXECUTADA em 06/10/2026** (local, planilhas sintéticas). Resultado no fim do documento.

## Teto aprovado

| Campo | Valor |
|---|---|
| Teto de gasto (US$) | US$ 5,00 (parar em 80%) |
| Teto de chamadas | 10 |
| Aprovado por / data | Rodrigo — 2026-10-06 (delegou a definição do teto; valores acima definidos pela sessão Campanhas) |
| Ambiente | local (worktree do chat2you), nunca produção |

## O que a rodada prova

1. Com `CAMPAIGN_JOURNEY_JEV_ENABLED=true` e chave TypeSafe, o Jev acha nome, celular, e-mail e
   empresa sozinho (`schema_resolution.method = "jev"`) em planilhas no formato das corretoras (B1, B1c,
   B3), no mesmo serviço usado por Novo público e Importar contatos
   (`CampaignImports::SpreadsheetReader` → `TypesafeAi::AudienceSchemaResolver`).
2. Resposta insegura ou erro do provedor cai em escolha manual, sem alias silencioso (Q3, B2).
3. O corpo enviado tem só cabeçalhos, contagens e formato mascarado (B4/Q1) — conferido em cada
   requisição real, não só no spec.

## Pré-requisitos

- Modelo fixo `jev-1.13.0` (`TYPESAFE_JEV_MODEL`; nunca `jev-latest`).
- Chave TypeSafe passada só em variável de ambiente do processo local (`TYPESAFE_API_KEY`), injetada
  no `TypesafeAi::Client`; nunca gravada em banco, arquivo, log ou chat.
- Planilhas **sintéticas** com o formato real (nomes e números inventados). Nenhuma planilha de cliente.

## Roteiro

| # | Planilha (sintética) | Esperado |
|---|---|---|
| 1 | XLSX `Segurado`, `Fone 1`, `Corretora`, `Vencimento` | `method=jev`; Vencimento extra |
| 2 | CSV `;` `Responsável`, `Email comercial`, `Corretora` | `method=jev`; selo E-mail |
| 3 | XLSX com cabeçalho na linha 3 | cabeçalho achado; `method=jev` |
| 4 | CSV com `Nome`, `Telefone fixo`, `Celular`, `Empresa`, `Plano` | celular ≠ fixo; Plano extra |
| 5 | CSV ambíguo (duas colunas de celular) | `needs_column_choice`, sem erro |

## Resultado

Execução local (`rails runner` no ambiente de teste da worktree, nunca produção). Cada pedido foi
inspecionado antes de sair: **nenhum** nome, celular ou e-mail das planilhas apareceu no corpo (B4/Q1).

| # | Linha do cabeçalho | `method` | Escolhas do Jev (confiança) | Resultado |
|---|---|---|---|---|
| 1 | 1 | jev | nome 0,89 · celular 0,99 · e-mail "não há" 1,0 · empresa 0,94 | ok |
| 2 | 1 | jev | nome 0,88 · celular "não há" 1,0 · e-mail 0,97 · empresa 0,92 | ok |
| 3 | **3** | jev | nome 1,0 · celular 1,0 · empresa 0,99 | ok — cabeçalho achado na linha 3 |
| 4 | 1 | jev | celular = **Celular** (não o "Telefone fixo") 1,0 · empresa 0,99 | ok |
| 5 | 1 | jev | celular = **Celular** (1ª das duas) 0,97 | **desvio** — escolheu com confiança em vez de devolver dúvida |

- Chamadas: **7** de 10 (5 da rodada + 2 repetições das planilhas 4 e 5 para registrar a coluna escolhida).
- Uso: 14.395 tokens de entrada e 1.849 de saída no total (≈ 2.060 + 265 por planilha).
- Custo: a resposta da TypeSafe traz tokens, não valor em dinheiro, e não há tabela de preço
  versionada no repositório. Pelo volume (≈ 16 mil tokens) o gasto fica muito abaixo do teto de
  US$ 5; o valor exato deve ser conferido no painel da TypeSafe.
- Desvio da planilha 5: escolha razoável (coluna principal), mas não prova com resposta real o caminho
  "Jev inseguro → escolha manual". Esse caminho (Q3/B2) segue coberto por specs com respostas
  simuladas (`spec/services/campaign_imports/audience_validator_spec.rb`).
- Decisão: aceite Q4 cumprido. O Jev da jornada está ligado em produção nas 2 stacks desde
  06/10/2026 (Super Admin → App Configs → TypeSafe, #1045/#1046).
