# QA independente — Kanban CRM, cards/funis e empresa

**Data:** 2026-10-01
**Checkout revisado:** `/Users/rodrigosilva/.codex/worktrees/793-audit-design/chat2you`
**HEAD:** `56b56f3a79` (integração de `1acd2b1809` e correção de concorrência da PR793)
**Escopo:** leitura estática de API, Vue/Vuex, Enterprise e evidências visuais locais; nenhuma alteração de produto, spec ou banco.

## Parecer

O Kanban distingue corretamente, no contrato atual, o **título do negócio**, a pessoa de contato, o responsável, a caixa de entrada e os sinais de atividade. A empresa não faz parte desse contrato: em um caso B2B o nome da empresa pode existir no CRM, mas não chega no payload compacto do board nem é renderizado no card/lista. Ela só aparece depois de abrir o detalhe e carregar o relacionamento, por outra requisição. Portanto, não considero “empresa no Kanban” entregue.

Esse é um achado de contrato, não uma alegação de falha de produção. Não acessei a conta 18, produção, autenticação externa, banco externo nem IA paga. As capturas locais são sintéticas e históricas; servem para mostrar a apresentação, não para provar merge, deploy ou o estado atual em produção.

## Achados prioritários

### P1 — Empresa B2B ausente do payload e da apresentação do Kanban

**Fatos no código:**

- `BoardPayloadBuilder` pré-carrega `owner`, participantes, labels, inbox e conversa, mas não `contact.company` (`app/services/crm/kanban/board_payload_builder.rb:143-153`).
- `CardPayloadBuilder#compact_contact` emite somente `id`, `name` e `phone_number` (`app/services/crm/kanban/card_payload_builder.rb:120-128`). Não há `company_id`, `company.name` nem `company` nula explícita.
- O card mostra `card.title` como título do negócio (`CrmKanbanCard.vue:317-321`) e o nome/telefone da pessoa como linha secundária (`:348-353`). O componente não tem renderização de empresa.
- A tabela usa o mesmo conceito de subtítulo pessoa/telefone (`CrmCardsTable.vue:369-372, 767-782`); `cardColumns.js:35-68` não possui coluna empresa.
- O painel de relacionamento refaz `ContactAPI.show` e, quando há `company_id`, chama `CompanyAPI.show` (`CrmCardRelationshipPanel.vue:92-116`). É ali que o nome canônico pode aparecer, com fallback de texto legado em `additional_attributes.company_name` (`:466-475`).
- A relação canônica é Enterprise (`enterprise/app/models/enterprise/concerns/contact.rb:1-14`). O endpoint de busca de contatos só inclui empresa com `include_company=true` (`enterprise/app/controllers/enterprise/api/v1/accounts/contacts_controller.rb:1-11`); isso ajuda o picker, não o board.

**Reprodução sintética:** contato com `company_id` e nome de empresa, card aberto ligado a esse contato; chamar o board. A resposta contém `contact: {id, name, phone_number}`. Ao montar `CrmKanbanCard`, aparece título da oportunidade e pessoa, sem empresa. Abrir o detalhe pode mostrar a empresa após requisição adicional.

**B2B/B2C:** para B2B, o nome canônico deveria ser visível sem abrir cada card. Para B2C, `company` deve ser `null`/omitida e o layout não deve deixar uma linha vazia. Um `company_name` legado em `additional_attributes` não deve substituir a relação canônica no card, porque pode estar desatualizado ou representar apenas texto histórico.

**Contrato mínimo recomendado, sem N+1 e sem dado cruzado:**

```json
{
  "contact": {
    "id": 42,
    "name": "Mariana Costa",
    "phone_number": "+55...",
    "company": { "id": 7, "name": "Horizonte Seguros" }
  }
}
```

Quando não houver vínculo, `company: null` (ou ausência documentada). A consulta do board deve carregar a associação no mesmo escopo/autorização da conta e serializar somente `id` e `name`; nada de uma chamada por card. O frontend deve exibir empresa abaixo da pessoa somente quando presente, em Kanban, lista e variante mobile. O filtro/busca por empresa é uma decisão separada e precisa de consulta SQL autorizada, não de filtro client-side sobre dados parciais.

### P1/P2 — Paginação por ID não combina com a ordenação visual por atenção

O backend monta cada coluna com `order(id: :desc)` e cursor por `id` (`app/services/crm/kanban/board_payload_builder.rb:143-153`). O store manda `limit_per_stage: 30` (`app/javascript/dashboard/store/modules/crmKanban.js:479-502`) e depois ordena apenas os cards carregados por `score`, `last_message_at` e `id` (`:170-187`).

Assim, com mais de 30 cards, um card antigo com score alto pode ficar fora da primeira página. A interface parece priorizar “quem precisa de atenção”, mas a seleção inicial ainda é por ID. Isso é uma inconsistência real de contrato; não é apenas opinião visual. Correção mínima: ordenar e paginar no servidor pela mesma chave de prioridade (com desempate estável), ou remover a promessa de ranking global e informar que a ordenação vale só para os cards carregados.

### P1/P2 — Busca não procura pessoa nem empresa

A busca do board filtra somente `LOWER(crm_cards.title)` (`app/services/crm/kanban/board_payload_builder.rb:85-90`). A busca da lista faz o mesmo (`app/services/crm/cards/filter_query.rb:99-104`), e o espelho client-side também compara apenas título (`app/javascript/dashboard/store/modules/crmKanban.js:333-341`). Portanto, digitar nome da pessoa ou empresa não encontra o card, mesmo que a relação exista.

Se isso for requisito do produto, incluir um filtro server-side com joins/preload autorizados para `contact.name` e empresa canônica, respeitando escopo de conta e evitando `LIKE` em dados carregados por card. Testar explicitamente B2B com nome de empresa, pessoa e título distintos.

### P2 — Mover card no board depende de drag; existem alternativas manuais fora dele

`CrmKanbanPage` configura `Draggable` com `:sort=false`; só trata `event.added` e chama `moveCard` (`app/javascript/dashboard/routes/dashboard/crm/pages/CrmKanbanPage.vue:1177-1192, 2335-2359`). O reordenamento dentro da coluna é deliberadamente desativado (`:2335-2337`). Não encontrei ação de mover card para estágio anterior/próximo ou menu de teclado no card. A tabela tem navegação por teclado e grid semântico (`CrmCardsTable.vue:435-513, 570-730`), mas isso não oferece mover o card.

Há uma alternativa manual por clique na **Lista**: a coluna de estágio usa `CrmTableCellEditable`/`ComboBox` e salva a mudança (`app/javascript/dashboard/routes/dashboard/crm/components/list/CrmTableCellEditable.vue:250-273`, `CrmCardsTable.vue:784-799`). A barra de ações em lote também permite escolher o estágio (`CrmBulkActionBar.vue:138-142`). A tela de criação tem `ChoiceSelect` de estágio (`CrmOpportunityForm.vue:378-398`), mas o `CrmCardDrawer` de edição de um card existente não expõe um seletor de estágio no resumo; o `form.stageId` é usado para criação (`CrmCardDrawer.vue:614-633`).

Portanto, o achado é específico: **não há ação direta acessível para mover um card no Kanban**. Não é correto dizer que inexiste alternativa manual no produto. Para UX, tornar “Mover para…” visível no card/detalhe, ou apresentar a Lista como caminho equivalente, reduz a dependência de drag sem duplicar regra de backend.

### P2 — Score 82 não comunica origem e motivo de forma confiável no board

O builder do Kanban envia `score`, mas não envia `metadata` nem um campo de proveniência/motivo (`app/services/crm/kanban/card_payload_builder.rb:28-43`). O componente tenta ler `card.metadata.ai.score.source/reason` (`CrmKanbanCard.vue:135-159`); quando esse bloco não existe, `source` não é `manual`, o ícone cai no tratamento de score automático e `reason` fica vazio. Assim, “82” isolado pode parecer IA, mas o contrato não prova isso e não há motivo contextual no card. O payload completo de cards tem sanitização de metadata por visibilidade (`app/services/crm/cards/payload_builder.rb:292-299`), o que também impede simplesmente expor texto derivado da conversa sem gate.

Para o mockup, usar **“Atenção IA · 82”** somente quando o backend enviar uma origem autorizada; mostrar a razão no detalhe/tooltip com o mesmo gate de visibilidade. Quando a origem não estiver disponível, usar “Atenção · 82” neutro. Score manual deve ser “Atenção manual · 82” e manter o ícone/ARIA de edição humana. A ordenação atual continua válida apenas para cards carregados; isso deve aparecer como limite do fluxo até a paginação usar a mesma chave de prioridade.

### P2 — Estados e filtros existem, mas alguns estados não têm semântica suficiente

Há erro inline quando existe board (`CrmKanbanPage.vue:2238-2258`), spinner (`:2260-2262`), erro com retry (`:2264-2281`) e empty state de funil sem pipelines (`:2283-2301`). A tabela tem loading, vazio filtrado e vazio sem cards (`CrmCardsTable.vue:519-567, 661-675`).

Os filtros usam `ChoiceSelect` próprio, não o select nativo. Os chips de estágio/label/campanha e os botões de alternância Kanban/List/Calendar dependem de classe visual; não têm `aria-pressed`/`aria-selected` explícito (`CrmKanbanPage.vue:1781-1800, 2003-2095`). Isso torna o estado ativo menos claro para tecnologia assistiva. É um achado de acessibilidade, não um bloqueio de dados.

O board desktop usa scroll horizontal e colunas `w-[19rem] shrink-0` (`CrmKanbanPage.vue:2303-2322`); a lista possui tratamento mobile separado (`CrmCardsTable.vue:910-972`). Não há empresa em nenhuma dessas variantes.

### P2/P3 — Contagens têm semânticas diferentes

`cards_count` conta o escopo aberto e filtrado (`BoardPayloadBuilder:32-50`); `total_cards_count` conta todos os status do estágio, inclusive os que não aparecem no board. O header chama ambos de “cards” e só recebe os totais quando `include_counts` está ativo. Essa diferença é útil para exclusão de estágio, mas pode surpreender a pessoa (“0 cards” visualmente e total não zero). Recomendo rotular a contagem exibida como “abertos”/“filtrados” e reservar o total para contexto de edição/exclusão.

### P3 — Detalhe/lista podem ficar defasados e inbox tem duas fontes

`fetchCard`/`updateCard` atualizam o board (`app/javascript/dashboard/store/modules/crmKanban.js:828-848`); não encontrei commit equivalente direto para `cardsList`. Realtime ou refresh pode corrigir, mas sem isso a lista pode continuar com a versão anterior. Trato como risco de consistência, não como regressão comprovada.

O pill de origem do card usa `card.inbox` (`CrmKanbanCard.vue:402-410`; payload compacto em `CardPayloadBuilder:136-144`), enquanto `responsible_descriptor` pode derivar o bot da inbox da conversa primária. Se uma conversa for transferida depois da criação do card, o source pill e o responsável podem divergir. O código não prova que essa divergência ocorre no fluxo atual; vale teste de transferência de inbox.

## Mapa dos dados exibidos

| Conceito | Fonte do payload | Onde aparece | Observação QA |
|---|---|---|---|
| Título da oportunidade/negócio | `crm_cards.title` | topo do card e tabela | Não confundir com nome da pessoa. |
| Pessoa de contato | `contact.name`, fallback telefone | subtítulo do card/tabela | Hoje é o único identificador de contato no board. |
| Empresa | Não serializada no board | somente relacionamento após fetch extra | P1 para B2B. |
| `owner_id` | `card.owner`, separado de `responsible` | responsável/rodapé | Owner humano não é automaticamente quem atende. |
| Responsável | `card.responsible` (`bot`, `agent`, `none`) | avatar e rodapé | Avatar do card representa quem trata o card, não o cliente. |
| Inbox/origem | `card.inbox` (`id`, `name`, `channel_type`) | pill de canal/inbox | É a caixa associada ao card; conversa também tem `inbox_id`. |
| Última mensagem | `last_message_at` epoch | timestamp/botão de conversa | Mostra tempo relativo; não exibe corpo da mensagem. |
| Score/atenção | Board: `card.score`; origem/motivo tentados em `metadata.ai.score.source/reason`, mas metadata não é emitida pelo builder do board | pill com faixa/ícone e tooltip | Hoje o board não prova IA/manual nem tem motivo; “Atenção IA · 82” exige contrato explícito. Score participa do sort carregado. |
| Follow-up | `next_follow_up_at`, `next_follow_up_source` | pill vencido/próximo | Fonte `ai`/`manual` é inferida do estado de cadência e da data. |
| Sugestão IA | `ai_suggestion` pendente | pill “mover para…” | Não é o mesmo que score nem responsável bot. |

As datas vêm como epoch no payload (`CardPayloadBuilder:36-42`) e são convertidas por `timeHelper` no componente (`CrmKanbanCard.vue:169-175`), o que é coerente entre backend e frontend.

## Efeito da PR793 e Enterprise

A mudança `1acd2b1809` concentra-se no drawer de relacionamento/editor e acessibilidade; não altera `CrmKanbanPage`, `BoardPayloadBuilder`, `CardPayloadBuilder` ou `crmKanban.js`. A correção `56b56f3a79` serializa criação de contato entre fluxos de oportunidade e também não altera payload/renderização do board. Logo, ambas melhoram o detalhe e a integridade da criação, mas não resolvem a ausência de empresa no Kanban.

A associação `Contact belongs_to :company` é Enterprise; o CRM OSS deve continuar funcional sem assumir essa coluna/feature. O contrato recomendado deve ser feature-aware e autorizado: em OSS/B2C, `company: null`; em Enterprise/B2B, relação canônica pré-carregada no escopo da conta. O endpoint padrão de contato já expõe `company_id`, mas o builder CRM tem payload próprio e não o repassa.

## QA estático do protótipo local

**Arquivos:** `.codex/kanban-design/prototype/index.html`, `styles.css` e `app.js` (624 linhas). A revisão abaixo é do comportamento implementado no protótipo; não representa defeito confirmado no produto. Não usei navegador/CUA, conforme combinado; a captura e a interação visual ficam com o root. `node --check` não foi possível neste ambiente porque o comando `node` não está instalado.

### P1 — Trocar o funil muda só o cabeçalho, não os dados

O menu oferece “Email Comercial” com 5 etapas/191 oportunidades e “Pós-venda” com 4 etapas/28 (`index.html:101-112`). O listener de seleção apenas troca `#pipeline-name` e `#pipeline-summary` (`app.js:500-505`); não troca `app.cards`, etapas, totais, filtros nem o estado selecionado. O board continua com as cinco etapas e os mesmos cards, mas o cabeçalho passa a dizer Pós-venda. O check visual também continua no primeiro item ao reabrir o menu.

Para a tela ser apresentada como fluxo real, cada funil precisa ter dataset próprio (ou o menu deve ficar explicitamente desabilitado como demonstração). Aceitação: selecionar Pós-venda altera etapas, cards, contagens, vazio, busca e calendário; voltar para Email Comercial restaura o conjunto anterior; a opção ativa mantém check/ARIA coerentes.

### P1 — Contagens e estados filtrados ficam contraditórios

`STAGES.total` é fixo em 23/47/115/6/0 e soma 191 (`app.js:51-55`), enquanto os dez cards sintéticos incluem um card em Perdido. O footer mostra “1 exemplo de 0 no funil” nessa coluna (`app.js:226-232`). Mover um card altera apenas `card.stage`; os totais do cabeçalho/coluna não mudam (`app.js:347-358`). Pesquisa, filtro B2C, empresa ou sem responsável também mantêm “191 oportunidades no funil” (`app.js:252-256`) e os totais de cada etapa, embora a descrição diga quantos exemplos correspondem.

O protótipo deve separar “total no funil” de “visíveis após filtro” e atualizar o total após mover. Para o caso Perdido, decidir se cards fechados ficam no quadro e corrigir o total, ou removê-los do conjunto exibido. Não mostrar número 191 junto de uma tela vazia ou de um recorte B2C.

### P1/P2 — Modelo de empresa do protótipo não coincide com o contrato aprovado

Os fixtures usam `company` no topo do card, enquanto o contrato recomendado é `contact.company` (`app.js:59-68`). `op-3` tem empresa sem contato; o card escreve “Sem contato · Lumen Design” e o topo ainda classifica como “Pessoa · Empresa” (`app.js:199-201, 213-214`). Isso pode ser um caso válido de oportunidade ligada somente à empresa, mas o modelo precisa decidir isso explicitamente; hoje ele não prova o contrato CRM.

Quando não existe empresa, o drawer e a lista escrevem **“Pessoa”** no campo de empresa (`app.js:288, 369-370`), o que parece afirmar que a oportunidade é uma pessoa, não que não há empresa. Usar “Sem empresa” e manter “Pessoa” como tipo de entidade separado. Para empresa sem contato, exibir “Empresa” no tipo, ou não permitir esse estado se o produto exigir contato vinculado.

### P2 — Score null é apresentado como manual; razão nunca existe

`scoreLabel` transforma qualquer origem diferente de `ai` em “manual” (`app.js:162-165`). Vários fixtures têm `scoreSource: null` e score preenchido (`app.js:60, 63-68`), logo 54/32/19/12 aparecem como “Atenção manual” sem afirmação de que foram editados por uma pessoa. Cards sem score usam ícone de faísca e “Atenção ainda não calculada” (`app.js:207-209`), misturando ausência de cálculo com sinal de IA. Não há `reason` no fixture nem no drawer; o texto é genérico (`app.js:369-370`).

Para a apresentação, usar `scoreSource: 'ai' | 'manual' | null` de forma explícita: “Atenção IA · 82”, “Atenção manual · 82” ou “Atenção · 82” neutro quando a origem não existir. Mostrar motivo contextual no detalhe quando autorizado. Se a referência de faixas do produto for mantida, 83 é faixa HOT; o protótipo só aplica classe de destaque a `score >= 84` (`app.js:168-172`), portanto o limiar visual também precisa ser alinhado.

### P2 — Datas do calendário são inconsistentes entre card e coluna

`renderCalendar` cria “Hoje 03 out”, “Amanhã 04 out” e “Sexta 05 out”, mas filtra o card `Sex, 04 out` para a coluna Sexta (`app.js:296-300`). O mesmo item aparece com uma data textual e uma coluna incompatíveis. As datas são strings hardcoded, enquanto cards usam rótulos relativos (“Hoje”, “Amanhã”). Usar uma data ISO sintética única e formatar coluna, card e drawer pelo mesmo relógio-base; caso contrário, usar somente rótulos relativos sem inventar dia da semana.

### P2 — O botão “Nova oportunidade” abre conteúdo de “Novo funil”

`#new-opportunity-button` e o atalho `N` chamam `openConfig('new-pipeline')` (`app.js:563, 610-612`). A ação visível diz “Nova oportunidade”, mas o drawer mostra “Novo funil”. Isso deve ser corrigido antes da captura: ou abrir um formulário de oportunidade, ou renomear a ação para novo funil.

### P2 — Mover por clique/drag funciona localmente; o atalho de teclado é superprometido

O menu “Mover” chama `moveCard` e o drag/drop altera `card.stage` em memória (`app.js:213, 312-358`). Isso cobre o caminho direto que faltava no Kanban. Porém o card tem `tabindex="-1"` e o listener da tecla `M` está no `<article>` (`app.js:213, 328-344`); a navegação Tab chega aos botões internos, não ao artigo, enquanto o aviso diz “Tab navega · M move” (`index.html:203`). Tornar o card alcançável por teclado sem aninhar ações conflitantes, mover o atalho para um botão focável ou remover essa promessa. O protótipo também não atualiza contagens após mover, conforme achado acima.

### P2/P3 — Busca, filtros e acessibilidade precisam de contrato explícito

`activeCards` pesquisa título, contato, empresa, telefone e inbox (`app.js:185-193`), mas nenhum fixture define `phone`; a promessa “nome, empresa ou telefone” não é demonstrável. O filtro “Pessoa” usa `kind === 'b2c'`, não ausência de empresa; isso é uma regra de negócio que precisa ser confirmada para não classificar contato B2B sem vínculo como pessoa (`app.js:189-193`). Os botões do filtro mudam somente a classe `selected` (`app.js:434-440`); não expõem `aria-pressed`/`aria-selected`. O seletor de funil usa menu visual, mas não atualiza seleção quando muda.

Não encontrei `<select>` nativo, regex de interpretação de linguagem nem requests externos no protótipo. O estado de erro/retry também não existe: há loading e empty no HTML, mas o refresh apenas exibe toast (`app.js:550-563`); se o objetivo é validar a tela real, incluir ao menos um estado de falha ou declarar esse cenário fora do escopo.

### P2/P3 — Responsável, empresa e conversa estão simplificados demais para validar semântica

Os fixtures têm apenas `owner` textual e todos usam a mesma inbox; não há `responsible.type` (IA/humano/sem responsável), `conversation`, `last_message_at` ou motivo de follow-up. O protótipo consegue mostrar “Responsável” e “Caixa de entrada”, mas não testa a distinção exigida pelo produto entre owner, bot, humano, origem da inbox, última mensagem, score e follow-up. Para o gate visual, adicionar pelo menos um card com responsável IA, um humano, nenhum responsável e uma conversa sem contato; manter isso separado da empresa.

## Matriz curta de aceitação

| Caso | Resposta esperada |
|---|---|
| B2C: contato sem empresa | Card mostra título + pessoa/telefone; nenhuma linha vazia nem erro. |
| B2B: contato com empresa canônica | Uma resposta do board traz `contact.company.id/name`; card, tabela e mobile mostram o nome sem chamada por card. |
| Texto legado `additional_attributes.company_name`, sem relação | Não apresentar o texto como empresa canônica sem regra explícita; preservar relação nula e evitar dado potencialmente errado. |
| Título diferente da pessoa/empresa | Topo permanece nome da oportunidade; pessoa e empresa aparecem como contexto separado. |
| 31+ cards: score alto em card antigo | O card prioritário precisa estar na página inicial se essa for a promessa; caso contrário, a UI deve declarar que ordena só carregados. |
| Busca por empresa/pessoa | Se habilitada, deve retornar por consulta server-side autorizada, com conta/empresa corretas e sem N+1. |
| Mover card sem mouse | Deve existir ação equivalente (“Mover para…”/setas) ou a lista deve ser explicitamente o fluxo acessível. |
| IA/manual/default | Com contrato de proveniência: “Atenção IA · 82”/“Atenção manual · 82”, motivo no detalhe e ARIA equivalente; sem proveniência, “Atenção · 82” neutro. Follow-up AI/manual aparece separado do responsável bot. |
| Protótipo: troca de funil | O dataset, etapas, contagens, busca, filtros e calendário devem mudar juntos; o cabeçalho não pode mudar sozinho. |
| Protótipo: recorte B2C/empresa | Contagens visíveis e estado vazio refletem o recorte; ausência de empresa aparece como “Sem empresa”, não “Pessoa”. |
| Protótipo: calendário | A mesma data-base determina rótulo relativo, dia da semana e coluna. |

## Limites e gates

- Não rodei produção, conta 18, autenticação externa, banco externo, worker, provider ou chamada paga.
- Não rodei nova bateria pesada; este parecer é revisão estática apoiada nos arquivos e fixtures locais já disponíveis.
- As imagens em `docs/relationships/screenshots/793-review/` são Rails/Vite locais com dados sintéticos; mostram empresa no drawer e não no card, mas não provam deploy ou estado atual.
- Antes de apresentar “empresa no Kanban” como pronto, o gate mínimo é: contrato API com empresa canônica, preload/consulta sem N+1, autorização/Enterprise, renderização desktop/list/mobile e teste B2B/B2C. A decisão de colocar nome da empresa no card é produto/UX; a ausência atual no payload é o bloqueio técnico factual.

## Revisão posterior — protótipo 822

Esta seção é separada dos achados do protótipo anterior, que foi rejeitado. O protótipo novo está em `/Users/rodrigosilva/.codex/worktrees/kanban-design-review/chat2you/docs/crm/kanban-design-822/prototype/`, com datasets sintéticos próprios para Email Comercial e Pós-venda. Não alterei os arquivos nem usei navegador; a captura e a interação visual ficam com o root. O `deno check` de `app.js` passou sem saída.

### O que foi corrigido no protótipo novo

- A troca de funil muda de fato `app.pipelineId`, limpa busca/filtro e renderiza etapas, cards, contagens, estados e calendário do funil escolhido (`app.js:78-83, 248-249`). Não repete o erro histórico de trocar só o título.
- As contagens agora são derivadas dos cards visíveis por estágio (`app.js:125-147`) e o texto de resultados distingue o recorte do total do funil (`:130`).
- A empresa está aninhada no contato (`PEOPLE:36-42`), B2C não inventa empresa e o drawer só mostra “Empresa vinculada” quando há relação (`app.js:95-99, 186-188`).
- Responsável bot/humano/sem responsável, inbox, última mensagem, score com origem/motivo e retorno possuem dados separados (`app.js:55-63, 89-115`).
- Mover por botão, drawer e drag/drop funciona em memória com opção de desfazer (`app.js:190-204, 300-304`). O protótipo não promete persistência e informa dados fictícios.
- Não encontrei `<select>` nativo, regex de interpretação ou chamadas externas; filtros, views e menus usam botões/ARIA próprios (`index.html:48-56`, `app.js:135, 155, 223, 292-299`).

### Achados que ainda impedem tratar o protótipo como contrato final

#### P2 — Ordenação não representa a regra do Kanban de atenção

`matches()` ordena por score decrescente e depois por `id` crescente (`app.js:100-108`). Não usa `lastMessageAt` como desempate e usa a direção oposta ao desempate por ID do store real. Dois cards com score igual podem aparecer em ordem diferente da tela do produto. Se a proposta visual é “atenção primeiro”, alinhar a ordenação com score, última mensagem e ID estável; se for somente demonstração, declarar esse limite.

#### P2 — Follow-up está tipado no dado, mas a UI sempre comunica “manual”

O fixture possui `nextFollowUpSource` (`app.js:60-63`), mas `signal()` fixa o título em “Retorno manual” para qualquer retorno (`:110-115`) e todos os exemplos com data são manuais. Não há cenário visual para retorno criado pela IA nem distinção de origem no card/detalhe. O gate de score/proveniência foi melhorado; o mesmo contrato precisa existir para follow-up: `ai`, `manual` ou ausência, com texto/ícone correspondente.

#### P2 — Critério de “Em atendimento” ainda usa “proposta formal”

O critério do estágio diz “sem proposta formal enviada” (`app.js:44-48`). “Formal” pode ser lido como documento/canal obrigatório e diverge da regra aprovada de que a proposta precisa apenas ter sido efetivamente apresentada, inclusive verbalmente. Usar “sem proposta, orçamento ou condição comercial apresentada” para não induzir a IA ou a equipe a exigir formato não definido.

#### P2 — Foco não volta necessariamente ao acionador correto após fechar drawer

`openDrawer()` guarda o elemento atual, mas `restoreFocus()` procura primeiro qualquer `[data-move="id"]` (`app.js:166-171`). Se o drawer foi aberto pelo título, o foco volta ao botão “Mover”, não ao título. Se foi aberto pela Lista, pode encontrar o botão de mover de um card no board oculto. O comportamento deve guardar o elemento acionador (ou validar que está visível) e restaurá-lo diretamente; isso é importante para o fluxo teclado e para não perder o contexto atual.

#### P2/P3 — A ligação de mais caixas de entrada não é acionável

O menu “Caixas de entrada” lista WhatsApp e Email, mas a tela só renderiza texto e orienta usar “a última etapa do Editar Funil” (`app.js:224, 236-237`). Não há botão para adicionar/remover uma caixa nem confirmação do funil escolhido. Como a capacidade de conectar várias entradas é requisito do CRM, a captura deve mostrar o controle real ou marcar a área como ainda não implementada no protótipo.

#### P3 — Os estados e a semântica geral melhoraram, mas o board ainda depende de estrutura implícita

Loading, vazio e erro existem (`app.js:136-164`); filtros e views expõem `aria-pressed` (`:133-155`) e menus oferecem navegação de setas (`:292-297`). Porém as colunas não têm `role="list"` explícito e os artigos de card não informam estágio, empresa, score ou responsável no nome acessível; o `aria-label` é apenas “Oportunidade {título}” (`:118`). Para o gate de acessibilidade, incluir contexto essencial no nome/descrição acessível ou garantir que cada informação esteja navegável sem depender de ordem visual.

### Matriz curta para a captura 822

| Cenário | Evidência esperada |
|---|---|
| Trocar Email Comercial → Pós-venda | Nome, etapas, cards, total, busca, filtros e calendário mudam juntos; `menuitemradio` mantém `aria-checked` correto. |
| B2B e B2C | Empresa aparece somente em `contact.company`; B2C mostra contato sem inventar “Pessoa” como empresa. |
| Score | IA/manual/null são três estados distintos; motivo aparece no detalhe; score nulo não vira manual. |
| Follow-up | Retorno manual e retorno IA usam origem/ícone/texto diferentes; atrasado usa data consistente. |
| Mover | Botão e drag levam ao status escolhido, foco retorna ao acionador visível, contagem/ordem atualizam e desfazer restaura. |
| Filtro/busca | Nome da oportunidade, pessoa, empresa e telefone sintéticos retornam; contagem reflete o recorte. |
| Empresa/inbox | Empresa canônica não exige request por card; existe caminho claro para adicionar a segunda caixa de entrada. |

O parecer desta seção é sobre o protótipo 822 e não reabre nem invalida as conclusões históricas da implementação do Kanban: o payload real ainda precisa do contrato `contact.company` descrito acima antes de qualquer publicação do produto.

## Atualização final — protótipo 822 após os ajustes de UX

Esta atualização supersede apenas os “achados que ainda impedem” da seção 822 imediatamente anterior; a crítica do protótipo antigo e os limites de integração do produto continuam separados.

**Confirmado corrigido no código atual:**

- Ordenação agora é score decrescente, última mensagem decrescente e ID decrescente (`app.js:103-112`).
- Follow-up distingue `Retorno por IA`, `Retorno manual` e `Retorno agendado`; o exemplo 9 exerce o caminho IA (`app.js:60-63, 91, 113-118`; `:78`).
- O critério de “Em atendimento” passou a dizer “antes de apresentar condições ao cliente”, sem exigir proposta formal/documento (`app.js:44-48`).
- O foco conserva se o acionador era título ou mover e só escolhe um elemento visível ao fechar (`app.js:179-200`).
- O nome acessível do card agora inclui status, identidade, responsável e score (`app.js:120-126`); cards sem valor/sinal não ficam com a faixa vazia (`:121, 125`).
- A navegação horizontal de status tem controles anterior/próximo e atualização após resize/scroll (`index.html:58`, `app.js:159-165, 292-295`).

**Limites que permanecem e devem ser explícitos na captura/documentação:**

- “Editar funil” e “Caixas de entrada” ainda são prévias somente leitura: mostram critérios e duas caixas, mas não permitem alterar status, melhorar descrição com IA, adicionar/remover uma entrada ou salvar associação (`app.js:237-251`). Isso não deve ser apresentado como fluxo implementado.
- O retry do cenário de erro agora volta ao quadro preservando busca e filtros; o refresh também sai de `error/loading` sem zerar esse contexto (`app.js:211, 340, 377`). Isso é comportamento da demo, não prova de reexecução de carga no produto real.
- As colunas usam `role="list"` e os cards `role="listitem"`; a semântica básica desse trecho foi fechada (`app.js:184`).
- Os controles de navegação horizontal têm estado visual para `disabled` (`index.html:58`); ainda dependem da validação visual do root em primeiro/último status.
- Os motivos de score são sintéticos e repetidos para várias oportunidades; isso comprova a hierarquia visual e a origem IA/manual, mas não comprova qualidade ou pertinência do motivo gerado por IA.
- **P3 — A origem do follow-up é parcialmente visível:** o retorno futuro criado por IA aparece com o prefixo “IA”, mas retorno manual, origem desconhecida e qualquer retorno atrasado continuam exibindo texto genérico, deixando a origem completa apenas no `title` (`app.js:95, 127-128`). Também evitar mapear ausência de `nextFollowUpSource` para “Retorno agendado”, pois isso transforma origem desconhecida em uma afirmação de negócio.

### Filtros independentes — atualização final do protótipo 822

- A demo agora mantém filtros independentes de responsável, empresa e retorno atrasado; eles são combinados por `AND`, a contagem do badge soma cada critério ativo e o resultado/stage counts usam o recorte (`app.js:82, 88-90, 106-115, 141-155`). O menu de empresa é customizado com `menuitemradio`; não há `select` nativo (`index.html:56`, `app.js:254-255`).
- O filtro de empresa é demonstrável apenas com os fixtures `Norte Logística`, `Alvorada Tecnologia` e “Sem empresa vinculada” (`app.js:38-41, 89`). A lista é hardcoded, não carregada por conta, permissão ou endpoint. No produto real, o picker precisa receber somente empresas autorizadas no escopo da conta; a busca por empresa também exige contrato de filtro no endpoint de oportunidades, com autorização e paginação/preload definidos. A demo não prova nenhuma dessas garantias.
- **P3 — “Sem empresa vinculada” mistura dois estados:** o predicado `!c.contact?.company` inclui tanto contato existente sem empresa quanto card sem contato (`app.js:102, 113`). O fixture “Indicação recebida na feira” entra nessa opção. Confirmar se a regra do produto é “sem empresa” incluindo oportunidades sem contato ou separar “Sem contato” de “Contato sem empresa”; hoje o rótulo não deixa essa distinção clara.
- A troca de funil limpa responsável, empresa e atraso (`app.js:282`), enquanto `Limpar filtros` também limpa busca e cenário (`app.js:311`); isso é coerente para a demo e deve ser mantido/validado no produto para não preservar IDs de uma conta/funil anterior.

### Prévia “Encontrar com IA” — atualização final

- A prévia usa somente três exemplos determinísticos por ID (`AI_DEMOS`); não interpreta texto humano, não chama provedor e informa explicitamente que a ligação ao GPT-6 Luna ainda será feita (`app.js:284-308`). Campo livre invalida o exemplo, desabilita entendimento/aplicação e limpa a resposta anterior (`app.js:292-294`). Isso é correto para uma prévia e não representa o contrato de produção da IA.
- A sugestão mostra chips e contagem calculados com os mesmos filtros locais e, ao confirmar, substitui responsável/empresa/atraso, limpa a busca, fecha os drawers e devolve foco ao botão de filtros (`app.js:295-307`). Não há alteração de dados nem chamada externa.
- No mobile, o mesmo `filter-panel` é movido para um `dialog` dedicado e devolvido ao contêiner original no fechamento; o drawer de IA fica acima dele e o apply fecha ambos (`index.html:72-78`, `app.js:378-393`). Não encontrei IDs duplicados nem bloqueador estático nesse fluxo.
- O limite para o produto permanece: sugestões por linguagem natural precisam de endpoint/modelo, autorização por conta e uma resposta tipada que não invente empresas. O picker de empresa continua fixo em fixtures; a fonte real precisa ser conta-scoped e autorizada (`app.js:89, 272-282`).

Não há novos bloqueadores de troca de funil, contagem, empresa, score, follow-up, mover, busca ou filtro no estado atual do protótipo. O gate de publicação do produto continua condicionado ao payload real `contact.company`, preload autorizado sem N+1 e integração efetiva dos fluxos de edição de funil e múltiplas caixas.

## Fechamento do integrador após este parecer

- Retry agora conserva busca/filtro; atualizar recupera o cenário simulado de erro/carregamento.
- Colunas/cards expõem list/listitem; status, empresa, responsável e atenção são anunciados.
- Navegação horizontal tem estado visual desabilitado e alcança Perdido integralmente.
- Retorno IA aparece também no chip; o detalhe distingue IA/manual. Origem ausente usa rótulo neutro de retorno com data conhecida, sem afirmar criador.
- Tab foi testado na gaveta, assim como Escape e retorno ao acionador visível no Kanban e na Lista.
- Cards criados sem conversa não inventam horário de última mensagem.

A verificação renderizada é do integrador; o parecer do agente permanece estático.
Editar Funil, múltiplas caixas e configuração são prévias somente leitura no
protótipo. O fluxo completo existente será reutilizado na PR de implementação.
Não houve teste de produção, banco, provider ou persistência API.
