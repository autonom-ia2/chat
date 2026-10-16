# Teste de estresse do multifunil — 16/10/2026

Épico #1140. Teste com IA de verdade (Jev da Typesafe e os modelos da OpenAI que o sistema usa), num chat2you de
teste local, com a estrutura das contas piloto 16 e 18. Conversas sintéticas de corretora de seguros, nomes fictícios.

## Resumo

1. **Fase A (main + #1687 + #1674): 108 de 147 execuções passaram (73%).** A IA de movimentação acerta quase tudo
   (96%). A IA de assunto acerta 85% e erra sempre do mesmo jeito: uma mensagem com dois ou três assuntos vira um só.
2. **Fase B (o mesmo + #1700, head 52f97c3459): 132 de 147 (90%).** Os cenários de vários assuntos passaram de 0–20%
   para 80–100%. IA de assunto 96%, movimentação 98%.
3. **Ficaram 5 falhas, todas repetidas nas 3 rodadas (nenhum resultado mudou entre rodadas):** o nome do funil
   ("Auto e Residencial") faz a IA recusar seguro de vida (3 conversas; na Fase B a dúvida derruba também o outro assunto da mensagem); na Fase B, o pedido de atendente se perde
   quando a IA o põe no card que não é o principal (regressão nova); e o cliente com card ganho que volta por outro
   assunto deixa um card vazio no funil padrão.
4. **Custo total registrado pelo sistema: US$ 0,955** de US$ 3,00 (Fase A e ajustes do harness US$ 0,57; Fase B
   US$ 0,40). Por mensagem do cliente: cerca de US$ 0,001 na IA de assunto e US$ 0,0007 na de movimentação.
5. **Corrigir primeiro:** o pedido de atendente na avaliação conjunta (#1700, código) e o filtro pelo nome do funil
   (prompt/regra). Depois o card vazio do cliente que volta (código).

## Como foi feito

- **Onde:** M2, snapshot do MacCluster
  `/Users/Shared/maccluster-workspaces/chat2you/20261016-052100-b6c59773-a6900788ad-7818e594` (réplica no M2 e no
  M4), banco próprio `chatwoot_stress` no Postgres de teste do M2 (127.0.0.1:55432) e Redis db 11. O
  `chatwoot_test` compartilhado não foi tocado. Produção não foi tocada (só o export de configuração, lido pela
  Orquestração).
- **Código.** Fase A: `origin/main` (86a176ca1d) + #1687 + #1674, mesclados só na máquina. Fase B: o mesmo + #1700
  no head 52f97c3459, com a migration `20261105163000` aplicada no banco de teste. Flag `crm_avaliar_toda_mensagem`
  ligada em todas as contas do teste.
- **IA de verdade, o resto parado.** O harness (`script/stress/multifunil/`) roda o Rails em ambiente de teste com
  o adaptador `:test` do ActiveJob e executa, na ordem do horário agendado, só os jobs do coração do multifunil:
  o evento de mensagem (só para o `Crm::ConversationObserverListener`), `Crm::SyncConversationCardJob`,
  `Crm::Subjects::IdentifyJob`, `Crm::Ai::EvaluateCardJob` e, na Fase B, `Crm::Ai::EvaluateCardsJob`. Webhook,
  notificação, envio ao cliente e follow-up são descartados e contados. Um relógio virtual faz passar as esperas
  (15 s do assunto, 15 s da avaliação, dias entre mensagens) sem esperar de verdade.
- **Uma conta nova por conversa**, montada a partir de `fixtures/estrutura.json`. Atendentes "online" ficam
  sempre online (o batimento de 20 s venceria com o relógio virtual).
- **Esperado escrito antes.** Cada conversa de `fixtures/conversas.json` diz o que o produto deve fazer e qual falha
  ela pega. Hard-assert: qualquer diferença é FALHA; job com erro, decisão de assunto `failed` e avaliação `failed`
  (inclusive timeout) também. Cada conversa rodou **3 vezes** em cada fase, para medir a variação da IA.
- **Custo** somado de `crm_ai_usage_events` (o que o próprio sistema grava por chamada), conferido antes de cada
  conversa; o harness para antes de passar do teto da fase e de US$ 2,90 no total.
- **Agentes de IA (Fase 2) desligados** nas contas do teste: aqui se mede só o CRM. Com a Fase 2 ligada, a IA de
  assunto vai para a fila rápida (3 s) e troca o dono em linha; isso não foi exercitado.

### Espelho das contas 16 e 18

Lido em 16/10 por export só de configuração (sem dado de cliente; arquivo apagado do disco depois do uso).

Igual à produção:
- as etapas e os critérios de cada funil, com o texto exato: Novo, Em atendimento, Proposta, Fechamento, Perdido
  (funis de venda das contas 16 e 18) e Novo pedido, Em atendimento, Esperando o cliente, Resolvido (Suporte da 16);
- a IA do funil: ligada, mover sozinho, retorno combinado, nota, extração de campos, follow-up;
- a regra de Atribuição: rodízio na caixa, `r2_direct`, só para quem está online, com o gatilho de texto da
  produção ("Quando o agente informar que irá transferir... ou quando o usuário pedir para falar com um humano");
  e um funil sem regra (como o RC Médico da 18);
- caixa de WhatsApp que cria card ao chegar, caixa de e-mail que não cria;
- os campos personalizados da conta 16 (CPF, Cidade, UF, CEP, CNPJ).

Montado por cima, porque a produção não tem e os cenários precisam:
- **2 e 3 funis na mesma caixa.** Na produção cada caixa tem um funil (a 16 tem um segundo arquivado);
- **IA de assunto em Automática.** Na produção está desligada em todas as caixas; fica em Automática depois do SQL do #1676;
- **regra de Atribuição no funil de Sinistro** (o Suporte da produção não tem) e **quem cuida de cada funil**
  (Ana: Vendas e Renovação; Bruno: Sinistro). A produção não usa acesso por funil nem agentes de IA por funil;
- nomes de corretora nos funis ("Vendas: Auto e Residencial", "Pós-venda / Sinistro", "Renovação") e nas caixas
  ("WhatsApp 1", "E-mail 1");
- **observação:** os funis de venda da produção não têm "quando usar" preenchido (o Suporte tem). A IA de assunto
  decide com o nome e a descrição do funil, e isso pesou (ver causa 2).

Antes do export chegar, rodou uma vez uma estrutura modelada por mim (rascunho A0, 46 conversas, 31 passaram).
Ela tinha uma etapa "Ganho" com critério que se sobrepunha a "Fechamento"; o achado dela está na causa 5.

## Resultado

### Taxa de acerto

| IA | Fase A | Fase B |
|---|---|---|
| IA de assunto (cards criados e nomeados, foco, nenhum card a mais) | 345/405 (85%) | 390/405 (96%) |
| IA de movimentação (etapa, atendente, retorno, valor, campos) | 291/303 (96%) | 297/303 (98%) |
| Conversas (execuções) que passaram inteiras | 108/147 (73%) | 132/147 (90%) |

| Cenário | Fase A | Fase B |
|---|---|---|
| 1. 1 funil, 2 cards, mensagem sobre um deles | 18/18 | 18/18 |
| 2. 1 funil, dois assuntos numa mensagem | 3/15 | 12/15 |
| 3. 2 funis, mensagem sobre o outro funil | 15/15 | 15/15 |
| 4. 3 assuntos em 3 funis numa mensagem | 0/12 | 12/12 |
| 5. Mensagem sem assunto | 12/12 | 12/12 |
| 6. Dois assuntos + pedido de atendente | 0/9 | 3/9 |
| 7. Mesmo assunto até "quero contratar" (+ retorno combinado) | 15/18 | 15/18 |
| 8. Cliente com card ganho volta com pedido novo | 9/12 | 9/12 |
| 9. Parece um assunto e é outro | 12/12 | 12/12 |
| 10. Pedido de atendente com e sem regra; ninguém online | 15/15 | 15/15 |
| 11. Mesmo card no WhatsApp e no e-mail (pedido do coordenador) | 9/9 | 9/9 |

Nenhuma conversa mudou de resultado entre as 3 rodadas, nas duas fases: as falhas são de regra ou de código, não
de sorte.

### O que passou e vale registrar

- **Foco** troca para o card certo do mesmo funil (C01, C03, C06), mesmo com texto de áudio e rajada, e não troca
  quando a mensagem cita "casa" de um parente (C04).
- **Falso positivo** resistiu: dúvida de cobertura não virou sinistro (C38), "carro reserva" ficou no sinistro (C39),
  o assalto do vizinho não abriu sinistro (C40), ironia ("baratíssimo 🙄") não moveu para Perdido (C41).
- **"Obrigado", emoji e "alguém aí?"** não criaram assunto nem moveram card (C05, C21–C24, C37).
- **Valor:** "100 mil de incêndio" não virou valor do negócio (C07). **Campos:** cidade e CEP foram gravados no
  contato (C28). **Retorno:** "me liga amanhã às 15h que eu fecho" virou retorno marcado e não Fechamento (C33).
- **Atribuição:** pedido claro e indireto vai para quem está online (C42, C45), ninguém online segura a conversa
  (C43), sem regra ninguém é atribuído (C44) e elogiar a atendente não é pedido (C46).
- **Outro canal:** a proposta assinada que chega por e-mail move o card do WhatsApp; "conforme conversamos no
  WhatsApp, pode fechar" move o card certo (C47–C49).

## Falhas por causa raiz

Ordem: impacto. Cada causa com um exemplo (texto sintético, o que a IA decidiu e por que está errado).

### 1. Uma mensagem, um assunto só (Fase A) — corrigido pelo #1700

Cenários 2, 4 e 6: 21 conversas × 3 rodadas na Fase A. A IA de assunto escolhe uma opção por mensagem, e a IA de
movimentação só avalia o card em foco.

- **C07**, cliente com o auto em Proposta: "fecha o auto e quero cotação do residencial de 100 mil de incêndio".
  Fase A: criou "Seguro residencial" e pôs o foco nele; o auto ficou em Proposta (não foi avaliado, porque deixou de
  ser o assunto atual). Errado: o cliente fechou o auto. Fase B: o auto vai para Fechamento e nasce o residencial.
- **C17**, 3 funis: "Preciso de três coisas: cotar seguro pro meu carro novo, abrir sinistro da batida que tive
  ontem com a moto e renovar o seguro residencial que vence dia 30." Fase A: o modelo maior ficou em dúvida ("reúne
  cotação, abertura de sinistro e renovação, sem indicar qual pedido deve ser priorizado") e nada mudou; sobrou só o
  card sem nome que a caixa cria. Fase B: 3 cards, um em cada funil, nas 3 rodadas.

### 2. O nome do funil vira filtro: seguro de vida é recusado (Fases A e B) — prompt e regra

C09, C27 e C32, 3/3 rodadas nas duas fases. Com um único funil de venda chamado "Vendas: Auto e Residencial", o
modelo maior se recusa a pôr seguro de vida nele e responde "dúvida": nenhum card ganha assunto.

- **C32**, caixa com Vendas, Sinistro e Renovação: "oi, quero fazer um seguro de vida" → "tenho 38, queria uns 300
  mil" → "fechado, quero contratar". As três decisões: dúvida, "o funil de vendas disponível contempla apenas auto e
  residencial". O card ficou com o nome da cliente. A IA de movimentação levou esse card até Fechamento, certo, mas o
  CRM fica com um card sem assunto.
- **C09** (1 funil): "quero fazer um seguro de vida pra mim e pro meu marido. ah, e o do carro pode fechar sim" →
  o auto vai para Fechamento, o pedido de vida some ("o funil disponível não contempla vida").

- **C27**, rajada "me passa pra um atendente" / "é pra cotar seguro de vida" / "e tb abrir um sinistro do celular q
  foi roubado". Fase A: nasce o card "Sinistro de celular roubado" (o vida se perde). Fase B: dúvida para a mensagem
  inteira ("São dois pedidos, mas a cotação de seguro de vida não se enquadra claramente no funil de Auto e
  Residencial") e **nem o sinistro nasce**. No #1700, um assunto em dúvida derruba os outros da mesma mensagem.

Por que importa: na produção os funis de venda **não têm "quando usar"**, e os nomes são estreitos ("Viagem",
"RC Médico"). Um cliente da Placement que peça outro produto vai cair nesse buraco. Se a única saída é um funil,
"dúvida" não ajuda ninguém.

### 3. Pedido de atendente perdido na avaliação conjunta (só Fase B) — código do #1700, regressão

C26, 3/3 rodadas: "preciso falar com uma pessoa. é sobre o sinistro do meu carro (bateram) e quero cotar
residencial tb". Fase A: Ana (Vendas) recebe. Fase B: os dois cards nascem certos, mas **ninguém é atribuído**.

O log confirma: `[crm][avaliacao_conjunta] pedido de atendente fora do principal card=<sinistro>` e, no card
principal (Vendas), `[crm][handoff] ... desfecho=skipped motivo=not_requested`. A chamada conjunta devolve o pedido
de atendente dentro da resposta de UM card. Se ele cai num card que não é o principal, o #1700 só registra no log e
descarta. O pedido de pessoa é da mensagem, não de um card.

### 4. Card vazio quando o cliente com card ganho volta por outro assunto (Fases A e B) — código

C36, 3/3 nas duas fases: card "Seguro do Tracker" ganho há 60 dias; o cliente volta: "roubaram meu carro hoje de
madrugada 😭 o que eu faço?". O sinistro nasce certo ("Sinistro por roubo do Tracker"), mas sobra também um card
"Carla Siqueira" (o nome da cliente) no funil Vendas. Causa: a caixa cria card ao chegar (`CardSyncer`), porque o
cliente não tem card aberto, no funil padrão; a IA de assunto decide depois e cria outro em vez de usar ou mover
esse. O card vazio fica no Kanban de Vendas e conta como lead.

### 5. Critério de etapa sobreposto + "toda mensagem avalia" (rascunho A0) — regra de configuração

Só na estrutura modelada (antes do espelho), C04 e C05: o card estava em Fechamento e o histórico tinha "pode
seguir com o do carro, gostei". O cliente manda "valeu, obrigada pela ajuda de sempre 🙏" e o card vai para Ganho:
"A cliente disse 'pode seguir com o do carro, gostei', confirmando que quer contratar". Com a flag
`crm_avaliar_toda_mensagem`, qualquer mensagem relê o histórico inteiro; se dois critérios de etapa se sobrepõem, um
"obrigado" basta para mover. Os critérios da produção (sem etapa Ganho, Fechamento = "conversão iminente ou
concluída") não têm esse problema; vale como cuidado ao escrever critério.

### Pergunta de produto (não é falha da IA): no cenário 6, qual regra vale?

Hoje vale a regra do funil do **card principal** (o foco). Resultado medido, igual nas 3 rodadas:

| Conversa | Fase A | Fase B |
|---|---|---|
| C25 "cotar o seguro da minha casa e também abrir um sinistro do carro... me passa pra alguém" | Ana (Vendas) | Bruno (Sinistro) |
| C26 "preciso falar com uma pessoa. é sobre o sinistro... e quero cotar residencial" | Ana (Vendas) | ninguém (causa 3) |
| C27 rajada "me passa pra um atendente" / vida / sinistro do celular | Bruno (Sinistro) | Ana (Vendas) |

Quem recebe depende de qual assunto a IA escolheu como principal, e isso muda de A para B na mesma frase. Falta uma
regra: por exemplo, "sinistro antes de venda", "o primeiro pedido citado" ou "quem cuida de mais de um assunto".

## Custo e latência

Custo registrado pelo sistema (`crm_ai_usage_events`, preço de tabela do `Crm::Ai::Pricing`):

| | Fase A | Fase B |
|---|---|---|
| IA de assunto (Jev + revisão pelo modelo maior) | US$ 0,2015 (300 chamadas) | US$ 0,2420 (295 chamadas) |
| IA de movimentação (avaliação do card) | US$ 0,1354 (270 chamadas) | US$ 0,1410 (272 chamadas) |
| Por mensagem do cliente, IA de assunto | US$ 0,00105 | US$ 0,00126 |
| Por mensagem do cliente, IA de movimentação | US$ 0,00070 | US$ 0,00073 |
| Latência média por mensagem (assunto / movimentação) | 2,4 s / 13,8 s | 2,4 s / 12,4 s |
| Pior latência da movimentação numa mensagem | 44 s | 43 s |

- O Jev custa quase nada (US$ 0,00003 por pergunta); quase todo o custo de assunto é o modelo maior, chamado em
  56% das mensagens na Fase A (108 de 192) e 54% na B (103 de 192): sempre que há pedido novo ou dúvida.
- A Fase B custa ~20% a mais na IA de assunto (o modelo maior responde a lista de assuntos) e o mesmo na
  movimentação: uma chamada conjunta por mensagem em vez de uma por card (na Fase B, 66 avaliações foram de 2 ou 3
  cards numa chamada só).
- Gasto total: **US$ 0,955** (FUMAÇA e validações do harness US$ 0,03; rascunho A0 e uma rodada interrompida
  US$ 0,20; Fase A US$ 0,34; Fase B US$ 0,38; diagnóstico da causa 3 US$ 0,004). A Fase A inteira ficou em US$ 0,57,
  abaixo do teto de US$ 1,20.

## O que corrigir, em ordem de impacto

**Código**
1. #1700: o pedido de atendente é da mensagem. Na avaliação conjunta, se qualquer card devolve "transferir", passar
   pela regra do principal (ou decidir pela regra de produto do cenário 6), em vez de descartar. Teste: C26.
2. Card vazio do cliente que volta (causa 4): quando a IA de assunto decide um pedido novo e a conversa tem um card
   sem nome criado na chegada, usar esse card (renomear e mover de funil, como já faz o "card do aviso" do #1638)
   em vez de criar outro. Teste: C36.

**Prompt**
3. IA de assunto (Question/Reviewer): o nome do funil não é lista fechada. Com um funil só de venda, ou quando
   nenhum funil descreve o pedido, escolher o funil mais próximo em vez de "dúvida". Teste: C09, C27, C32.
4. #1700 (Reviewer de vários assuntos): a dúvida vale por assunto, não pela mensagem; os assuntos claros seguem.
   Teste: C27.

**Regra de produto e configuração**
5. Definir qual regra de Atribuição vale quando uma mensagem tem dois assuntos e um pedido de pessoa (cenário 6).
6. Preencher "quando usar" dos funis de venda nas contas 16 e 18 antes de ligar a IA de assunto (hoje vazio).
7. Ao escrever critério de etapa, não deixar duas etapas aceitarem a mesma frase (causa 5), porque com
   `crm_avaliar_toda_mensagem` toda mensagem relê o histórico.
8. Etapa "ganha" não fecha o card: mover para a etapa de ganho deixa o card aberto (status `open`), e ele segue
   como assunto atual. Na produção não existe etapa de ganho; vale decidir se Fechamento deve fechar o card.

## Diferença entre a Fase A e a Fase B

- **Melhorou:** cenário 2 de 3/15 para 12/15, cenário 4 de 0/12 para 12/12, cenário 6 de 0/9 para 3/9. IA de
  assunto de 85% para 96%.
- **Piorou (checagens que passavam na A e falham na B, nas 3 rodadas):** o atendente do C26 (causa 3) e o card de
  sinistro do C27 (um assunto em dúvida derruba os outros, causa 2). No C25 e no C27 a pessoa que recebe mudou
  (Ana ↔ Bruno), porque o principal escolhido mudou.
- **Igual:** nome do funil (causa 2) e card vazio (causa 4) não são do escopo do #1700.
- **Custo:** +20% na IA de assunto, igual na movimentação, latência igual.

## Tabela por conversa

Esperado escrito antes de rodar; "obtido" só mostra o que diferiu do esperado (todas as 3 rodadas juntas).
Latência e custo são médias por mensagem e por execução.

| Conversa | Cen. | Variação | Esperado | Obtido Fase A | Fase A | Obtido Fase B | Fase B | Latência por msg s (assunto / mov.) A → B | Custo médio US$ A → B |
|---|---|---|---|---|---|---|---|---|---|
| C01 | 1 | informal | foco,resid; sem_card_novo; etapa,resid,proposta; etapa,auto,fechamento | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.5 / 9.4 → 0.5 / 10.8 | 0.0005 → 0.0006 |
| C02 | 1 | erro de digitação | sem_card_novo; etapa,auto,fechamento; etapa,resid,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 20.0 → 0.5 / 23.0 | 0.0011 → 0.0012 |
| C03 | 1 | áudio transcrito | foco,resid; sem_card_novo; etapa,resid,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 1.4 / 12.4 → 2.3 / 10.7 | 0.0013 → 0.0021 |
| C04 | 1 | mensagem longa | foco,auto; sem_card_novo; etapa,auto,fechamento | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 13.0 → 0.4 / 10.7 | 0.0007 → 0.0006 |
| C05 | 1 | obrigado | foco,auto; sem_card_novo; etapa,auto,fechamento; etapa,resid,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 2.2 / 9.4 → 2.9 / 0.0 | 0.0017 → 0.0014 |
| C06 | 1 | rajada de 3 mensagens | foco,resid; sem_card_novo; etapa,resid,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.6 / 9.3 → 0.6 / 10.4 | 0.0006 → 0.0006 |
| C07 | 2 | frase base | card_novo,vendas,título~resid,casa,incend,lar,imovel,apart; etapa,auto,fechamento; valor,vendas,título~resid,casa,incend,lar,imovel,apart,nao:10000000 | etapa: proposta | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 3.7 / 15.5 → 3.5 / 19.3 | 0.0024 → 0.0033 |
| C08 | 2 | informal | card_novo,vendas,título~resid,casa,lar,imovel; etapa,auto,fechamento | etapa: proposta | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 3.6 / 10.2 → 3.4 / 18.5 | 0.0021 → 0.0032 |
| C09 | 2 | ordem invertida | card_novo,vendas,título~vida; etapa,auto,fechamento | card_novo:  | FALHOU 0/3 | card_novo:  | FALHOU 0/3 | 7.9 / 14.6 → 7.9 / 12.9 | 0.0043 → 0.0046 |
| C10 | 2 | rajada de 3 mensagens | card_novo,vendas,título~resid,apart,apto,casa,imovel; etapa,auto,fechamento | etapa: proposta | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 3.3 / 15.3 → 4.0 / 20.7 | 0.0024 → 0.0035 |
| C11 | 2 | mudança de ideia | card_novo,vendas,título~resid,casa,lar,imovel; etapa,auto,proposta; status,auto,open | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.4 / 9.8 → 3.8 / 19.1 | 0.0021 → 0.0032 |
| C12 | 3 | frase base | card_novo,sinistro,título~moto,batida,colis,sinistro,traseira; foco,sinistro; etapa,auto,proposta; cards_abertos,2 | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.1 / 11.7 → 3.2 / 9.2 | 0.0024 → 0.0027 |
| C13 | 3 | informal com erro | card_novo,sinistro,título~moto,batida,colis,sinistro; foco,sinistro; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.8 / 11.1 → 4.0 / 9.4 | 0.0023 → 0.0027 |
| C14 | 3 | áudio transcrito | card_novo,sinistro,título~roubo,furto,casa,resid,arromb,sinistro; foco,sinistro; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.7 / 12.9 → 3.4 / 13.3 | 0.0024 → 0.0030 |
| C15 | 3 | pergunta que cabe em dois funis | card_novo,vendas,título~resid,renov,casa; novos_no_funil,sinistro,0 | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 4.1 / 10.8 → 4.5 / 13.0 | 0.0024 → 0.0031 |
| C16 | 3 | cliente volta dias depois | sem_card_novo; foco,auto; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 7.3 → 0.5 / 7.0 | 0.0004 → 0.0005 |
| C17 | 4 | frase base | card_novo,vendas,título~carro,auto; card_novo,sinistro,título~moto,batida,colis,sinistro; card_novo,renovacao,título~resid,casa,renov; cards_abertos,3 | card_novo: vendas: Marcelo Antunes; cards_abertos: 1 | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 4.7 / 13.0 → 3.9 / 16.9 | 0.0031 → 0.0036 |
| C18 | 4 | rajada em lista | card_novo,vendas,título~carro,auto; card_novo,sinistro,título~moto,batida,colis,sinistro; card_novo,renovacao,título~resid,casa,renov; cards_abertos,3 | card_novo: vendas: Aline Ferraz,renovacao: Renovação do seguro residencial; cards_abertos: 2 | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 3.5 / 15.5 → 4.2 / 18.1 | 0.0024 → 0.0037 |
| C19 | 4 | mensagem longa | card_novo,vendas,título~renegade,carro,auto; card_novo,sinistro,título~moto,fazer,batida,colis,sinistro; card_novo,renovacao,título~resid,apart,renov; cards_abertos,3 | card_novo: vendas: Eduardo Nogueira,renovacao: Renovação do seguro residencial; cards_abertos: 2 | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 4.0 / 17.1 → 4.0 / 22.2 | 0.0029 → 0.0042 |
| C20 | 4 | áudio transcrito | card_novo,vendas,título~onix,carro,auto; card_novo,sinistro,título~geladeira,eletric,danos,sinistro; card_novo,renovacao,título~resid,casa,renov; cards_abertos,3 | card_novo: vendas: Sônia Barreto,sinistro: Sinistro de dano elétrico; cards_abertos: 2; card_novo: vendas: Sônia Barreto,sinistro: Sinistro de danos elétricos | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 4.1 / 12.2 → 3.5 / 22.2 | 0.0027 → 0.0041 |
| C21 | 5 | saudação | nenhum_assunto_novo; atendente,ninguem | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 5.6 → 0.4 / 5.3 | 0.0003 → 0.0003 |
| C22 | 5 | obrigado | sem_card_novo; foco,sin; etapa,sin,analise | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.1 / 9.8 → 1.4 / 0.0 | 0.0021 → 0.0007 |
| C23 | 5 | emoji sozinho | sem_card_novo; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.2 / 8.3 → 4.4 / 0.0 | 0.0021 → 0.0024 |
| C24 | 5 | alguém aí | nenhum_assunto_novo | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 5.7 → 0.4 / 5.2 | 0.0003 → 0.0004 |
| C25 | 6 | frase base | card_novo,vendas,título~casa,resid,lar; card_novo,sinistro,título~carro,batida,colis,sinistro,auto; atendente,atribuido | card_novo: vendas: Paulo Henrique Dias | FALHOU 0/3 | igual ao esperado | PASSOU 3/3 | 5.5 / 30.8 → 3.6 / 37.9 | 0.0040 → 0.0040 |
| C26 | 6 | informal, pedido primeiro | card_novo,vendas,título~resid,casa,lar; card_novo,sinistro,título~carro,batida,colis,sinistro,auto; atendente,atribuido | card_novo: vendas: Larissa Melo | FALHOU 0/3 | atendente: estado:ninguem | FALHOU 0/3 | 5.4 / 29.6 → 3.7 / 14.3 | 0.0038 → 0.0031 |
| C27 | 6 | rajada de 3 mensagens | card_novo,vendas,título~vida; card_novo,sinistro,título~celular,roubo,furto,sinistro; atendente,atribuido | card_novo: vendas: Mateus Queiroz,sinistro: Sinistro de celular roubado | FALHOU 0/3 | card_novo: vendas: Mateus Queiroz | FALHOU 0/3 | 3.6 / 32.2 → 7.4 / 28.5 | 0.0033 → 0.0050 |
| C28 | 7 | frase base | card_novo,vendas,título~onix,carro,auto; novos_no_funil,vendas,1; etapa,vendas,título~onix,carro,auto,fechamento; campo,contato:true,chave:cidade,contem:campinas; campo,contato:true,chave:cep,contem:13087 | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 1.2 / 13.1 → 1.2 / 12.1 | 0.0043 → 0.0048 |
| C29 | 7 | informal com erros | card_novo,vendas,título~gol,carro,auto; novos_no_funil,vendas,1; etapa,vendas,título~gol,carro,auto,fechamento | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 1.2 / 12.2 → 1.1 / 11.5 | 0.0042 → 0.0046 |
| C30 | 7 | volta dias depois para fechar | card_novo,vendas,título~moto,cg; novos_no_funil,vendas,1; etapa,vendas,título~moto,cg,fechamento | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 1.3 / 12.4 → 1.4 / 10.1 | 0.0035 → 0.0038 |
| C31 | 7 | ironia e mudança de ideia | card_novo,vendas,título~corolla,carro,auto; novos_no_funil,vendas,1; etapa,vendas,título~corolla,carro,auto,fechamento | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 1.0 / 13.4 → 1.2 / 10.5 | 0.0043 → 0.0046 |
| C32 | 7 | três funis, vida | card_novo,vendas,título~vida; novos_no_funil,vendas,1; novos_no_funil,sinistro,0; novos_no_funil,renovacao,0; etapa,vendas,título~vida,fechamento | card_novo: vendas: Daniela Moraes; etapa: card não existe | FALHOU 0/3 | card_novo: vendas: Daniela Moraes; etapa: card não existe | FALHOU 0/3 | 5.1 / 12.0 → 4.9 / 10.4 | 0.0098 → 0.0104 |
| C33 | 7 | retorno combinado | card_novo,vendas,título~renegade,carro,auto; etapa,vendas,título~renegade,carro,auto,proposta,fechamento; retorno,vendas,título~renegade,carro,auto,true | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 1.4 / 18.9 → 1.4 / 14.1 | 0.0042 → 0.0045 |
| C34 | 8 | frase base | card_novo,vendas,título~casa,resid,lar; status,auto,won; cards_abertos,1 | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 2.9 / 7.1 → 3.1 / 6.0 | 0.0018 → 0.0023 |
| C35 | 8 | informal | card_novo,vendas,título~moto; status,auto,won; cards_abertos,1 | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.5 / 8.1 → 3.9 / 6.7 | 0.0020 → 0.0025 |
| C36 | 8 | volta com sinistro | card_novo,sinistro,título~roubo,furto,carro,tracker,sinistro; status,auto,won; novos_no_funil,vendas,0 | novos_no_funil: 1 | FALHOU 0/3 | novos_no_funil: 1 | FALHOU 0/3 | 3.4 / 7.6 → 3.3 / 8.8 | 0.0020 → 0.0025 |
| C37 | 8 | obrigado depois do ganho | nenhum_assunto_novo; status,auto,won | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 22.1 → 0.4 / 13.8 | 0.0010 → 0.0008 |
| C38 | 9 | dúvida de cobertura parece sinistro | sem_card_novo; foco,auto; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 9.4 → 0.4 / 6.9 | 0.0005 → 0.0005 |
| C39 | 9 | carro reserva dentro do sinistro | sem_card_novo; foco,sin | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 11.7 → 0.4 / 9.3 | 0.0006 → 0.0006 |
| C40 | 9 | assalto do vizinho | sem_card_novo; foco,resid; novos_no_funil,sinistro,0 | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 20.1 → 0.5 / 14.2 | 0.0010 → 0.0009 |
| C41 | 9 | ironia | sem_card_novo; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.5 / 6.9 → 0.6 / 6.6 | 0.0004 → 0.0004 |
| C42 | 10 | com regra, alguém online | atendente,atribuido,pessoa:ana; sem_card_novo | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.5 / 17.0 → 3.4 / 15.4 | 0.0025 → 0.0029 |
| C43 | 10 | com regra, ninguém online | atendente,segurando | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.5 / 9.6 → 3.6 / 6.5 | 0.0021 → 0.0026 |
| C44 | 10 | sem regra | atendente,ninguem | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 3.4 / 12.6 → 3.7 / 8.0 | 0.0022 → 0.0025 |
| C45 | 10 | pedido indireto | atendente,atribuido,pessoa:ana | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 2.9 / 24.8 → 3.0 / 14.9 | 0.0027 → 0.0029 |
| C46 | 10 | elogio citando a atendente | atendente,ninguem; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 4.5 / 11.1 → 4.9 / 9.6 | 0.0021 → 0.0030 |
| C47 | 11 | WhatsApp + e-mail: proposta assinada por e-mail | sem_card_novo; etapa,auto,fechamento | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.4 / 16.2 → 0.5 / 13.4 | 0.0009 → 0.0009 |
| C48 | 11 | WhatsApp + e-mail: 'conforme conversamos' | sem_card_novo; etapa,resid,fechamento; etapa,auto,atendimento | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 4.3 / 18.1 → 0.4 / 14.5 | 0.0028 → 0.0010 |
| C49 | 11 | WhatsApp + e-mail: documentos do sinistro | sem_card_novo; etapa,sin,analise; etapa,auto,proposta | igual ao esperado | PASSOU 3/3 | igual ao esperado | PASSOU 3/3 | 0.5 / 24.0 → 0.5 / 19.9 | 0.0011 → 0.0012 |

As tabelas por execução (147 linhas por fase), com o obtido de cada rodada, estão no apêndice.

## Ajustes no esperado (transparência)

- C02: tirei a checagem "status ganho" depois do rascunho: mover para etapa de ganho não fecha o card no produto
  (ver item 8). Era erro meu de entendimento do produto, não da IA.
- Com o espelho da produção (sem etapa Ganho), os esperados "Ganho" viraram "Fechamento"; nos cenários 1, 2 e 7 o
  card de antes passou a começar em Proposta, para que "fecha o auto" ainda mova o card.
- Nenhum esperado foi mudado depois de ver o resultado das Fases A e B.

## Como rodar de novo

Nunca roda no CI: exige `STRESS_MULTIFUNIL=1`, banco `chatwoot_stress` e o adaptador `:test`.

```sh
# 1) Snapshot da worktree com o código a testar (um por entrega) e banco próprio no M2 (uma vez):
maccluster workspace snapshot --cwd <worktree> --name chat2you
#    db:create db:schema:load com POSTGRES_DATABASE=chatwoot_stress (ver script/stress/multifunil/rodar_no_m2.sh)

# 2) Fase A (3 rodadas, teto US$ 1,20):
script/stress/multifunil/rodar_no_m2.sh <snapshot> A 1.20 todas 3

# 3) Fase B: copiar os arquivos do #1700 para o src do snapshot e migrar o banco de teste
git diff --name-only -z <base-A> <base-A+1700> | xargs -0 git archive <base-A+1700> | ssh m2 "cd <snapshot>/src && tar -xf -"
#    rails db:migrate com o mesmo ambiente do rodar_no_m2.sh (POSTGRES_DATABASE=chatwoot_stress)
script/stress/multifunil/rodar_no_m2.sh <snapshot> B 1.00 todas 3

# 4) Tabelas do relatório:
ruby script/stress/multifunil/tabelas.rb tmp/stress/fase-B/resultado.json "Fase B"
```

`STRESS_LOG_LEVEL=info` grava no `log/test.log` do snapshot as linhas de info (foi assim que a causa 3 foi achada).

## Limpeza pendente (depois do merge)

- Snapshot: `/Users/Shared/maccluster-workspaces/chat2you/20261016-052100-b6c59773-a6900788ad-7818e594` (M2 e M4).
- Banco `chatwoot_stress` no Postgres de teste do M2 e o arquivo de chaves descartáveis
  `/Users/Shared/maccluster-test-services/stress-cofre.env` (M2).
- Worktree `~/dev/worktrees/chat2you/1140-stress-multifunil` e as branches locais `stress/fase-a` e `stress/fase-b`
  (merges só locais, nunca enviados).

## Apêndice: tabelas por execução

### Fase A (main + #1687 + #1674): 108 de 147 execuções passaram (73%). Gasto registrado: US$ 0.3369.

| Conversa | Cen. | Variação | Esperado | Obtido (só o que diferiu) | Resultado | Latência IA s (assunto / mov.) | Custo US$ |
|---|---|---|---|---|---|---|---|
| C01 r1 | 1 | informal | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.6 / 8.5 | 0.0005 |
| C02 r1 | 1 | erro de digitação | sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 17.3 | 0.0010 |
| C03 r1 | 1 | áudio transcrito | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 3.1 / 14.0 | 0.0025 |
| C04 r1 | 1 | mensagem longa | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 12.3 | 0.0007 |
| C05 r1 | 1 | obrigado | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 3.3 / 10.4 | 0.0024 |
| C06 r1 | 1 | rajada de 3 mensagens | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.6 / 8.2 | 0.0005 |
| C07 r1 | 2 | frase base | card_novo,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart]; etapa,ref:auto,valor:[fechamento]; valor,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart],nao:10000000 | etapa: proposta | FALHOU | 3.1 / 16.9 | 0.0026 |
| C08 r1 | 2 | informal | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[fechamento] | etapa: proposta | FALHOU | 3.4 / 6.8 | 0.0020 |
| C09 r1 | 2 | ordem invertida | card_novo,funil:vendas,titulo_tem:[vida]; etapa,ref:auto,valor:[fechamento] | card_novo: [] | FALHOU | 7.2 / 12.3 | 0.0041 |
| C10 r1 | 2 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[resid,apart,apto,casa,imovel]; etapa,ref:auto,valor:[fechamento] | etapa: proposta | FALHOU | 3.0 / 13.8 | 0.0023 |
| C11 r1 | 2 | mudança de ideia | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[proposta]; status,ref:auto,valor:[open] | igual ao esperado | PASSOU | 3.3 / 12.3 | 0.0022 |
| C12 r1 | 3 | frase base | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro,traseira]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta]; cards_abertos,valor:2 | igual ao esperado | PASSOU | 3.1 / 8.0 | 0.0023 |
| C13 r1 | 3 | informal com erro | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.4 / 8.2 | 0.0023 |
| C14 r1 | 3 | áudio transcrito | card_novo,funil:sinistro,titulo_tem:[roubo,furto,casa,resid,arromb,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.9 / 10.9 | 0.0024 |
| C15 r1 | 3 | pergunta que cabe em dois funis | card_novo,funil:vendas,titulo_tem:[resid,renov,casa]; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 5.1 / 8.6 | 0.0026 |
| C16 r1 | 3 | cliente volta dias depois | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 5.9 | 0.0004 |
| C17 r1 | 4 | frase base | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Marcelo Antunes]; card_novo: [vendas: Marcelo Antunes]; card_novo: [vendas: Marcelo Antunes]; cards_abertos: 1 | FALHOU | 5.4 / 10.6 | 0.0035 |
| C18 r1 | 4 | rajada em lista | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Aline Ferraz,renovacao: Renovação do seguro residencial]; card_novo: [vendas: Aline Ferraz,renovacao: Renovação do seguro residencial]; cards_abertos: 2 | FALHOU | 3.8 / 14.6 | 0.0024 |
| C19 r1 | 4 | mensagem longa | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,fazer,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,apart,renov]; cards_abertos,valor:3 | card_novo: [vendas: Eduardo Nogueira,renovacao: Renovação do seguro residencial]; card_novo: [vendas: Eduardo Nogueira,renovacao: Renovação do seguro residencial]; cards_abertos: 2 | FALHOU | 4.1 / 11.5 | 0.0028 |
| C20 r1 | 4 | áudio transcrito | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; card_novo,funil:sinistro,titulo_tem:[geladeira,eletric,danos,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Sônia Barreto,sinistro: Sinistro de dano elétrico]; card_novo: [vendas: Sônia Barreto,sinistro: Sinistro de dano elétrico]; cards_abertos: 2 | FALHOU | 3.1 / 9.2 | 0.0023 |
| C21 r1 | 5 | saudação | nenhum_assunto_novo; atendente,valor:[ninguem] | igual ao esperado | PASSOU | 0.4 / 5.7 | 0.0003 |
| C22 r1 | 5 | obrigado | sem_card_novo; foco,ref:sin; etapa,ref:sin,valor:[analise] | igual ao esperado | PASSOU | 2.7 / 8.0 | 0.0021 |
| C23 r1 | 5 | emoji sozinho | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.3 / 8.0 | 0.0021 |
| C24 r1 | 5 | alguém aí | nenhum_assunto_novo | igual ao esperado | PASSOU | 0.3 / 4.7 | 0.0003 |
| C25 r1 | 6 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | card_novo: [vendas: Paulo Henrique Dias]; card_novo: [vendas: Paulo Henrique Dias] | FALHOU | 7.1 / 28.6 | 0.0043 |
| C26 r1 | 6 | informal, pedido primeiro | card_novo,funil:vendas,titulo_tem:[resid,casa,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | card_novo: [vendas: Larissa Melo] | FALHOU | 5.6 / 26.3 | 0.0037 |
| C27 r1 | 6 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[vida]; card_novo,funil:sinistro,titulo_tem:[celular,roubo,furto,sinistro]; atendente,valor:[atribuido] | card_novo: [vendas: Mateus Queiroz,sinistro: Sinistro de celular roubado] | FALHOU | 3.2 / 30.6 | 0.0032 |
| C28 r1 | 7 | frase base | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[onix,carro,auto],valor:[fechamento]; campo,contato:true,chave:cidade,contem:campinas; campo,contato:true,chave:cep,contem:13087 | igual ao esperado | PASSOU | 4.6 / 45.8 | 0.0041 |
| C29 r1 | 7 | informal com erros | card_novo,funil:vendas,titulo_tem:[gol,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[gol,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.3 / 45.5 | 0.0042 |
| C30 r1 | 7 | volta dias depois para fechar | card_novo,funil:vendas,titulo_tem:[moto,cg]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[moto,cg],valor:[fechamento] | igual ao esperado | PASSOU | 3.7 / 31.2 | 0.0034 |
| C31 r1 | 7 | ironia e mudança de ideia | card_novo,funil:vendas,titulo_tem:[corolla,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[corolla,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.1 / 42.9 | 0.0040 |
| C32 r1 | 7 | três funis, vida | card_novo,funil:vendas,titulo_tem:[vida]; novos_no_funil,funil:vendas,valor:1; novos_no_funil,funil:sinistro,valor:0; novos_no_funil,funil:renovacao,valor:0; etapa,funil:vendas,titulo_tem:[vida],valor:[fechamento] | card_novo: [vendas: Daniela Moraes]; etapa: card não existe | FALHOU | 16.7 / 34.0 | 0.0104 |
| C33 r1 | 7 | retorno combinado | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; etapa,funil:vendas,titulo_tem:[renegade,carro,auto],valor:[proposta,fechamento]; retorno,funil:vendas,titulo_tem:[renegade,carro,auto],valor:true | igual ao esperado | PASSOU | 4.1 / 52.0 | 0.0044 |
| C34 r1 | 8 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.0 / 7.9 | 0.0018 |
| C35 r1 | 8 | informal | card_novo,funil:vendas,titulo_tem:[moto]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.8 / 7.0 | 0.0021 |
| C36 r1 | 8 | volta com sinistro | card_novo,funil:sinistro,titulo_tem:[roubo,furto,carro,tracker,sinistro]; status,ref:auto,valor:[won]; novos_no_funil,funil:vendas,valor:0 | novos_no_funil: 1 | FALHOU | 4.1 / 8.0 | 0.0021 |
| C37 r1 | 8 | obrigado depois do ganho | nenhum_assunto_novo; status,ref:auto,valor:[won] | igual ao esperado | PASSOU | 0.5 / 10.8 | 0.0006 |
| C38 r1 | 9 | dúvida de cobertura parece sinistro | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 8.8 | 0.0005 |
| C39 r1 | 9 | carro reserva dentro do sinistro | sem_card_novo; foco,ref:sin | igual ao esperado | PASSOU | 0.5 / 11.5 | 0.0006 |
| C40 r1 | 9 | assalto do vizinho | sem_card_novo; foco,ref:resid; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 0.4 / 16.4 | 0.0010 |
| C41 r1 | 9 | ironia | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 8.2 | 0.0005 |
| C42 r1 | 10 | com regra, alguém online | atendente,valor:[atribuido],pessoa:ana; sem_card_novo | igual ao esperado | PASSOU | 4.0 / 14.0 | 0.0025 |
| C43 r1 | 10 | com regra, ninguém online | atendente,valor:[segurando] | igual ao esperado | PASSOU | 4.0 / 8.8 | 0.0023 |
| C44 r1 | 10 | sem regra | atendente,valor:[ninguem] | igual ao esperado | PASSOU | 3.8 / 9.0 | 0.0023 |
| C45 r1 | 10 | pedido indireto | atendente,valor:[atribuido],pessoa:ana | igual ao esperado | PASSOU | 3.2 / 24.7 | 0.0027 |
| C46 r1 | 10 | elogio citando a atendente | atendente,valor:[ninguem]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.0 / 7.4 | 0.0019 |
| C47 r1 | 11 | WhatsApp + e-mail: proposta assinada por e-mail | sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 20.3 | 0.0010 |
| C48 r1 | 11 | WhatsApp + e-mail: 'conforme conversamos' | sem_card_novo; etapa,ref:resid,valor:[fechamento]; etapa,ref:auto,valor:[atendimento] | igual ao esperado | PASSOU | 3.8 / 21.2 | 0.0027 |
| C49 r1 | 11 | WhatsApp + e-mail: documentos do sinistro | sem_card_novo; etapa,ref:sin,valor:[analise]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 24.6 | 0.0012 |
| C01 r2 | 1 | informal | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 9.3 | 0.0005 |
| C02 r2 | 1 | erro de digitação | sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 16.8 | 0.0010 |
| C03 r2 | 1 | áudio transcrito | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 11.5 | 0.0006 |
| C04 r2 | 1 | mensagem longa | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 14.1 | 0.0007 |
| C05 r2 | 1 | obrigado | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 9.2 | 0.0005 |
| C06 r2 | 1 | rajada de 3 mensagens | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.6 / 7.4 | 0.0005 |
| C07 r2 | 2 | frase base | card_novo,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart]; etapa,ref:auto,valor:[fechamento]; valor,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart],nao:10000000 | etapa: proposta | FALHOU | 4.5 / 13.7 | 0.0023 |
| C08 r2 | 2 | informal | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[fechamento] | etapa: proposta | FALHOU | 3.7 / 9.2 | 0.0022 |
| C09 r2 | 2 | ordem invertida | card_novo,funil:vendas,titulo_tem:[vida]; etapa,ref:auto,valor:[fechamento] | card_novo: [] | FALHOU | 9.0 / 15.0 | 0.0046 |
| C10 r2 | 2 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[resid,apart,apto,casa,imovel]; etapa,ref:auto,valor:[fechamento] | etapa: proposta | FALHOU | 3.6 / 8.8 | 0.0020 |
| C11 r2 | 2 | mudança de ideia | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[proposta]; status,ref:auto,valor:[open] | igual ao esperado | PASSOU | 3.1 / 8.0 | 0.0020 |
| C12 r2 | 3 | frase base | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro,traseira]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta]; cards_abertos,valor:2 | igual ao esperado | PASSOU | 3.2 / 13.9 | 0.0025 |
| C13 r2 | 3 | informal com erro | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.4 / 12.9 | 0.0024 |
| C14 r2 | 3 | áudio transcrito | card_novo,funil:sinistro,titulo_tem:[roubo,furto,casa,resid,arromb,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.3 / 15.7 | 0.0025 |
| C15 r2 | 3 | pergunta que cabe em dois funis | card_novo,funil:vendas,titulo_tem:[resid,renov,casa]; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 3.5 / 10.5 | 0.0021 |
| C16 r2 | 3 | cliente volta dias depois | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 7.7 | 0.0004 |
| C17 r2 | 4 | frase base | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Marcelo Antunes]; card_novo: [vendas: Marcelo Antunes]; card_novo: [vendas: Marcelo Antunes]; cards_abertos: 1 | FALHOU | 4.8 / 16.3 | 0.0029 |
| C18 r2 | 4 | rajada em lista | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Aline Ferraz,renovacao: Renovação do seguro residencial]; card_novo: [vendas: Aline Ferraz,renovacao: Renovação do seguro residencial]; cards_abertos: 2 | FALHOU | 3.2 / 15.9 | 0.0024 |
| C19 r2 | 4 | mensagem longa | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,fazer,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,apart,renov]; cards_abertos,valor:3 | card_novo: [vendas: Eduardo Nogueira,renovacao: Renovação do seguro residencial]; card_novo: [vendas: Eduardo Nogueira,renovacao: Renovação do seguro residencial]; cards_abertos: 2 | FALHOU | 3.7 / 19.8 | 0.0029 |
| C20 r2 | 4 | áudio transcrito | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; card_novo,funil:sinistro,titulo_tem:[geladeira,eletric,danos,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Sônia Barreto,sinistro: Sinistro de danos elétricos]; card_novo: [vendas: Sônia Barreto,sinistro: Sinistro de danos elétricos]; cards_abertos: 2 | FALHOU | 4.4 / 16.6 | 0.0029 |
| C21 r2 | 5 | saudação | nenhum_assunto_novo; atendente,valor:[ninguem] | igual ao esperado | PASSOU | 0.5 / 5.7 | 0.0003 |
| C22 r2 | 5 | obrigado | sem_card_novo; foco,ref:sin; etapa,ref:sin,valor:[analise] | igual ao esperado | PASSOU | 3.5 / 11.5 | 0.0021 |
| C23 r2 | 5 | emoji sozinho | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 2.7 / 8.0 | 0.0021 |
| C24 r2 | 5 | alguém aí | nenhum_assunto_novo | igual ao esperado | PASSOU | 0.5 / 6.7 | 0.0004 |
| C25 r2 | 6 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | card_novo: [vendas: Paulo Henrique Dias]; card_novo: [vendas: Paulo Henrique Dias] | FALHOU | 4.7 / 34.3 | 0.0039 |
| C26 r2 | 6 | informal, pedido primeiro | card_novo,funil:vendas,titulo_tem:[resid,casa,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | card_novo: [vendas: Larissa Melo] | FALHOU | 5.2 / 28.6 | 0.0036 |
| C27 r2 | 6 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[vida]; card_novo,funil:sinistro,titulo_tem:[celular,roubo,furto,sinistro]; atendente,valor:[atribuido] | card_novo: [vendas: Mateus Queiroz,sinistro: Sinistro de celular roubado] | FALHOU | 3.9 / 44.0 | 0.0038 |
| C28 r2 | 7 | frase base | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[onix,carro,auto],valor:[fechamento]; campo,contato:true,chave:cidade,contem:campinas; campo,contato:true,chave:cep,contem:13087 | igual ao esperado | PASSOU | 4.9 / 56.6 | 0.0044 |
| C29 r2 | 7 | informal com erros | card_novo,funil:vendas,titulo_tem:[gol,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[gol,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.2 / 50.1 | 0.0040 |
| C30 r2 | 7 | volta dias depois para fechar | card_novo,funil:vendas,titulo_tem:[moto,cg]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[moto,cg],valor:[fechamento] | igual ao esperado | PASSOU | 3.9 / 41.8 | 0.0036 |
| C31 r2 | 7 | ironia e mudança de ideia | card_novo,funil:vendas,titulo_tem:[corolla,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[corolla,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.1 / 65.0 | 0.0046 |
| C32 r2 | 7 | três funis, vida | card_novo,funil:vendas,titulo_tem:[vida]; novos_no_funil,funil:vendas,valor:1; novos_no_funil,funil:sinistro,valor:0; novos_no_funil,funil:renovacao,valor:0; etapa,funil:vendas,titulo_tem:[vida],valor:[fechamento] | card_novo: [vendas: Daniela Moraes]; etapa: card não existe | FALHOU | 15.2 / 39.0 | 0.0094 |
| C33 r2 | 7 | retorno combinado | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; etapa,funil:vendas,titulo_tem:[renegade,carro,auto],valor:[proposta,fechamento]; retorno,funil:vendas,titulo_tem:[renegade,carro,auto],valor:true | igual ao esperado | PASSOU | 4.6 / 54.6 | 0.0042 |
| C34 r2 | 8 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.0 / 6.1 | 0.0018 |
| C35 r2 | 8 | informal | card_novo,funil:vendas,titulo_tem:[moto]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.1 / 8.6 | 0.0020 |
| C36 r2 | 8 | volta com sinistro | card_novo,funil:sinistro,titulo_tem:[roubo,furto,carro,tracker,sinistro]; status,ref:auto,valor:[won]; novos_no_funil,funil:vendas,valor:0 | novos_no_funil: 1 | FALHOU | 3.0 / 8.0 | 0.0020 |
| C37 r2 | 8 | obrigado depois do ganho | nenhum_assunto_novo; status,ref:auto,valor:[won] | igual ao esperado | PASSOU | 0.3 / 24.2 | 0.0011 |
| C38 r2 | 9 | dúvida de cobertura parece sinistro | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 9.4 | 0.0005 |
| C39 r2 | 9 | carro reserva dentro do sinistro | sem_card_novo; foco,ref:sin | igual ao esperado | PASSOU | 0.4 / 11.8 | 0.0005 |
| C40 r2 | 9 | assalto do vizinho | sem_card_novo; foco,ref:resid; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 0.4 / 18.4 | 0.0009 |
| C41 r2 | 9 | ironia | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 5.6 | 0.0004 |
| C42 r2 | 10 | com regra, alguém online | atendente,valor:[atribuido],pessoa:ana; sem_card_novo | igual ao esperado | PASSOU | 3.4 / 19.6 | 0.0027 |
| C43 r2 | 10 | com regra, ninguém online | atendente,valor:[segurando] | igual ao esperado | PASSOU | 3.1 / 8.1 | 0.0020 |
| C44 r2 | 10 | sem regra | atendente,valor:[ninguem] | igual ao esperado | PASSOU | 3.2 / 12.5 | 0.0021 |
| C45 r2 | 10 | pedido indireto | atendente,valor:[atribuido],pessoa:ana | igual ao esperado | PASSOU | 2.8 / 27.5 | 0.0028 |
| C46 r2 | 10 | elogio citando a atendente | atendente,valor:[ninguem]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 7.0 / 12.1 | 0.0021 |
| C47 r2 | 11 | WhatsApp + e-mail: proposta assinada por e-mail | sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 13.5 | 0.0008 |
| C48 r2 | 11 | WhatsApp + e-mail: 'conforme conversamos' | sem_card_novo; etapa,ref:resid,valor:[fechamento]; etapa,ref:auto,valor:[atendimento] | igual ao esperado | PASSOU | 5.2 / 16.2 | 0.0029 |
| C49 r2 | 11 | WhatsApp + e-mail: documentos do sinistro | sem_card_novo; etapa,ref:sin,valor:[analise]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 23.5 | 0.0011 |
| C01 r3 | 1 | informal | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.5 / 10.5 | 0.0006 |
| C02 r3 | 1 | erro de digitação | sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 25.8 | 0.0013 |
| C03 r3 | 1 | áudio transcrito | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 11.6 | 0.0006 |
| C04 r3 | 1 | mensagem longa | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.5 / 12.7 | 0.0007 |
| C05 r3 | 1 | obrigado | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 3.0 / 8.5 | 0.0022 |
| C06 r3 | 1 | rajada de 3 mensagens | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 12.3 | 0.0006 |
| C07 r3 | 2 | frase base | card_novo,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart]; etapa,ref:auto,valor:[fechamento]; valor,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart],nao:10000000 | etapa: proposta | FALHOU | 3.4 / 15.8 | 0.0024 |
| C08 r3 | 2 | informal | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[fechamento] | etapa: proposta | FALHOU | 3.6 / 14.7 | 0.0022 |
| C09 r3 | 2 | ordem invertida | card_novo,funil:vendas,titulo_tem:[vida]; etapa,ref:auto,valor:[fechamento] | card_novo: [] | FALHOU | 7.6 / 16.4 | 0.0041 |
| C10 r3 | 2 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[resid,apart,apto,casa,imovel]; etapa,ref:auto,valor:[fechamento] | etapa: proposta | FALHOU | 3.2 / 23.2 | 0.0028 |
| C11 r3 | 2 | mudança de ideia | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[proposta]; status,ref:auto,valor:[open] | igual ao esperado | PASSOU | 3.8 / 9.1 | 0.0020 |
| C12 r3 | 3 | frase base | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro,traseira]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta]; cards_abertos,valor:2 | igual ao esperado | PASSOU | 3.0 / 13.3 | 0.0024 |
| C13 r3 | 3 | informal com erro | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.5 / 12.3 | 0.0024 |
| C14 r3 | 3 | áudio transcrito | card_novo,funil:sinistro,titulo_tem:[roubo,furto,casa,resid,arromb,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 2.9 / 12.1 | 0.0024 |
| C15 r3 | 3 | pergunta que cabe em dois funis | card_novo,funil:vendas,titulo_tem:[resid,renov,casa]; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 3.8 / 13.3 | 0.0026 |
| C16 r3 | 3 | cliente volta dias depois | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 8.3 | 0.0004 |
| C17 r3 | 4 | frase base | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Marcelo Antunes]; card_novo: [vendas: Marcelo Antunes]; card_novo: [vendas: Marcelo Antunes]; cards_abertos: 1 | FALHOU | 4.0 / 12.2 | 0.0027 |
| C18 r3 | 4 | rajada em lista | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Aline Ferraz,renovacao: Renovação do seguro residencial]; card_novo: [vendas: Aline Ferraz,renovacao: Renovação do seguro residencial]; cards_abertos: 2 | FALHOU | 3.5 / 15.9 | 0.0024 |
| C19 r3 | 4 | mensagem longa | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,fazer,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,apart,renov]; cards_abertos,valor:3 | card_novo: [vendas: Eduardo Nogueira,renovacao: Renovação do seguro residencial]; card_novo: [vendas: Eduardo Nogueira,renovacao: Renovação do seguro residencial]; cards_abertos: 2 | FALHOU | 4.1 / 20.0 | 0.0031 |
| C20 r3 | 4 | áudio transcrito | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; card_novo,funil:sinistro,titulo_tem:[geladeira,eletric,danos,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | card_novo: [vendas: Sônia Barreto,sinistro: Sinistro de dano elétrico]; card_novo: [vendas: Sônia Barreto,sinistro: Sinistro de dano elétrico]; cards_abertos: 2 | FALHOU | 4.7 / 10.9 | 0.0029 |
| C21 r3 | 5 | saudação | nenhum_assunto_novo; atendente,valor:[ninguem] | igual ao esperado | PASSOU | 0.4 / 5.4 | 0.0003 |
| C22 r3 | 5 | obrigado | sem_card_novo; foco,ref:sin; etapa,ref:sin,valor:[analise] | igual ao esperado | PASSOU | 3.2 / 9.9 | 0.0021 |
| C23 r3 | 5 | emoji sozinho | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.7 / 9.0 | 0.0022 |
| C24 r3 | 5 | alguém aí | nenhum_assunto_novo | igual ao esperado | PASSOU | 0.4 / 5.7 | 0.0004 |
| C25 r3 | 6 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | card_novo: [vendas: Paulo Henrique Dias]; card_novo: [vendas: Paulo Henrique Dias] | FALHOU | 4.8 / 29.4 | 0.0039 |
| C26 r3 | 6 | informal, pedido primeiro | card_novo,funil:vendas,titulo_tem:[resid,casa,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | card_novo: [vendas: Larissa Melo] | FALHOU | 5.3 / 33.9 | 0.0041 |
| C27 r3 | 6 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[vida]; card_novo,funil:sinistro,titulo_tem:[celular,roubo,furto,sinistro]; atendente,valor:[atribuido] | card_novo: [vendas: Mateus Queiroz,sinistro: Sinistro de celular roubado] | FALHOU | 3.8 / 22.1 | 0.0030 |
| C28 r3 | 7 | frase base | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[onix,carro,auto],valor:[fechamento]; campo,contato:true,chave:cidade,contem:campinas; campo,contato:true,chave:cep,contem:13087 | igual ao esperado | PASSOU | 4.3 / 55.1 | 0.0044 |
| C29 r3 | 7 | informal com erros | card_novo,funil:vendas,titulo_tem:[gol,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[gol,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 5.3 / 50.3 | 0.0042 |
| C30 r3 | 7 | volta dias depois para fechar | card_novo,funil:vendas,titulo_tem:[moto,cg]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[moto,cg],valor:[fechamento] | igual ao esperado | PASSOU | 4.2 / 38.8 | 0.0036 |
| C31 r3 | 7 | ironia e mudança de ideia | card_novo,funil:vendas,titulo_tem:[corolla,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[corolla,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.2 / 53.4 | 0.0042 |
| C32 r3 | 7 | três funis, vida | card_novo,funil:vendas,titulo_tem:[vida]; novos_no_funil,funil:vendas,valor:1; novos_no_funil,funil:sinistro,valor:0; novos_no_funil,funil:renovacao,valor:0; etapa,funil:vendas,titulo_tem:[vida],valor:[fechamento] | card_novo: [vendas: Daniela Moraes]; etapa: card não existe | FALHOU | 14.3 / 35.4 | 0.0096 |
| C33 r3 | 7 | retorno combinado | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; etapa,funil:vendas,titulo_tem:[renegade,carro,auto],valor:[proposta,fechamento]; retorno,funil:vendas,titulo_tem:[renegade,carro,auto],valor:true | igual ao esperado | PASSOU | 3.7 / 63.8 | 0.0041 |
| C34 r3 | 8 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 2.7 / 7.4 | 0.0017 |
| C35 r3 | 8 | informal | card_novo,funil:vendas,titulo_tem:[moto]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.7 / 8.8 | 0.0020 |
| C36 r3 | 8 | volta com sinistro | card_novo,funil:sinistro,titulo_tem:[roubo,furto,carro,tracker,sinistro]; status,ref:auto,valor:[won]; novos_no_funil,funil:vendas,valor:0 | novos_no_funil: 1 | FALHOU | 3.2 / 6.9 | 0.0020 |
| C37 r3 | 8 | obrigado depois do ganho | nenhum_assunto_novo; status,ref:auto,valor:[won] | igual ao esperado | PASSOU | 0.4 / 31.3 | 0.0014 |
| C38 r3 | 9 | dúvida de cobertura parece sinistro | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 10.1 | 0.0005 |
| C39 r3 | 9 | carro reserva dentro do sinistro | sem_card_novo; foco,ref:sin | igual ao esperado | PASSOU | 0.4 / 11.8 | 0.0006 |
| C40 r3 | 9 | assalto do vizinho | sem_card_novo; foco,ref:resid; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 0.5 / 25.4 | 0.0010 |
| C41 r3 | 9 | ironia | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.6 / 6.9 | 0.0004 |
| C42 r3 | 10 | com regra, alguém online | atendente,valor:[atribuido],pessoa:ana; sem_card_novo | igual ao esperado | PASSOU | 3.0 / 17.4 | 0.0024 |
| C43 r3 | 10 | com regra, ninguém online | atendente,valor:[segurando] | igual ao esperado | PASSOU | 3.3 / 11.8 | 0.0021 |
| C44 r3 | 10 | sem regra | atendente,valor:[ninguem] | igual ao esperado | PASSOU | 3.3 / 16.4 | 0.0023 |
| C45 r3 | 10 | pedido indireto | atendente,valor:[atribuido],pessoa:ana | igual ao esperado | PASSOU | 2.6 / 22.3 | 0.0025 |
| C46 r3 | 10 | elogio citando a atendente | atendente,valor:[ninguem]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.4 / 13.8 | 0.0022 |
| C47 r3 | 11 | WhatsApp + e-mail: proposta assinada por e-mail | sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 14.9 | 0.0008 |
| C48 r3 | 11 | WhatsApp + e-mail: 'conforme conversamos' | sem_card_novo; etapa,ref:resid,valor:[fechamento]; etapa,ref:auto,valor:[atendimento] | igual ao esperado | PASSOU | 3.9 / 17.0 | 0.0028 |
| C49 r3 | 11 | WhatsApp + e-mail: documentos do sinistro | sem_card_novo; etapa,ref:sin,valor:[analise]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 24.0 | 0.0011 |

| IA | Checagens certas | Acerto |
|---|---|---|
| IA de assunto (Jev + revisão) | 345/405 | 85% |
| IA de movimentação (avaliação do card) | 291/303 | 96% |

| Cenário | Execuções que passaram | Acerto |
|---|---|---|
| 1 | 18/18 | 100% |
| 2 | 3/15 | 20% |
| 3 | 15/15 | 100% |
| 4 | 0/12 | 0% |
| 5 | 12/12 | 100% |
| 6 | 0/9 | 0% |
| 7 | 15/18 | 83% |
| 8 | 9/12 | 75% |
| 9 | 12/12 | 100% |
| 10 | 15/15 | 100% |
| 11 | 9/9 | 100% |

Mensagens do cliente processadas: 192.

| IA | Custo US$ | Chamadas | Custo médio por mensagem do cliente US$ |
|---|---|---|---|
| IA de assunto (Jev + revisão) | 0.2015 | 300 | 0.00105 |
| IA de movimentação (avaliação do card) | 0.1354 | 270 | 0.00070 |

Rodadas por conversa: 3. Instáveis (o resultado mudou entre rodadas): nenhuma.

### Fase B (+ #1700 52f97c3459): 132 de 147 execuções passaram (90%). Gasto registrado: US$ 0.3830.

| Conversa | Cen. | Variação | Esperado | Obtido (só o que diferiu) | Resultado | Latência IA s (assunto / mov.) | Custo US$ |
|---|---|---|---|---|---|---|---|
| C01 r1 | 1 | informal | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.6 / 12.0 | 0.0006 |
| C02 r1 | 1 | erro de digitação | sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 29.7 | 0.0013 |
| C03 r1 | 1 | áudio transcrito | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 3.6 / 14.8 | 0.0029 |
| C04 r1 | 1 | mensagem longa | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.5 / 15.1 | 0.0007 |
| C05 r1 | 1 | obrigado | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 7.5 / 0.0 | 0.0040 |
| C06 r1 | 1 | rajada de 3 mensagens | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.7 / 12.0 | 0.0006 |
| C07 r1 | 2 | frase base | card_novo,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart]; etapa,ref:auto,valor:[fechamento]; valor,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart],nao:10000000 | igual ao esperado | PASSOU | 3.7 / 24.5 | 0.0033 |
| C08 r1 | 2 | informal | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 3.2 / 19.8 | 0.0030 |
| C09 r1 | 2 | ordem invertida | card_novo,funil:vendas,titulo_tem:[vida]; etapa,ref:auto,valor:[fechamento] | card_novo: [] | FALHOU | 8.0 / 16.1 | 0.0048 |
| C10 r1 | 2 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[resid,apart,apto,casa,imovel]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 3.4 / 19.7 | 0.0031 |
| C11 r1 | 2 | mudança de ideia | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[proposta]; status,ref:auto,valor:[open] | igual ao esperado | PASSOU | 3.7 / 22.1 | 0.0032 |
| C12 r1 | 3 | frase base | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro,traseira]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta]; cards_abertos,valor:2 | igual ao esperado | PASSOU | 3.1 / 10.6 | 0.0027 |
| C13 r1 | 3 | informal com erro | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.9 / 14.7 | 0.0028 |
| C14 r1 | 3 | áudio transcrito | card_novo,funil:sinistro,titulo_tem:[roubo,furto,casa,resid,arromb,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.4 / 8.9 | 0.0027 |
| C15 r1 | 3 | pergunta que cabe em dois funis | card_novo,funil:vendas,titulo_tem:[resid,renov,casa]; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 4.1 / 20.6 | 0.0034 |
| C16 r1 | 3 | cliente volta dias depois | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 8.9 | 0.0005 |
| C17 r1 | 4 | frase base | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.9 / 17.0 | 0.0036 |
| C18 r1 | 4 | rajada em lista | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.9 / 18.7 | 0.0037 |
| C19 r1 | 4 | mensagem longa | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,fazer,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,apart,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.6 / 25.1 | 0.0043 |
| C20 r1 | 4 | áudio transcrito | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; card_novo,funil:sinistro,titulo_tem:[geladeira,eletric,danos,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.6 / 24.4 | 0.0041 |
| C21 r1 | 5 | saudação | nenhum_assunto_novo; atendente,valor:[ninguem] | igual ao esperado | PASSOU | 0.5 / 6.2 | 0.0003 |
| C22 r1 | 5 | obrigado | sem_card_novo; foco,ref:sin; etapa,ref:sin,valor:[analise] | igual ao esperado | PASSOU | 3.3 / 0.0 | 0.0019 |
| C23 r1 | 5 | emoji sozinho | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.0 / 0.0 | 0.0024 |
| C24 r1 | 5 | alguém aí | nenhum_assunto_novo | igual ao esperado | PASSOU | 0.4 / 6.2 | 0.0004 |
| C25 r1 | 6 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | igual ao esperado | PASSOU | 3.2 / 39.6 | 0.0039 |
| C26 r1 | 6 | informal, pedido primeiro | card_novo,funil:vendas,titulo_tem:[resid,casa,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | atendente: estado:ninguem | FALHOU | 3.6 / 15.6 | 0.0031 |
| C27 r1 | 6 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[vida]; card_novo,funil:sinistro,titulo_tem:[celular,roubo,furto,sinistro]; atendente,valor:[atribuido] | card_novo: [vendas: Mateus Queiroz]; card_novo: [vendas: Mateus Queiroz] | FALHOU | 6.0 / 32.5 | 0.0048 |
| C28 r1 | 7 | frase base | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[onix,carro,auto],valor:[fechamento]; campo,contato:true,chave:cidade,contem:campinas; campo,contato:true,chave:cep,contem:13087 | igual ao esperado | PASSOU | 4.2 / 53.2 | 0.0047 |
| C29 r1 | 7 | informal com erros | card_novo,funil:vendas,titulo_tem:[gol,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[gol,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.2 / 60.0 | 0.0047 |
| C30 r1 | 7 | volta dias depois para fechar | card_novo,funil:vendas,titulo_tem:[moto,cg]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[moto,cg],valor:[fechamento] | igual ao esperado | PASSOU | 4.1 / 37.4 | 0.0040 |
| C31 r1 | 7 | ironia e mudança de ideia | card_novo,funil:vendas,titulo_tem:[corolla,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[corolla,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.3 / 50.6 | 0.0046 |
| C32 r1 | 7 | três funis, vida | card_novo,funil:vendas,titulo_tem:[vida]; novos_no_funil,funil:vendas,valor:1; novos_no_funil,funil:sinistro,valor:0; novos_no_funil,funil:renovacao,valor:0; etapa,funil:vendas,titulo_tem:[vida],valor:[fechamento] | card_novo: [vendas: Daniela Moraes]; etapa: card não existe | FALHOU | 13.5 / 36.4 | 0.0104 |
| C33 r1 | 7 | retorno combinado | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; etapa,funil:vendas,titulo_tem:[renegade,carro,auto],valor:[proposta,fechamento]; retorno,funil:vendas,titulo_tem:[renegade,carro,auto],valor:true | igual ao esperado | PASSOU | 3.9 / 48.7 | 0.0045 |
| C34 r1 | 8 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 2.9 / 6.0 | 0.0022 |
| C35 r1 | 8 | informal | card_novo,funil:vendas,titulo_tem:[moto]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.4 / 7.4 | 0.0023 |
| C36 r1 | 8 | volta com sinistro | card_novo,funil:sinistro,titulo_tem:[roubo,furto,carro,tracker,sinistro]; status,ref:auto,valor:[won]; novos_no_funil,funil:vendas,valor:0 | novos_no_funil: 1 | FALHOU | 3.2 / 8.3 | 0.0025 |
| C37 r1 | 8 | obrigado depois do ganho | nenhum_assunto_novo; status,ref:auto,valor:[won] | igual ao esperado | PASSOU | 0.5 / 7.2 | 0.0004 |
| C38 r1 | 9 | dúvida de cobertura parece sinistro | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 8.6 | 0.0005 |
| C39 r1 | 9 | carro reserva dentro do sinistro | sem_card_novo; foco,ref:sin | igual ao esperado | PASSOU | 0.4 / 12.8 | 0.0007 |
| C40 r1 | 9 | assalto do vizinho | sem_card_novo; foco,ref:resid; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 0.5 / 17.2 | 0.0009 |
| C41 r1 | 9 | ironia | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.6 / 7.0 | 0.0004 |
| C42 r1 | 10 | com regra, alguém online | atendente,valor:[atribuido],pessoa:ana; sem_card_novo | igual ao esperado | PASSOU | 3.1 / 18.1 | 0.0030 |
| C43 r1 | 10 | com regra, ninguém online | atendente,valor:[segurando] | igual ao esperado | PASSOU | 3.3 / 6.3 | 0.0026 |
| C44 r1 | 10 | sem regra | atendente,valor:[ninguem] | igual ao esperado | PASSOU | 3.4 / 7.2 | 0.0024 |
| C45 r1 | 10 | pedido indireto | atendente,valor:[atribuido],pessoa:ana | igual ao esperado | PASSOU | 2.7 / 16.7 | 0.0029 |
| C46 r1 | 10 | elogio citando a atendente | atendente,valor:[ninguem]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.4 / 11.0 | 0.0030 |
| C47 r1 | 11 | WhatsApp + e-mail: proposta assinada por e-mail | sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.5 / 16.1 | 0.0009 |
| C48 r1 | 11 | WhatsApp + e-mail: 'conforme conversamos' | sem_card_novo; etapa,ref:resid,valor:[fechamento]; etapa,ref:auto,valor:[atendimento] | igual ao esperado | PASSOU | 0.5 / 13.6 | 0.0008 |
| C49 r1 | 11 | WhatsApp + e-mail: documentos do sinistro | sem_card_novo; etapa,ref:sin,valor:[analise]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 22.2 | 0.0012 |
| C01 r2 | 1 | informal | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.5 / 12.0 | 0.0007 |
| C02 r2 | 1 | erro de digitação | sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 23.8 | 0.0013 |
| C03 r2 | 1 | áudio transcrito | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 2.8 / 9.8 | 0.0028 |
| C04 r2 | 1 | mensagem longa | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 7.9 | 0.0005 |
| C05 r2 | 1 | obrigado | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.7 / 0.0 | 0.0000 |
| C06 r2 | 1 | rajada de 3 mensagens | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.6 / 9.3 | 0.0005 |
| C07 r2 | 2 | frase base | card_novo,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart]; etapa,ref:auto,valor:[fechamento]; valor,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart],nao:10000000 | igual ao esperado | PASSOU | 3.6 / 19.2 | 0.0034 |
| C08 r2 | 2 | informal | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 3.6 / 16.5 | 0.0031 |
| C09 r2 | 2 | ordem invertida | card_novo,funil:vendas,titulo_tem:[vida]; etapa,ref:auto,valor:[fechamento] | card_novo: [] | FALHOU | 6.3 / 12.3 | 0.0043 |
| C10 r2 | 2 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[resid,apart,apto,casa,imovel]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 5.0 / 21.5 | 0.0037 |
| C11 r2 | 2 | mudança de ideia | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[proposta]; status,ref:auto,valor:[open] | igual ao esperado | PASSOU | 3.8 / 18.7 | 0.0032 |
| C12 r2 | 3 | frase base | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro,traseira]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta]; cards_abertos,valor:2 | igual ao esperado | PASSOU | 3.1 / 9.0 | 0.0028 |
| C13 r2 | 3 | informal com erro | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.5 / 6.8 | 0.0026 |
| C14 r2 | 3 | áudio transcrito | card_novo,funil:sinistro,titulo_tem:[roubo,furto,casa,resid,arromb,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.1 / 17.2 | 0.0032 |
| C15 r2 | 3 | pergunta que cabe em dois funis | card_novo,funil:vendas,titulo_tem:[resid,renov,casa]; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 4.7 / 8.9 | 0.0029 |
| C16 r2 | 3 | cliente volta dias depois | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 6.3 | 0.0004 |
| C17 r2 | 4 | frase base | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.9 / 13.7 | 0.0035 |
| C18 r2 | 4 | rajada em lista | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.8 / 20.5 | 0.0038 |
| C19 r2 | 4 | mensagem longa | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,fazer,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,apart,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 4.0 / 15.5 | 0.0038 |
| C20 r2 | 4 | áudio transcrito | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; card_novo,funil:sinistro,titulo_tem:[geladeira,eletric,danos,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.8 / 25.8 | 0.0043 |
| C21 r2 | 5 | saudação | nenhum_assunto_novo; atendente,valor:[ninguem] | igual ao esperado | PASSOU | 0.4 / 5.4 | 0.0003 |
| C22 r2 | 5 | obrigado | sem_card_novo; foco,ref:sin; etapa,ref:sin,valor:[analise] | igual ao esperado | PASSOU | 0.5 / 0.0 | 0.0000 |
| C23 r2 | 5 | emoji sozinho | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.8 / 0.0 | 0.0025 |
| C24 r2 | 5 | alguém aí | nenhum_assunto_novo | igual ao esperado | PASSOU | 0.4 / 5.2 | 0.0004 |
| C25 r2 | 6 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | igual ao esperado | PASSOU | 3.4 / 43.2 | 0.0042 |
| C26 r2 | 6 | informal, pedido primeiro | card_novo,funil:vendas,titulo_tem:[resid,casa,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | atendente: estado:ninguem | FALHOU | 3.8 / 14.3 | 0.0032 |
| C27 r2 | 6 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[vida]; card_novo,funil:sinistro,titulo_tem:[celular,roubo,furto,sinistro]; atendente,valor:[atribuido] | card_novo: [vendas: Mateus Queiroz]; card_novo: [vendas: Mateus Queiroz] | FALHOU | 7.0 / 29.0 | 0.0049 |
| C28 r2 | 7 | frase base | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[onix,carro,auto],valor:[fechamento]; campo,contato:true,chave:cidade,contem:campinas; campo,contato:true,chave:cep,contem:13087 | igual ao esperado | PASSOU | 5.0 / 51.0 | 0.0049 |
| C29 r2 | 7 | informal com erros | card_novo,funil:vendas,titulo_tem:[gol,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[gol,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 5.0 / 39.9 | 0.0045 |
| C30 r2 | 7 | volta dias depois para fechar | card_novo,funil:vendas,titulo_tem:[moto,cg]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[moto,cg],valor:[fechamento] | igual ao esperado | PASSOU | 3.9 / 28.2 | 0.0038 |
| C31 r2 | 7 | ironia e mudança de ideia | card_novo,funil:vendas,titulo_tem:[corolla,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[corolla,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 5.0 / 36.8 | 0.0044 |
| C32 r2 | 7 | três funis, vida | card_novo,funil:vendas,titulo_tem:[vida]; novos_no_funil,funil:vendas,valor:1; novos_no_funil,funil:sinistro,valor:0; novos_no_funil,funil:renovacao,valor:0; etapa,funil:vendas,titulo_tem:[vida],valor:[fechamento] | card_novo: [vendas: Daniela Moraes]; etapa: card não existe | FALHOU | 14.4 / 31.8 | 0.0103 |
| C33 r2 | 7 | retorno combinado | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; etapa,funil:vendas,titulo_tem:[renegade,carro,auto],valor:[proposta,fechamento]; retorno,funil:vendas,titulo_tem:[renegade,carro,auto],valor:true | igual ao esperado | PASSOU | 4.5 / 42.3 | 0.0046 |
| C34 r2 | 8 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.1 / 6.3 | 0.0023 |
| C35 r2 | 8 | informal | card_novo,funil:vendas,titulo_tem:[moto]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.7 / 7.3 | 0.0024 |
| C36 r2 | 8 | volta com sinistro | card_novo,funil:sinistro,titulo_tem:[roubo,furto,carro,tracker,sinistro]; status,ref:auto,valor:[won]; novos_no_funil,funil:vendas,valor:0 | novos_no_funil: 1 | FALHOU | 3.2 / 9.8 | 0.0026 |
| C37 r2 | 8 | obrigado depois do ganho | nenhum_assunto_novo; status,ref:auto,valor:[won] | igual ao esperado | PASSOU | 0.4 / 19.8 | 0.0012 |
| C38 r2 | 9 | dúvida de cobertura parece sinistro | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.4 / 5.6 | 0.0004 |
| C39 r2 | 9 | carro reserva dentro do sinistro | sem_card_novo; foco,ref:sin | igual ao esperado | PASSOU | 0.4 / 6.7 | 0.0004 |
| C40 r2 | 9 | assalto do vizinho | sem_card_novo; foco,ref:resid; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 0.5 / 13.1 | 0.0009 |
| C41 r2 | 9 | ironia | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.6 / 5.4 | 0.0004 |
| C42 r2 | 10 | com regra, alguém online | atendente,valor:[atribuido],pessoa:ana; sem_card_novo | igual ao esperado | PASSOU | 3.6 / 14.4 | 0.0029 |
| C43 r2 | 10 | com regra, ninguém online | atendente,valor:[segurando] | igual ao esperado | PASSOU | 4.5 / 7.4 | 0.0028 |
| C44 r2 | 10 | sem regra | atendente,valor:[ninguem] | igual ao esperado | PASSOU | 4.1 / 12.4 | 0.0028 |
| C45 r2 | 10 | pedido indireto | atendente,valor:[atribuido],pessoa:ana | igual ao esperado | PASSOU | 3.2 / 14.0 | 0.0028 |
| C46 r2 | 10 | elogio citando a atendente | atendente,valor:[ninguem]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 5.6 / 9.8 | 0.0029 |
| C47 r2 | 11 | WhatsApp + e-mail: proposta assinada por e-mail | sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 9.9 | 0.0007 |
| C48 r2 | 11 | WhatsApp + e-mail: 'conforme conversamos' | sem_card_novo; etapa,ref:resid,valor:[fechamento]; etapa,ref:auto,valor:[atendimento] | igual ao esperado | PASSOU | 0.4 / 16.6 | 0.0011 |
| C49 r2 | 11 | WhatsApp + e-mail: documentos do sinistro | sem_card_novo; etapa,ref:sin,valor:[analise]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 17.5 | 0.0011 |
| C01 r3 | 1 | informal | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.5 / 8.4 | 0.0006 |
| C02 r3 | 1 | erro de digitação | sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 15.4 | 0.0011 |
| C03 r3 | 1 | áudio transcrito | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 7.5 | 0.0005 |
| C04 r3 | 1 | mensagem longa | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.4 / 9.2 | 0.0006 |
| C05 r3 | 1 | obrigado | foco,ref:auto; sem_card_novo; etapa,ref:auto,valor:[fechamento]; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 0.0 | 0.0000 |
| C06 r3 | 1 | rajada de 3 mensagens | foco,ref:resid; sem_card_novo; etapa,ref:resid,valor:[proposta] | igual ao esperado | PASSOU | 0.6 / 9.8 | 0.0007 |
| C07 r3 | 2 | frase base | card_novo,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart]; etapa,ref:auto,valor:[fechamento]; valor,funil:vendas,titulo_tem:[resid,casa,incend,lar,imovel,apart],nao:10000000 | igual ao esperado | PASSOU | 3.3 / 14.1 | 0.0032 |
| C08 r3 | 2 | informal | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 3.5 / 19.1 | 0.0034 |
| C09 r3 | 2 | ordem invertida | card_novo,funil:vendas,titulo_tem:[vida]; etapa,ref:auto,valor:[fechamento] | card_novo: [] | FALHOU | 9.4 / 10.3 | 0.0046 |
| C10 r3 | 2 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[resid,apart,apto,casa,imovel]; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 3.7 / 20.9 | 0.0035 |
| C11 r3 | 2 | mudança de ideia | card_novo,funil:vendas,titulo_tem:[resid,casa,lar,imovel]; etapa,ref:auto,valor:[proposta]; status,ref:auto,valor:[open] | igual ao esperado | PASSOU | 3.8 / 16.6 | 0.0032 |
| C12 r3 | 3 | frase base | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro,traseira]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta]; cards_abertos,valor:2 | igual ao esperado | PASSOU | 3.3 / 8.0 | 0.0027 |
| C13 r3 | 3 | informal com erro | card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.6 / 6.7 | 0.0026 |
| C14 r3 | 3 | áudio transcrito | card_novo,funil:sinistro,titulo_tem:[roubo,furto,casa,resid,arromb,sinistro]; foco,funil:sinistro; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 3.6 / 13.8 | 0.0031 |
| C15 r3 | 3 | pergunta que cabe em dois funis | card_novo,funil:vendas,titulo_tem:[resid,renov,casa]; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 4.8 / 9.4 | 0.0030 |
| C16 r3 | 3 | cliente volta dias depois | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 5.9 | 0.0004 |
| C17 r3 | 4 | frase base | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.9 / 19.9 | 0.0039 |
| C18 r3 | 4 | rajada em lista | card_novo,funil:vendas,titulo_tem:[carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 5.0 / 15.1 | 0.0037 |
| C19 r3 | 4 | mensagem longa | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; card_novo,funil:sinistro,titulo_tem:[moto,fazer,batida,colis,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,apart,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 4.3 / 25.9 | 0.0044 |
| C20 r3 | 4 | áudio transcrito | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; card_novo,funil:sinistro,titulo_tem:[geladeira,eletric,danos,sinistro]; card_novo,funil:renovacao,titulo_tem:[resid,casa,renov]; cards_abertos,valor:3 | igual ao esperado | PASSOU | 3.2 / 16.3 | 0.0038 |
| C21 r3 | 5 | saudação | nenhum_assunto_novo; atendente,valor:[ninguem] | igual ao esperado | PASSOU | 0.4 / 4.2 | 0.0003 |
| C22 r3 | 5 | obrigado | sem_card_novo; foco,ref:sin; etapa,ref:sin,valor:[analise] | igual ao esperado | PASSOU | 0.5 / 0.0 | 0.0000 |
| C23 r3 | 5 | emoji sozinho | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.3 / 0.0 | 0.0023 |
| C24 r3 | 5 | alguém aí | nenhum_assunto_novo | igual ao esperado | PASSOU | 0.5 / 4.1 | 0.0003 |
| C25 r3 | 6 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | igual ao esperado | PASSOU | 4.1 / 30.9 | 0.0040 |
| C26 r3 | 6 | informal, pedido primeiro | card_novo,funil:vendas,titulo_tem:[resid,casa,lar]; card_novo,funil:sinistro,titulo_tem:[carro,batida,colis,sinistro,auto]; atendente,valor:[atribuido] | atendente: estado:ninguem | FALHOU | 3.7 / 13.0 | 0.0031 |
| C27 r3 | 6 | rajada de 3 mensagens | card_novo,funil:vendas,titulo_tem:[vida]; card_novo,funil:sinistro,titulo_tem:[celular,roubo,furto,sinistro]; atendente,valor:[atribuido] | card_novo: [vendas: Mateus Queiroz]; card_novo: [vendas: Mateus Queiroz] | FALHOU | 9.1 / 24.1 | 0.0054 |
| C28 r3 | 7 | frase base | card_novo,funil:vendas,titulo_tem:[onix,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[onix,carro,auto],valor:[fechamento]; campo,contato:true,chave:cidade,contem:campinas; campo,contato:true,chave:cep,contem:13087 | igual ao esperado | PASSOU | 4.7 / 41.2 | 0.0047 |
| C29 r3 | 7 | informal com erros | card_novo,funil:vendas,titulo_tem:[gol,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[gol,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.4 / 38.7 | 0.0047 |
| C30 r3 | 7 | volta dias depois para fechar | card_novo,funil:vendas,titulo_tem:[moto,cg]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[moto,cg],valor:[fechamento] | igual ao esperado | PASSOU | 4.6 / 25.1 | 0.0037 |
| C31 r3 | 7 | ironia e mudança de ideia | card_novo,funil:vendas,titulo_tem:[corolla,carro,auto]; novos_no_funil,funil:vendas,valor:1; etapa,funil:vendas,titulo_tem:[corolla,carro,auto],valor:[fechamento] | igual ao esperado | PASSOU | 4.7 / 38.8 | 0.0047 |
| C32 r3 | 7 | três funis, vida | card_novo,funil:vendas,titulo_tem:[vida]; novos_no_funil,funil:vendas,valor:1; novos_no_funil,funil:sinistro,valor:0; novos_no_funil,funil:renovacao,valor:0; etapa,funil:vendas,titulo_tem:[vida],valor:[fechamento] | card_novo: [vendas: Daniela Moraes]; etapa: card não existe | FALHOU | 15.8 / 25.0 | 0.0104 |
| C33 r3 | 7 | retorno combinado | card_novo,funil:vendas,titulo_tem:[renegade,carro,auto]; etapa,funil:vendas,titulo_tem:[renegade,carro,auto],valor:[proposta,fechamento]; retorno,funil:vendas,titulo_tem:[renegade,carro,auto],valor:true | igual ao esperado | PASSOU | 4.3 / 35.6 | 0.0044 |
| C34 r3 | 8 | frase base | card_novo,funil:vendas,titulo_tem:[casa,resid,lar]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 3.2 / 5.7 | 0.0023 |
| C35 r3 | 8 | informal | card_novo,funil:vendas,titulo_tem:[moto]; status,ref:auto,valor:[won]; cards_abertos,valor:1 | igual ao esperado | PASSOU | 4.6 / 5.3 | 0.0027 |
| C36 r3 | 8 | volta com sinistro | card_novo,funil:sinistro,titulo_tem:[roubo,furto,carro,tracker,sinistro]; status,ref:auto,valor:[won]; novos_no_funil,funil:vendas,valor:0 | novos_no_funil: 1 | FALHOU | 3.5 / 8.3 | 0.0026 |
| C37 r3 | 8 | obrigado depois do ganho | nenhum_assunto_novo; status,ref:auto,valor:[won] | igual ao esperado | PASSOU | 0.4 / 14.5 | 0.0009 |
| C38 r3 | 9 | dúvida de cobertura parece sinistro | sem_card_novo; foco,ref:auto; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 6.5 | 0.0005 |
| C39 r3 | 9 | carro reserva dentro do sinistro | sem_card_novo; foco,ref:sin | igual ao esperado | PASSOU | 0.5 / 8.5 | 0.0006 |
| C40 r3 | 9 | assalto do vizinho | sem_card_novo; foco,ref:resid; novos_no_funil,funil:sinistro,valor:0 | igual ao esperado | PASSOU | 0.5 / 12.4 | 0.0008 |
| C41 r3 | 9 | ironia | sem_card_novo; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 7.3 | 0.0005 |
| C42 r3 | 10 | com regra, alguém online | atendente,valor:[atribuido],pessoa:ana; sem_card_novo | igual ao esperado | PASSOU | 3.5 / 13.8 | 0.0029 |
| C43 r3 | 10 | com regra, ninguém online | atendente,valor:[segurando] | igual ao esperado | PASSOU | 3.0 / 5.9 | 0.0024 |
| C44 r3 | 10 | sem regra | atendente,valor:[ninguem] | igual ao esperado | PASSOU | 3.5 / 4.5 | 0.0024 |
| C45 r3 | 10 | pedido indireto | atendente,valor:[atribuido],pessoa:ana | igual ao esperado | PASSOU | 3.0 / 14.0 | 0.0029 |
| C46 r3 | 10 | elogio citando a atendente | atendente,valor:[ninguem]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 4.6 / 7.9 | 0.0030 |
| C47 r3 | 11 | WhatsApp + e-mail: proposta assinada por e-mail | sem_card_novo; etapa,ref:auto,valor:[fechamento] | igual ao esperado | PASSOU | 0.5 / 14.2 | 0.0009 |
| C48 r3 | 11 | WhatsApp + e-mail: 'conforme conversamos' | sem_card_novo; etapa,ref:resid,valor:[fechamento]; etapa,ref:auto,valor:[atendimento] | igual ao esperado | PASSOU | 0.4 / 13.3 | 0.0009 |
| C49 r3 | 11 | WhatsApp + e-mail: documentos do sinistro | sem_card_novo; etapa,ref:sin,valor:[analise]; etapa,ref:auto,valor:[proposta] | igual ao esperado | PASSOU | 0.5 / 20.1 | 0.0012 |

| IA | Checagens certas | Acerto |
|---|---|---|
| IA de assunto (Jev + revisão) | 390/405 | 96% |
| IA de movimentação (avaliação do card) | 297/303 | 98% |

| Cenário | Execuções que passaram | Acerto |
|---|---|---|
| 1 | 18/18 | 100% |
| 2 | 12/15 | 80% |
| 3 | 15/15 | 100% |
| 4 | 12/12 | 100% |
| 5 | 12/12 | 100% |
| 6 | 3/9 | 33% |
| 7 | 15/18 | 83% |
| 8 | 9/12 | 75% |
| 9 | 12/12 | 100% |
| 10 | 15/15 | 100% |
| 11 | 9/9 | 100% |

Mensagens do cliente processadas: 192.

| IA | Custo US$ | Chamadas | Custo médio por mensagem do cliente US$ |
|---|---|---|---|
| IA de assunto (Jev + revisão) | 0.2420 | 295 | 0.00126 |
| IA de movimentação (avaliação do card) | 0.1410 | 272 | 0.00073 |

Rodadas por conversa: 3. Instáveis (o resultado mudou entre rodadas): nenhuma.

### Rascunho A0 (estrutura modelada, antes do espelho): 31 de 46 execuções passaram (67%). Gasto registrado: US$ 0.1051.
