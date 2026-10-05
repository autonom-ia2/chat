# Rodada real paga do Jev — Públicos e Importar contatos (Q4)

Refs #990 (PRD §8.7, aceite Q4) · #992 · #1006.

**Status: NÃO EXECUTADA.** Este documento é o roteiro. A rodada só acontece depois que o
Rodrigo aprovar o teto abaixo, por escrito, e o resultado é registrado aqui mesmo.

## Teto aprovado

| Campo | Valor |
|---|---|
| Teto de gasto (US$) | `<<PREENCHER — aprovado pelo Rodrigo>>` |
| Teto de chamadas | `<<PREENCHER>>` (referência: 1 chamada por planilha; 10 planilhas = 10 chamadas) |
| Aprovado por / data | `<<Rodrigo — AAAA-MM-DD>>` |
| Ambiente | local (worktree do chat2you), nunca produção |

Sem as três primeiras linhas preenchidas, ninguém roda nada.

## O que a rodada prova

1. Com `CAMPAIGN_JOURNEY_JEV_ENABLED=true` e chave TypeSafe, o Jev acha nome, celular, e-mail e
   empresa sozinho (`schema_resolution.method = "jev"`) em planilhas reais de corretoras (B1, B1c,
   B3), tanto em Novo público quanto em Importar contatos — o mesmo serviço
   (`CampaignImports::SpreadsheetReader` → `TypesafeAi::AudienceSchemaResolver`).
2. Resposta insegura ou erro do provedor cai em escolha manual, sem alias silencioso (Q3, B2).
3. O corpo enviado tem só cabeçalhos, contagens e formato mascarado (B4/Q1) — conferido no log da
   requisição, não só no spec.

## Pré-requisitos

- Modelo fixo `jev-1.13.0` (`TYPESAFE_JEV_MODEL`; nunca `jev-latest`).
- Chave em `AiProviderCredential.for('typesafe')` da instalação local. Nunca copiar a chave para
  arquivo, log ou chat; citar só o nome.
- Planilhas **sintéticas** com o formato real (nomes e números inventados, celulares de teste).
  Nenhuma planilha de cliente.
- `CAMPAIGN_IMPORT_ENABLED=true`, `CAMPAIGN_JOURNEY_ENABLED=true`, `CAMPAIGN_JOURNEY_JEV_ENABLED=true`.

## Roteiro

| # | Planilha (sintética) | Tela | Esperado |
|---|---|---|---|
| 1 | XLSX `Segurado`, `Fone 1`, `Corretora`, `Vencimento` | Novo público | `method=jev`; Vencimento extra |
| 2 | CSV `;` `Responsável`, `Email comercial`, `Corretora` | Novo público | `method=jev`; selo E-mail |
| 3 | XLSX com cabeçalho na linha 3 | Importar contatos | cabeçalho achado; `method=jev` |
| 4 | CSV com `Nome`, `Telefone fixo`, `Celular`, `Empresa`, `Plano` | Importar contatos | celular ≠ fixo; Plano vira atributo |
| 5 | CSV ambíguo (duas colunas de celular) | Importar contatos | `needs_column_choice`, sem erro |

Para cada linha registrar: id da importação, `schema_resolution.method`, `jev.status`,
`jev.schema_probability`, confiança por alvo, `usage` (tokens) e custo estimado. Parar na hora se
o custo acumulado chegar a 80% do teto.

## Resultado

`<<preencher depois da rodada: tabela acima com os valores, custo total, desvios e decisão>>`
