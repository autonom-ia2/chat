# RAG v2, F1 (#1431) — medida do conjunto 1a + 1b + item contra a main (08/11/2026)

Mesma régua da `medida-f1.md`: `script/rag_placar/`, banco local de teste, os 2 PDFs públicos (Suhai auto 74 págs;
Mapfre residencial 71 págs), perguntas e gabaritos da F0 (`docs/audit/2026-10-31-rag-v2-f0/gabaritos/pdf.yml` e
`pdf-real2.yml`, sem mudança). Só a flag `rag_corte_por_estrutura` muda entre main e conjunto. Head medido: 26c1b27c2b.

A main não foi medida de novo: o código de RAG da main não mudou entre o merge-base 51ced25ff8 e origin/main
c0b0f99d2b (`git diff` dos arquivos de RAG vazio). Os números da main são os de `medida-f1.md`.

## Busca (perguntas respondíveis)

| | Suhai main | Suhai conjunto | Mapfre main | Mapfre conjunto |
|---|---|---|---|---|
| hit@1 | 0,31 | 0,52 | 0,41 | 0,47 |
| hit@5 | 0,66 | 0,79 | 0,56 | 0,69 |
| hit@12 | 0,83 | **0,93** | 0,72 | **0,875** |
| MRR | 0,47 | 0,65 | 0,50 | 0,58 |

Meta de busca (hit@12 ≥ 0,85): atingida nos dois.

## Resposta e recusa (todas as perguntas)

A 1ª rodada parou no teto antes das perguntas de fora da base; elas rodaram em rodadas só com as que faltavam, nos
mesmos agentes (sem nova ingestão).

| | Suhai main | Suhai conjunto | Mapfre main | Mapfre conjunto |
|---|---|---|---|---|
| Certas (respondíveis) | 23/29 (0,79) | **24/29 (0,83)** | 21/32 (0,66) | **28/32 (0,875)** |
| Recusa certa (fora da base) | 7/8 | **8/8 (1,00)** | 8/8 | **8/8 (1,00)** |
| Disse de onde veio | — | 0,79 | — | 0,78 |

Condições: Suhai não caiu (23 → 24) e a recusa ficou em 1,00 nos dois. Meta de acerto (≥ 0,88): **não atingida**.
Suhai precisa de 26/29 (faltam 2); Mapfre de 29/32 (falta 1).

## O que falta para a meta de acerto

As 9 erradas, por camada:

| Base | Pergunta (resumo) | Âncora no contexto? | Camada |
|---|---|---|---|
| Suhai | número para avisar a batida | sim | resposta: tinha o número e mandou à equipe |
| Suhai | roubo com rastreador | sim | resposta: passos genéricos em vez dos do contrato |
| Suhai | oficina do cunhado antes de avisar | não | busca |
| Suhai | a partir de quanto vira perda total | não | busca (o 75% veio de outro trecho) |
| Suhai | perda do movimento de um braço | não (0 trechos) | busca: fileira da tabela de invalidez não veio |
| Mapfre | seguradora demorou 45 dias | sim | resposta: não tirou a consequência do atraso |
| Mapfre | vendi o imóvel | sim | resposta |
| Mapfre | casa no Uruguai | não | âncora não fica inteira num trecho (limite conhecido) |
| Mapfre | carro na garagem, perda total | não | busca |

- 4 das 9 já têm a âncora no contexto: o erro está na resposta (cautela demais, "encaminhar à equipe" com o dado na
  mão). Corte e busca não resolvem essas; é trabalho do Answerer, com medida própria.
- 5 são de busca (uma delas, a do Uruguai, é limite conhecido). A ligadura lida errado pelo leitor de PDF
  ("especifjcação") segue na Issue #2765, fora deste PR.

## Depois do tester e da revisão (head 5adff0ecf5)

O tester (32 cenários, 28 passaram) achou 3 casos de código, corrigidos com teste antes:
- lista com marcador em letra 9 lida como tabela;
- cláusula numerada curta lida como tabela;
- o rodapé sumia quando a 1ª página era o sumário.

A revisão dessas correções achou mais um: a linha curta de introdução acima de uma lista de duas células passava como
cabeçalho, e a lista virava tabela. No Suhai isso acontecia de verdade, na lista de documentos do sinistro ("• |
Boletim de Ocorrência…"). Agora o cabeçalho de cima precisa cobrir as duas colunas, e essa lista sai como lista.

Busca nos 2 PDFs no head final: hit@12 igual (Suhai 0,93; Mapfre 0,875, a Mapfre idêntica em tudo). No Suhai, 4
perguntas mudaram de posição dentro do top 12 (hit@1 0,52 → 0,48; MRR 0,65 → 0,62). As 4 foram respondidas de novo
no head final: 4/4 certas, como antes. A rodada inteira de resposta não foi repetida (teto da etapa).

## Gasto

Resposta + juiz: US$ 1,00 (Suhai 0,41 + 0,04 + 0,05 das 4 de conferência; Mapfre 0,41 + 0,06 + 0,02 + 0,01).
Embeddings das ingestões e das rodadas só de busca da etapa: abaixo de US$ 0,06. Total da etapa ≈ US$ 1,06 do teto de
US$ 1,16.
