# Protótipos em tela real: automação no CRM (#2499 F6.3/F6.4/F6.5 e #2710)

Três jornadas montadas com os componentes reais do painel, encaixadas nas telas de verdade (o card do funil, a
etapa aberta no "Editar funil" e a linha do tempo do card). Ficam atrás da flag `automacao_no_crm` e leem os dados
de um adaptador falso (`crm/components/automacaoNoCrm/fonteDasAutomacoes.js`), no mesmo formato que a API vai
devolver. Trocar pela API é trocar esse arquivo; as telas não mudam.

O que é real e o que é ensaio:

| Parte | De onde vem hoje |
|---|---|
| Lista "Automações deste card" e o "Parar para este card" | adaptador falso (parar só some da tela) |
| Lista "Automações desta etapa" | adaptador falso (uma regra da etapa e duas automações novas) |
| "Nova automação para esta etapa" | real: abre o editor da Automação livre com o gatilho da etapa já escolhido |
| Reunião no card ganho e a linha na linha do tempo | adaptador falso (15/11 às 10h, marcada em 12/11) |
| Selo "Já é cliente · comprou em 03/11" | aparece no card aberto de quem já é cliente; a data é do ensaio |
| Abrir o card ganho pelo selo | real: procura o card ganho da pessoa na API de hoje (perfil do contato) |

As datas do ensaio são fixas (novembro de 2026) para os prints saírem iguais em qualquer dia.

## Preparar a demo

No M4, de dentro da worktree (kit `bin/demo`, runbook `docs/runbooks/demo-tela-real.md`):

```sh
bin/demo up 2414-telas
bin/demo flag 2414-telas automacao_no_crm
bin/demo seed 2414-telas docs/2414-prototipos/seed_demo.rb
bin/demo tunnel 2414-telas
```

O seed cria o funil "Vendas (demo 2414)", a Maria Souza (já cliente, com um card ganho em 03/11 e um card novo
"Agendou pela página") e o Pedro Lima (card em "Proposta enviada"). O "Nova automação para esta etapa" precisa
também de `automacao_editor` e `automacao_gatilhos` na conta (nascem ligadas no seed; se não, ligar com
`bin/demo flag`).

Estado vazio de qualquer jornada: acrescentar `?demo=vazio` ao endereço do CRM e recarregar.

## Jornada 1 — "Automações deste card" (F6.3)

1. Menu **CRM** → no topo, escolher o funil **Vendas (demo 2414)**.
2. Tocar no card **Pedro Lima** (coluna "Proposta enviada"). O card abre no resumo.
3. Rolar até **Automações deste card**, logo abaixo dos quatro cartões. Aparecem três frases:
   - "Lembrete de proposta — espera até 15/11"
   - "Avisar a equipe se o cliente sumir — espera o cliente responder"
   - "Ligar no dia seguinte — espera até 13/11"
4. Tocar **Parar para este card** na primeira. A linha vira a pergunta "Parar Lembrete de proposta só neste card?"
   com **Sim, parar** e **Voltar** (print da confirmação).
5. Tocar **Sim, parar**. A linha some e aparece "Lembrete de proposta parou neste card. Os outros cards continuam."
6. Vazio: abrir o mesmo card com `?demo=vazio`. Aparece "Nenhuma automação está cuidando deste card agora." e o
   botão **Criar uma automação**, que abre o editor com o gatilho "card entrou na etapa" da etapa do card já escolhido.

Prints: 1440 e 390 nos passos 3, 4, 5 e 6.

## Jornada 2 — "Automações desta etapa" (F6.5 e o aviso da F6.4)

1. Menu **CRM** → funil **Vendas (demo 2414)** → botão de configurar do quadro → **Editar funil**.
2. No resumo do funil, abrir **Etapas** e tocar na etapa **Proposta enviada**.
3. Embaixo do nome, da frase e da cor, a parte **Automações desta etapa** mostra uma lista só:
   - "Ligar no dia seguinte": Quando o card entra → Cria a tarefa "Ligar para o cliente" (regra da etapa, do jeito antigo)
   - "Lembrete de proposta": Quando o card entra → Lembra da proposta 3 dias depois (automação nova)
   - "Avisar a equipe se o cliente sumir" (Desligada): Quando o card sai → Avisa a equipe (automação nova)
4. Embaixo da lista, o botão principal **Nova automação para esta etapa** e o aviso "Arquivar vários cards de uma vez
   não conta como “saiu da etapa”."
5. Tocar **Nova automação para esta etapa**: o editor da Automação abre com o gatilho "card entrou na etapa" de
   **Proposta enviada** já escolhido (print do editor).
6. Voltar e tocar **Alterar** em "Ligar no dia seguinte": abre a tela das ações da etapa (a de hoje). O **Alterar**
   das automações novas abre a lista de Automações no ensaio (amanhã, o editor de cada uma).
7. Vazio: `?demo=vazio` → "Esta etapa ainda não tem automação.", o botão e o aviso.

Prints: 1440 e 390 nos passos 3/4, 5 e 7.

## Jornada 3 — Reunião do cliente que já comprou (#2710)

1. Menu **CRM** → funil **Vendas (demo 2414)**. Na coluna "Novo contato", o card **Maria Souza · Agendou pela
   página** tem o selo **Já é cliente · comprou em 03/11** (print do quadro).
2. Tocar no selo (não no card): abre o card ganho **Plano anual** da Maria. O mesmo selo aparece no topo do card
   novo, se ele for aberto primeiro.
3. No card ganho, a parte **Reunião do cliente** diz "Maria marcou para 15/11 às 10h pelo link do e-mail.", com
   **Ver** (abre a Agenda do card; no ensaio a Agenda ainda não lista essa reunião, que só existe no adaptador).
4. Em **Mais detalhes** → **O que já aconteceu**: a primeira linha é "Maria marcou para 15/11 às 10h pelo link do
   e-mail", feita por "Cliente" (filtro **Reuniões** também mostra).
5. Vazio: com `?demo=vazio`, o selo, a reunião e a linha somem.

Prints: 1440 e 390 nos passos 1, 3 e 4.

## Pendências para a implementação final

- **Bit de flag da Orquestração**: `automacao_no_crm` está na posição 45 (`17592186044416`, `1 << 44`) pela ordem do
  `config/features.yml`, depois da `agente_ferramentas_prontas_premium` (44). O `spec/models/account_spec.rb` cita o
  bit. A Orquestração confirma na fila.
- **API**: as funções do adaptador (`automacoesDoCard`, `pararNoCard`, `automacoesDaEtapa`, `reuniaoDoCard`,
  `atividadesDoCard`, `jaCliente`, `cardGanho`) viram endpoints; o evento da linha do tempo já tem nome e texto
  (`booking_client_booked_from_email`, com `labels.contact_name` e `payload.starts_at`).
- **Guia**: nenhuma rota nova, então não precisa de `guia:build`, de formatos nem de `porques.md`/`central:check`
  neste protótipo. Quando a F6.5 virar tela final, revisar o bloco da etapa em `lib/operator_guide/porques.md`.
