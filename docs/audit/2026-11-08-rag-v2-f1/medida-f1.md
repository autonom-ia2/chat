# RAG v2, F1 (#1431) — medida do PR 1a contra a main (08/11/2026)

Régua: `script/rag_placar/`, banco local de teste, 2 PDFs públicos de condições gerais (Suhai auto 74 págs; Mapfre
residencial 71 págs), perguntas e gabaritos da F0 em `docs/audit/2026-10-31-rag-v2-f0/gabaritos/` (`pdf.yml`,
`pdf-real2.yml`). Só a flag `rag_corte_por_estrutura` muda entre main e F1. Resposta = Answerer do agente; juiz = o do
autoteste.

## Busca (todas as perguntas respondíveis)

| | Suhai main | Suhai F1 | Mapfre main | Mapfre F1 |
|---|---|---|---|---|
| hit@1 | 0,31 | 0,38 | 0,41 | 0,38 |
| hit@5 | 0,66 | 0,59 | 0,56 | 0,66 |
| hit@12 | 0,83 | 0,76 | 0,72 | 0,81 |
| MRR | 0,47 | 0,49 | 0,50 | 0,52 |

A busca do head final (com o sumário do Mapfre fora) foi medida de novo: os mesmos números, só o MRR da Mapfre 0,51→0,52.

## Resposta e recusa (todas as perguntas)

A rodada da F1 parou no teto por base nas primeiras perguntas (trecho maior custa mais por resposta). As que faltaram
(10 do Suhai, 16 da Mapfre) rodaram numa segunda rodada só com elas.

| | Suhai main | Suhai F1 | Mapfre main | Mapfre F1 |
|---|---|---|---|---|
| Certas (respondíveis) | 23/29 (0,79) | 22/29 (0,76) | 21/32 (0,66) | 24/32 (0,75) |
| Recusa certa (fora da base) | 7/8 | 8/8 | 8/8 | 8/8 |

Suhai 23→22 e o ganho de hit@1 estão dentro da margem: não é ganho nem perda. Mapfre +3 certas e +0,09 no hit@12.

## Por que o hit@12 do Suhai caiu (0,83 → 0,76)

Perdeu 5 perguntas no top 12 e ganhou 3. As 5:

| Pergunta (resumo) | Onde está a âncora na F1 | Causa |
|---|---|---|
| surdez de um ouvido | trecho da "9 – TABELA … INVALIDEZ", 1.346 chars | linha de tabela diluída na tabela inteira |
| mandíbula que não colou | o mesmo trecho | idem |
| som e tela multimídia | "2. EXCLUSÕES …", 1.702 chars | item de lista diluído na seção longa |
| perda total a partir de quanto | "3. DEFINIÇÕES", 1.647 chars | item de glossário diluído |
| plano 200 → 500 km | "2. DESPESAS COBERTAS", 923 chars | item de lista diluído |

Na main essas âncoras estavam em pedaços de 118 a 515 chars, mas com o título errado (a tabela 9 aparecia sob
"8. ÂMBITO GEOGRÁFICO"). Não é só a tabela 9: é a granularidade da seção longa de itens (lista, glossário, tabela).
Nenhum texto se perde: as 34 âncoras continuam inteiras num trecho.

Testado e descartado, só com busca (custo de embedding):
- teto de 800 chars por trecho: Suhai hit@12 0,72, Mapfre 0,81 com hit@1 0,25. Pior.
- título só pela fonte proibido de terminar em ".", ":" ou ";" (87 dos 233 títulos do Suhai têm mais de 70 chars):
  Suhai 0,72, Mapfre 0,69. Pior.

## O que falta para a meta (hit@12 ≥ 0,85 e acerto ≥ 0,88 nos PDFs reais)

O PR 1a sozinho não chega lá.
- PR 1b, tabela por coluna com o cabeçalho repetido: as erradas de tabela são 2 no Suhai (surdez, mandíbula) e 3 na
  Mapfre (tabela de prazo curto). Se todas virarem certas: Suhai 24/29 (0,83), Mapfre 27/32 (0,84).
- Para passar disso: item de lista e de glossário como unidade, com o título da seção (som, perda total, 200→500 km,
  rastreador). Fica para depois do 1b, com medida própria.

## Gasto

US$ 1,44 do teto de US$ 2: main US$ 0,52, F1 1ª rodada US$ 0,62, F1 resto US$ 0,31, variantes só de busca abaixo de
US$ 0,01.
