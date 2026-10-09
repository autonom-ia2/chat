# Checagem limitada F1 — produto e testes

**Resultado: PASS nesta checagem limitada — os quatro achados da revisão normal foram fechados no desenho e
na fonte visual.** Isso não aprova a implementação, as telas reais ou o release.

**Alvo:** `docs/agentes-ia-redesign/design/F1.md`, SHA-256
`9190084edc615e4b304eea0f2a230f6f304291bea6c9e9caacc451b3a1ac1fd4`.

**Fonte visual conferida:** `docs/agentes-ia-redesign/mockup/src/screens-list.js`, SHA-256
`f418c5faf6d344ace341608770df244aefb5279e54ea911f9e6083c3ff25c8c6`, com `data.js`, `kit.js` e os quatro
cenários descritos no F1.

## Fechamento dos quatro achados

### F1-UX-01 — Abrir para só ver

Fechado. O F1 define `Abrir` para E1–E4, sem `Continuar`, `Ligar`, interruptor ou menu para quem só vê
(`F1.md:110-115,142-144`). A fonte visual agora renderiza `Abrir` nos ramos `todo` e `ready` quando o perfil é
somente leitura (`mockup/src/screens-list.js:22-26`). As fixtures de E1, E2, E2m e E3 estão presentes em
`mockup/src/data.js:76-81`, e o cenário específico prova que o painel abre sem escrita
(`F1.md:177-183`).

### F1-UX-02 — contrato dos números

Fechado. O payload do cartão está fechado em `stats.week/month.replies/handoffs`, com janelas de 7 e 30 dias,
`handoffs` alimentando “passou” e ausência de números para `internal` (`F1.md:31-62`). A divergência visual
legada `stats[7]/stats[30]/handed` está nomeada como referência, sem virar contrato. O plano exige comparar os
quatro valores com ListStats/Analytics no mesmo relógio e provar uma única consulta para N agentes
(`F1.md:59-62,169-172,188-191`).

### F1-UX-03 — motivo da invalidação

Fechado. O F1 fixa duas chaves/cópias distintas para `material` e `person` e deriva `{A}` somente do enum
seguro `voice`, sem inferir pelo nome (`F1.md:150-154`). O mockup mostra as duas causas
(`mockup/src/screens-list.js:2-7`), com fixtures separadas (`mockup/src/data.js:79-80`), e o cenário real exige
as duas mensagens (`F1.md:177-180`). O caso interno e a fonte de voz segura também permanecem cobertos no
cenário de agentes (`F1.md:174-176`); não há retorno ao texto genérico.

### F1-TEST-01 — fixtures dos estados

Fechado. O mockup agora nomeia referências para interno, E1, E2, E2m, as duas causas de E3, E4, E5, E6 e sem
canal (`mockup/src/data.js:75-83`). O F1 separa essas referências das fixtures de produto, exige dados da API/
banco local e enumera os quatro cenários com as ações e estados que precisam ser observados
(`F1.md:26-29,64-70,169-191`). Isso fecha a matriz de comparação sem transformar IDs ou números do protótipo em
contrato real.

## Limites que permanecem

Esta checagem não reabre os dois achados técnicos já fechados no relatório técnico limitado. F1 continua DRAFT e
depende de F0, B2/BE-01/08/11/32, o campo seguro de voz e o leitor BE-05 real (`F1.md:7-22,193-203`). Ainda não
há aprovação de tela real, captura local, backend GREEN, merge, fila, deploy ou produção.

## Validação

- Releitura do F1 corrigido, do relatório normal, da causa registrada, do PRD CA-LISTA, B2 e das fontes visuais.
- Nenhuma alteração no F1, mockup ou produto durante esta checagem.
- Nenhum teste, build, navegador, banco, serviço, commit, push, PR, merge ou deploy executado.
