# F2 corretora · Lote 1: o resto do CRM

autonom-ia2/chat#1802, 18/10/2026. Continua o #1832, que trouxe os funis da corretora.

É só texto: muda o pacote `seguros/corretora` (painel e servidor) e nenhum código. A conta geral não muda.

## O que entra

187 textos novos no painel e 2 no servidor. Saíram do inventário do CRM da F2 e foram conferidos contra as decisões do Rodrigo e com os donos de cada área.

- **Painel do CRM:** "Produção" no lugar de "Receita", e "Meta de produção do mês".
- **Funil de Vender:** o botão e os atalhos dizem "Nova cotação", "Ver cotações" e "Minhas cotações". O Atender tem chave própria e não muda.
- **Card:**
  - "Seguro" nas telas que só existem no funil de Vender;
  - "card" nas telas que servem aos dois tipos de funil;
  - "parcela" no card de Cobrança. O funil leva o nome do processo, e o card o nome do item cobrado.
- **Calendário, lembretes e mensagem marcada:** "card" no lugar de "negócio".
- **Links e QR, e Anúncios da Meta:** cotação, corretor e escritório.
- **Ficha do contato e da empresa:** a aba "Seguros" e o botão "Nova cotação".
- **Automações:** o modelo "Marcar quem pede cotação".
- **Servidor:**
  - na planilha do CRM, a coluna "Próximo retorno";
  - no e-mail de lembrete, "Card:" no lugar de "Negócio:".

## O que fica como está, e por quê

- **Os modelos Suporte, Pós-venda e Cobrança:** o nome, as etapas, as ideias de Suporte e Pós-venda e as frases da IA não mudam. O Rodrigo decidiu que o funil padrão fica como está. A corretora já ganhou modelos próprios no #1832: Venda de seguro, Renovação, Sinistro e Endosso.
  - As ideias de Cobrança mudam para falar da parcela, assim como o card.
- **O valor do card nas telas que servem a todo funil** (filtro, coluna da lista, planilha): continua "Valor". "Valor do seguro" ficaria errado num card de parcela ou de sinistro.
- **O painel do Guia (`AUTONOMIA_GUIDE.*`):** vai no Lote 6, junto com o Guia e a Central.
- **`crm.service_reminders.*` ("Lembrar da parcela"):** o título é gravado no banco fora do pacote, em `service_reminder_scheduler.rb`. O Followup vai pôr o pacote nessa gravação depois do #1734, e então as chaves entram.
- **Não mudam:** os nomes de evento da Meta, o Agendamento ("horário", avisos e modelos aprovados) e o Financeiro da assinatura.

## Ajustes sobre o inventário

**Pelas decisões do Rodrigo:**
- "Seguro ativo" virou "Seguro fechado", e "Já tem seguro com você" virou "Já fechou seguro com você". Sem a data de vencimento, não dá para saber se a apólice está em vigor.
- O exemplo de assunto virou "Endosso para trocar o carro", porque alteração na apólice se chama endosso.
- O exemplo de nomes de funil segue os modelos reais: "Venda de seguro, Renovação, Sinistro".

**Pedidos pelos donos:**
- Campanhas:
  - "Quando a cotação avança, avisamos…" no lugar de "Quando o card anda";
  - "Seguros a fechar: N cotações abertas".
- Followup:
  - a prévia do lembrete de parcela não oferece segunda via, que o fluxo não manda;
  - o exemplo de tom da IA não traz prazo de validade da cotação.
- Multifunnel: "A pessoa foi tirada deste card", para casar com "ligada a este card".

**Pelo revisor:**
- O texto de "Fechou" é neutro ("entra no painel do CRM"), porque aparece também ao resolver um card de Atender.
- O exemplo de "quando usar" serve a qualquer funil: "pede uma cotação ou avisa um sinistro".

## Os textos, por dono

### Agendamento (17)

| Chave | Hoje (geral) | Corretora |
|---|---|---|
| `CRM_KANBAN.CALENDAR.QUICK_ADD.MEETING_HINT` | Escolha o negócio e clique em Continuar para configurar a reunião (caixa de entrada, convidados, horário). | Escolha o card e clique em Continuar para configurar a reunião (caixa de entrada, convidados, horário). |
| `CRM_KANBAN.CALENDAR.QUICK_ADD.MEETING_HINT_AGENDA` | Escolha o negócio e toque em Continuar para ver os dias e horários livres. | Escolha o card e toque em Continuar para ver os dias e horários livres. |
| `CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.SUBTITLE` | Agende uma reunião para este negócio e envie convites de agenda aos convidados. | Agende uma reunião sobre este seguro e envie convites de agenda aos convidados. |
| `CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DEAL` | Negócio: {deal} | Card: {deal} |
| `CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.DEAL_FALLBACK` | Negócio #{id} | Card #{id} |
| `CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.TITLE_PLACEHOLDER` | ex. Demonstração do produto | Ex.: Apresentar as opções da cotação |
| `CRM_KANBAN.CALENDAR.MEETING_DETAIL.DEAL_LABEL` | Negócio | Card |
| `CRM_KANBAN.BOOKING.ADMIN.SUBTITLE` | Permita que prospects agendem reuniões em uma caixa de entrada com calendário. Compartilhe o link público — sem necessidade de login. | Deixe o cliente marcar um horário numa caixa de entrada com calendário. Compartilhe o link público, sem precisar de login. |
| `CRM_KANBAN.BOOKING.ADMIN.TITLE_PLACEHOLDER` | ex.: Conversa inicial | Ex.: Conversa sobre o seu seguro |
| `CRM_KANBAN.BOOKING.ADMIN.PIPELINE` | Funil do lead | Funil do cliente |
| `CRM_KANBAN.BOOKING.ADMIN.STAGE` | Etapa do lead | Etapa do cliente |
| `CRM_KANBAN.BOOKING_AGENDA.ERRORS.NO_CONTACT` | Este negócio não tem cliente. Vincule um contato primeiro. | Este card não tem cliente. Vincule um contato primeiro. |
| `CRM_CALENDARIO.NOVO.COM_QUEM_TEXTO` | Procure pelo nome do cliente ou do negócio. | Procure pelo nome do cliente ou do card. |
| `CRM_CALENDARIO.NOVO.BUSCA_ROTULO` | Nome do cliente ou do negócio | Nome do cliente ou do card |
| `CRM_CALENDARIO.NOVO.SEM_NEGOCIO` | Ainda sem negócio | Ainda sem card |
| `CRM_CALENDARIO.NOVO.SEM_NEGOCIO_TEXTO` | {nome} ainda não tem um negócio. A reunião é marcada no negócio do cliente. Por enquanto, marque um lembrete. | {nome} ainda não tem um card. A reunião é marcada no card do cliente. Por enquanto, marque um lembrete. |
| `CRM_CALENDARIO.NOVO.SEM_NEGOCIO_CURTO` | Sem negócio | Sem card |

### Base de Clientes (23)

| Chave | Hoje (geral) | Corretora |
|---|---|---|
| `CRM_CARD.RESUMO.JA_COMPROU` | Já comprou de você. | Já fechou seguro com você. |
| `CRM_CARD.CONTATO.TEXTO` | A pessoa: nome, telefone, e-mail e campos. Vale para todos os negócios dela. | A pessoa: nome, telefone, e-mail e campos. Vale para todos os seguros dela. |
| `CRM_KANBAN.COMPANY_OPPORTUNITIES.HELP` | Negociações dos contatos vinculados a esta empresa. Apenas oportunidades que você pode acessar. | Seguros e atendimentos dos contatos ligados a esta empresa. Só os que você pode acessar. |
| `CRM_KANBAN.CONTACT_OPPORTUNITIES.TAB` | Oportunidades | Seguros |
| `CRM_KANBAN.CONTACT_OPPORTUNITIES.TITLE` | Oportunidades no CRM | Seguros no CRM |
| `CRM_KANBAN.CONTACT_OPPORTUNITIES.HELP` | Negociações deste contato em todos os funis. Apenas oportunidades que você pode acessar. | Seguros e atendimentos deste contato em todos os funis. Só os que você pode acessar. |
| `CRM_KANBAN.CONTACT_OPPORTUNITIES.SEARCH` | Buscar oportunidade | Buscar seguro |
| `CRM_KANBAN.CONTACT_OPPORTUNITIES.SEARCH_HINT` | Título da negociação | Nome do card. Ex.: seguro do carro |
| `CRM_KANBAN.CONTACT_OPPORTUNITIES.EMPTY` | Nenhuma oportunidade nesta consulta | Nenhum seguro nesta consulta |
| `CRM_KANBAN.OPPORTUNITY.CONTEXT.LABEL` | Nova oportunidade | Nova cotação |
| `CRM_KANBAN.OPPORTUNITY.CONTEXT.OPEN_NEW_TAB` | Nova oportunidade — abre o CRM em outra aba | Nova cotação: abre o CRM em outra aba |
| `CRM_KANBAN.OPPORTUNITY.CONTEXT.UNAVAILABLE` | Você não tem permissão para criar oportunidades aqui. | Você não tem permissão para criar cotações aqui. |
| `CRM_KANBAN.OPPORTUNITY.CONTEXT.LOADING` | Carregando o contato para a nova oportunidade… | Carregando o contato para a nova cotação… |
| `CRM_KANBAN.OPPORTUNITY.CONTEXT.READY` | O contato está pronto. Abra a oportunidade para continuar. | O contato está pronto. Abra a cotação para continuar. |
| `CRM_KANBAN.OPPORTUNITY.CONTEXT.OPEN` | Abrir oportunidade | Abrir cotação |
| `CRM_KANBAN.RELATIONSHIP.SAME_OPPORTUNITY` | O contato será vinculado a esta oportunidade. Os dados da negociação serão preservados. | O contato será ligado a este card. Os dados do seguro continuam como estão. |
| `CRM_KANBAN.RELATIONSHIP.DEAL_COMPANY_LABEL` | Empresa deste negócio | Empresa deste seguro |
| `CRM_KANBAN.RELATIONSHIP.SAVE_CONFLICT` | Não foi possível concluir o vínculo. Confira se o contato já existe ou se esta oportunidade tem conversas de outra pessoa. | Não foi possível concluir o vínculo. Confira se o contato já existe ou se este card tem conversas de outra pessoa. |
| `CRM_KANBAN.RELATIONSHIP.FIELDS_SHARED` | Mesmos campos e valores da ficha em Relacionamentos. Cada alteração é salva separadamente da oportunidade. | Mesmos campos e valores da ficha em Relacionamentos. Cada alteração é salva separada do card. |
| `CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.UNLINK_CONTEXT` | O vínculo será removido do cadastro de {name} e de suas oportunidades. Os dados comerciais serão mantidos. | O vínculo será removido do cadastro de {name} e dos cards dele. Os dados dos seguros continuam. |
| `CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.EDIT_HELP` | Este é o cadastro compartilhado da empresa. As alterações também aparecem em Relacionamentos, sem alterar os dados da negociação. | Este é o cadastro compartilhado da empresa. As alterações também aparecem em Relacionamentos, sem mudar os dados do seguro. |
| `CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.LINK_HELP` | A empresa será vinculada ao cadastro de {name} e será usada em todas as oportunidades desse contato. | A empresa será ligada ao cadastro de {name} e usada em todos os cards desse contato. |
| `CRM_KANBAN.RELATIONSHIP.COMPANY_FORM.UNLINK_HELP` | O contato ficará sem empresa. Nenhum contato, empresa, oportunidade, conversa ou arquivo será excluído. As mídias da empresa seguem o vínculo atual. | O contato ficará sem empresa. Nenhum contato, empresa, card, conversa ou arquivo será excluído. As mídias da empresa seguem o vínculo atual. |

### Campanhas (34)

| Chave | Hoje (geral) | Corretora |
|---|---|---|
| `CRM_FUNIL.ANUNCIOS.GOOGLE.NOME_EXEMPLO` | Ex.: Venda | Ex.: Seguro fechado |
| `CRM_FUNIL.PREVIA.ANUNCIO_FECHOU` | A Ana fechou a compra de {valor}. | A Ana fechou o seguro de {valor}. |
| `CRM_CARD.RESUMO.AVISO_FACEBOOK` | Quando o negócio anda, avisamos o Facebook e o Instagram. | Quando a cotação avança, avisamos o Facebook e o Instagram. |
| `CRM_CARD.ORIGEM.AVISO_TEXTO` | Quando o negócio anda, avisamos os anúncios para trazerem clientes parecidos. | Quando a cotação avança, avisamos os anúncios para trazerem clientes parecidos. |
| `CRM_KANBAN.DASHBOARD.META_SYNC.REVENUE` | Receita enviada | Valor enviado |
| `CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.INTEREST.HELP` | O cliente iniciou contato ou pediu informações. | O cliente pediu uma cotação ou informação. |
| `CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.QUALIFIED.HELP` | A necessidade foi entendida e o cliente combina com a oferta. | Já sabemos qual seguro o cliente quer e temos os dados para cotar. |
| `CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.PROPOSAL.TITLE` | Oferta em avaliação | Cotação em avaliação |
| `CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.PROPOSAL.HELP` | O cliente recebeu uma proposta e está considerando comprar. | O cliente recebeu as opções da cotação e está escolhendo. |
| `CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.NEGOTIATION.HELP` | O cliente está acertando valores, condições ou próximos passos. | O cliente está acertando valor, coberturas ou forma de pagamento. |
| `CRM_KANBAN.TRACKED_LINKS.SUBTITLE` | Crie um link ou QR por campanha, vendedor ou loja. Conversas iniciadas por ele chegam atribuídas no CRM. | Crie um link ou QR por campanha, corretor ou escritório. Conversas iniciadas por ele chegam atribuídas no CRM. |
| `CRM_KANBAN.TRACKED_LINKS.NAME_PLACEHOLDER` | Ex.: QR da loja — Centro | Ex.: QR do escritório · Centro |
| `CRM_KANBAN.TRACKED_LINKS.PREFILLED_PLACEHOLDER` | Ex.: Olá! Quero saber mais | Ex.: Olá! Quero cotar o seguro do meu carro |
| `CRM_KANBAN.TRACKED_LINKS.EMPTY` | Nenhum link rastreável ainda. Crie o primeiro para atribuir conversas de loja, vendedor ou bio. | Nenhum link rastreável ainda. Crie o primeiro para atribuir conversas do escritório, de cada corretor ou da bio. |
| `CRM_KANBAN.TRACKED_LINKS.PAGE.NAME_PLACEHOLDER` | Ex.: Loja Centro · balcão | Ex.: Escritório Centro · recepção |
| `CRM_KANBAN.TRACKED_LINKS.PAGE.MESSAGE_PLACEHOLDER` | Olá! Gostaria de saber mais. | Olá! Quero fazer uma cotação de seguro. |
| `CRM_KANBAN.TRACKED_LINKS.PAGE.ATTRIBUTION_HINT` | Use uma origem para cada loja, vendedor, divulgação ou página do site. Quando a conversa começa, a origem fica registrada no CRM. | Use uma origem para cada escritório, corretor, parceiro, divulgação ou página do site. Quando a conversa começa, a origem fica registrada no CRM. |
| `CRM_KANBAN.TRACKED_LINKS.PAGE.USAGE_DIRECT_HINT` | Loja, vendedor, bio e material impresso. | Escritório, corretor, bio e material impresso. |
| `CRM_KANBAN.TRACKED_LINKS.PAGE.WEBSITE_NAME_PLACEHOLDER` | Ex.: LP Seguro Viagem | Ex.: Página do seguro do carro |
| `CRM_KANBAN.META_ADS_HUB.PANEL.ACTION.STALLED_QUOTES.TEXT` | 1 proposta de anúncio está parada há mais de {days} dias. Ela veio de "{ad}". \| {count} propostas de anúncio estão paradas há mais de {days} dias. A maior parte veio de "{ad}". | 1 cotação de anúncio está parada há mais de {days} dias. Ela veio de "{ad}". \| {count} cotações de anúncio estão paradas há mais de {days} dias. A maior parte veio de "{ad}". |
| `CRM_KANBAN.META_ADS_HUB.PANEL.ACTION.STALLED_QUOTES.WHY` | Por quê: somam {value} em negociação. Retomar quem já pediu proposta custa menos que anunciar de novo. | Por quê: somam {value} em negociação. Retomar quem já pediu cotação custa menos que anunciar de novo. |
| `CRM_KANBAN.META_ADS_HUB.PANEL.ACTION.STALLED_QUOTES.BUTTON` | Ver a proposta \| Ver as {count} propostas | Ver a cotação \| Ver as {count} cotações |
| `CRM_KANBAN.META_ADS_HUB.PANEL.PATH.QUOTES` | proposta \| propostas | cotação \| cotações |
| `CRM_KANBAN.META_ADS_HUB.PANEL.OPEN_QUOTES` | Vendas chegando: 1 proposta aberta \| Vendas chegando: {count} propostas abertas | Seguros a fechar: 1 cotação aberta \| Seguros a fechar: {count} cotações abertas |
| `CRM_KANBAN.META_ADS_HUB.PANEL.AD_QUOTES` | 1 proposta aberta \| {count} propostas abertas | 1 cotação aberta \| {count} cotações abertas |
| `CRM_KANBAN.META_ADS_HUB.PANEL.STALLED_TITLE` | 1 proposta parada \| {count} propostas paradas | 1 cotação parada \| {count} cotações paradas |
| `CRM_KANBAN.META_ADS_HUB.PANEL.PATH_LIST.TITLE_QUOTES` | Propostas | Cotações |
| `CRM_KANBAN.META_ADS_HUB.PANEL.PATH_LIST.TOTAL_QUOTES` | 1 proposta \| {count} propostas | 1 cotação \| {count} cotações |
| `CRM_KANBAN.META_ADS_HUB.AD_DETAIL.TILES.QUOTES` | Propostas | Cotações |
| `CRM_KANBAN.META_ADS_HUB.AD_DETAIL.MEANWHILE` | 1 proposta aberta deste anúncio espera resposta. Retomar essa conversa é o que dá para fazer agora. \| {count} propostas abertas deste anúncio esperam resposta. Retomar essas conversas é o que dá para fazer agora. | 1 cotação aberta deste anúncio espera resposta. Retomar essa conversa é o que dá para fazer agora. \| {count} cotações abertas deste anúncio esperam resposta. Retomar essas conversas é o que dá para fazer agora. |
| `CRM_KANBAN.META_ADS_HUB.AD_DETAIL.MEANWHILE_SEE` | Ver as propostas | Ver as cotações |
| `CRM_KANBAN.META_ADS_HUB.AD_DETAIL.QUOTES_TITLE` | Propostas deste anúncio | Cotações deste anúncio |
| `CRM_KANBAN.META_ADS_HUB.AD_DETAIL.QUOTES_EMPTY` | Nenhuma proposta deste anúncio neste período ainda. | Nenhuma cotação deste anúncio neste período ainda. |
| `CRM_KANBAN.META_ADS_HUB.AD_DETAIL.WON` | Vendida | Seguro fechado |

### Followup (33)

| Chave | Hoje (geral) | Corretora |
|---|---|---|
| `CRM_FUNIL.RESUMO.COBRAR_LEMBRETES` | Lembramos do pagamento antes, no dia e depois do vencimento. | Lembramos da parcela antes, no dia e depois do vencimento. |
| `CRM_FUNIL.ATENDER.LEMBRETES.ANDAMENTO.MSG` | Oi, {nome}! Seu pedido continua com a gente. Assim que tiver novidade, eu te aviso. | Oi, {nome}! Seguimos cuidando do seu pedido com a seguradora. Assim que tiver novidade, eu te aviso. |
| `CRM_FUNIL.ATENDER.LEMBRETES.COBRAR.TITULO` | Lembrar do pagamento | Lembrar da parcela |
| `CRM_FUNIL.ATENDER.LEMBRETES.COBRAR.MSG_ANTES` | Oi, {nome}! Passando para lembrar que o pagamento de {valor} vence sexta. | Oi, {nome}! Passando para lembrar que a parcela do seu seguro, de {valor}, vence sexta. |
| `CRM_FUNIL.ATENDER.LEMBRETES.COBRAR.MSG_NO_DIA` | Oi, {nome}! O pagamento de {valor} vence hoje. Se já pagou, pode ignorar. | Oi, {nome}! A parcela do seu seguro, de {valor}, vence hoje. Se já pagou, pode ignorar. |
| `CRM_FUNIL.ATENDER.LEMBRETES.COBRAR.MSG_DEPOIS` | Oi, {nome}! Ainda não vimos o pagamento de {valor}. Posso te ajudar com alguma coisa? | Oi, {nome}! Ainda não vimos o pagamento da parcela de {valor}. Posso te ajudar com alguma coisa? |
| `CRM_CARD.RETORNO.SEU_TEXTO_EXEMPLO` | Oi! Passando para saber se ficou alguma dúvida. | Oi! Conseguiu ver as opções da cotação? |
| `CRM_CARD.RETORNO.TITULO_EXEMPLO` | Ex.: Ligar dia 30 às 10h · Aniversário do cliente | Ex.: Cobrar a emissão da seguradora · Pedir a CNH |
| `CRM_CARD.AGENDA.LEMBRETE_EXEMPLO` | Ex.: Ligar dia 30 às 10h · Aniversário do cliente | Ex.: Cobrar a emissão da seguradora · Pedir a CNH |
| `CRM_CARD.CHAMAR.REACTIVATE_CONFIRM_BODY` | Este cliente pediu para não receber mensagens automáticas. Se você religar, elas voltam a sair. Se outro negócio dele ainda estiver parado pelo mesmo pedido, ou se o pedido veio de outro lugar (equipe, prospecção ou e-mail), continua parado até isso ser desfeito lá. Seu nome fica registrado. | Este cliente pediu para não receber mensagens automáticas. Se você religar, elas voltam a sair. Se outro card dele ainda estiver parado pelo mesmo pedido, ou se o pedido veio de outro lugar (equipe, prospecção ou e-mail), continua parado até isso ser desfeito lá. Seu nome fica registrado. |
| `CRM_CARD.CHAMAR.RESET_KEPT_OTHER_CARDS` | Religado. O pedido do cliente continua valendo por causa de outro negócio dele. | Religado. O pedido do cliente continua valendo por causa de outro card dele. |
| `CRM_KANBAN.CALENDAR.QUICK_ADD.TITLE_PLACEHOLDER` | Ex.: Ligar para confirmar a proposta | Ex.: Mandar as opções da cotação |
| `CRM_KANBAN.CALENDAR.QUICK_ADD.CONTACT_LABEL` | Contato / negócio | Contato / card |
| `CRM_KANBAN.CALENDAR.QUICK_ADD.DEAL_LABEL` | Negócio | Card |
| `CRM_KANBAN.CALENDAR.QUICK_ADD.DEAL_PLACEHOLDER` | Buscar negócio… | Buscar card… |
| `CRM_KANBAN.CALENDAR.QUICK_ADD.ADVANCED_HINT` | Escolha o negócio e clique em Continuar — abriremos o card dele para configurar os detalhes. | Escolha o card e clique em Continuar. Abrimos o card para você ajustar os detalhes. |
| `CRM_KANBAN.CALENDAR.EVENT.OPEN_DEAL` | Abrir negócio | Abrir card |
| `CRM_KANBAN.AI_SETTINGS.AUTO_FOLLOWUP.TONE_PLACEHOLDER` | informal, trate por você, foque em seguro viagem… | informal, trate por você, seja breve… |
| `CRM_LEMBRETE.SERIE.LIGADO_CARD` | Negócio: {nome} | Card: {nome} |
| `CRM_LEMBRETE.LIGAR.NADA_TEXTO` | Fica só no calendário. Ex.: pagar o aluguel. | Fica só no calendário. Ex.: conferir as renovações da semana. |
| `CRM_LEMBRETE.LIGAR.CONTATO_TEXTO` | Mesmo sem negócio aberto. Ex.: aniversário. | Mesmo sem card aberto. Ex.: aniversário. |
| `CRM_LEMBRETE.LIGAR.CARD` | Um negócio do funil | Um card do funil |
| `CRM_LEMBRETE.LIGAR.QUAL_CARD` | Qual negócio? | Qual card? |
| `CRM_CALENDARIO.EXEMPLO.LEMBRETE` | Ex.: ligar para um cliente na sexta | Ex.: ligar para o cliente sobre a renovação na sexta |
| `CRM_CALENDARIO.EXEMPLO.FECHAR` | O dia em que o negócio deve fechar | O dia em que o seguro deve fechar |
| `CRM_CALENDARIO.ITEM.ACAO.VER_NEGOCIO` | Ver negócio | Ver card |
| `CRM_MENSAGEM_MARCADA.PARA_QUEM.ROTULO` | Procure o cliente ou o negócio | Procure o cliente ou o card |
| `CRM_MENSAGEM_MARCADA.PARA_QUEM.PELO_NEGOCIO` | Outro WhatsApp: marque pelo negócio | Outro WhatsApp: marque pelo card |
| `CRM_MENSAGEM_MARCADA.CONFIRMAR.SE_FALHAR` | Se não der para enviar, {nome} vê um aviso na tela e o motivo fica no negócio. | Se não der para enviar, {nome} vê um aviso na tela e o motivo fica no card. |
| `CRM_MENSAGEM_MARCADA.CONFIRMAR.SE_FALHAR_SEM_DONO` | Se não der para enviar, quem cuida da conversa vê um aviso na tela e o motivo fica no negócio. | Se não der para enviar, quem cuida da conversa vê um aviso na tela e o motivo fica no card. |
| `CRM_MENSAGEM_MARCADA.CONFIRMAR.ONDE_APARECE` | Aparece no calendário e no negócio até sair. | Aparece no calendário e no card até sair. |
| `CRM_MENSAGEM_MARCADA.PRONTO.ONDE` | Ela já está no calendário e no negócio. Dá para mudar ou cancelar até a hora de sair. | Ela já está no calendário e no card. Dá para mudar ou cancelar até a hora de sair. |
| `CRM_MENSAGEM_MARCADA.PRONTO.ABRIR_NEGOCIO` | Abrir o negócio | Abrir o card |

### Multifunnel (64)

| Chave | Hoje (geral) | Corretora |
|---|---|---|
| `CRM_FUNIL.SOBRE.IDEIAS.PAGAR` | quer pagar | quer pagar a parcela |
| `CRM_FUNIL.SOBRE.IDEIAS.SEGUNDA_VIA` | pede a segunda via | pede a segunda via do boleto |
| `CRM_FUNIL.SOBRE.IDEIAS.ATRASADO` | está com o pagamento atrasado | está com a parcela atrasada |
| `CRM_FUNIL.SOBRE.EXEMPLO` | Ex.: pede preço ou orçamento | Ex.: pede uma cotação ou avisa um sinistro |
| `CRM_FUNIL.ETAPA.EXEMPLO` | Ex.: o cliente recebeu o orçamento e está pensando. | Ex.: o cliente recebeu as opções da cotação e está pensando. |
| `CRM_FUNIL.VENDAS.TITULO` | Saiba quanto este funil vende | Saiba quantos seguros este funil fecha |
| `CRM_FUNIL.VENDAS.TEXTO` | As vendas fechadas aqui entram no painel, junto da meta do mês. | Os seguros fechados aqui entram no painel, junto da meta do mês. |
| `CRM_FUNIL.VENDAS.META` | Meta de vendas por mês | Meta de produção por mês |
| `CRM_FUNIL.RESUMO.TIPO_VENDER` | {tipo}: conquistar um cliente novo. Cada venda fechada conta no painel. | {tipo}: conquistar um cliente novo. Cada seguro fechado conta no painel. |
| `CRM_FUNIL.RESUMO.META` | Meta de {valor} por mês. | Meta de produção de {valor} por mês. |
| `CRM_FUNIL.PREVIA.VENDAS_TEXTO` | Exemplo com 40% da meta já vendida. | Exemplo com 40% da meta já fechada. |
| `CRM_FUNIL.PREVIA.META_EXEMPLO` | {valor} vendidos até agora | {valor} fechados até agora |
| `CRM_FUNIL.PREVIA.SEM_META` | Sem meta, o painel mostra só o total vendido. | Sem meta, o painel mostra só o total fechado. |
| `CRM_FUNIL.PREVIA.MSG_NOSSA` | Segue o orçamento que combinamos. Qualquer dúvida, é só chamar. | Segue a cotação com as opções. Qualquer dúvida, é só chamar. |
| `CRM_FUNIL.PREVIA.MSG_RETORNO` | Oi, Ana! Conseguiu olhar o orçamento? Se quiser, ajusto algum ponto para você. | Oi, Ana! Conseguiu olhar as opções da cotação? Se quiser, cotamos outra cobertura para você. |
| `CRM_FUNIL.PREVIA.LEMBRETE_TEXTO` | A Ana não responde desde segunda. Próximo passo: perguntar se ficou alguma dúvida no orçamento. | A Ana não responde desde segunda. Próximo passo: perguntar se ficou alguma dúvida na cotação. |
| `CRM_CARD.DESFECHO.GANHOU_TEXTO` | Confira o valor. Ele vai para os relatórios de vendas. | Confira o valor. Ele entra no painel do CRM. |
| `CRM_CARD.RESUMO.NEGOCIO` | Negócio | Seguro |
| `CRM_CARD.RESUMO.MAIS_DETALHES_DICA` | De onde veio, o que já aconteceu, mais do negócio e arquivar | De onde veio, o que já aconteceu, mais do seguro e arquivar |
| `CRM_CARD.RESUMO.MAIS_NEGOCIO` | Mais do negócio | Mais do seguro |
| `CRM_CARD.HISTORICO.EVENTO.ACTIVITY_UPDATE` | Os dados do negócio mudaram | Os dados do seguro mudaram |
| `CRM_CARD.HISTORICO.EVENTO.ACTIVITY_UNLINK_CONTACT` | A pessoa foi tirada deste negócio | A pessoa foi tirada deste card |
| `CRM_CARD.HISTORICO.GRUPO.NEGOCIO` | Etapas e negócio | Etapas e seguro |
| `CRM_CARD.SAIR.NEGOCIO` | as mudanças no negócio | as mudanças no seguro |
| `CRM_CARD.NEGOCIO.TELA` | Negócio | Seguro |
| `CRM_CARD.NEGOCIO.TITULO` | Sobre o negócio | Sobre o seguro |
| `CRM_CARD.NEGOCIO.TEXTO` | O que {nome} quer, quanto vale e quanta pressa tem. | Qual seguro {nome} quer, quanto custa e quanta pressa tem. |
| `CRM_CARD.NEGOCIO.NOME` | Nome do negócio | Qual seguro |
| `CRM_CARD.NEGOCIO.TITULO_EXEMPLO` | Ex.: Plano anual | Ex.: Seguro do carro |
| `CRM_CARD.NEGOCIO.TITULO_FALTA` | Escreva o nome do negócio. | Escreva qual é o seguro. |
| `CRM_CARD.NEGOCIO.VALOR` | Quanto vale | Valor do seguro |
| `CRM_CARD.NEGOCIO.OBSERVACOES_EXEMPLO` | O que a equipe precisa saber | Ex.: prefere pagar no cartão em 10x |
| `CRM_CARD.CRIAR.TITULO_2` | Sobre o negócio | Sobre o seguro |
| `CRM_CARD.CRIAR.TEXTO_2` | Dê um nome ao negócio e diga em que etapa ele entra. O resto pode ficar para depois. | Diga qual é o seguro e em que etapa ele entra. O resto pode ficar para depois. |
| `CRM_CARD.CRIAR.TITULO_2_COBRANCA` | Sobre a cobrança | Sobre a parcela |
| `CRM_CARD.CRIAR.TEXTO_2_COBRANCA` | Diga o que está sendo cobrado, o valor e o vencimento. O resto pode ficar para depois. | Diga de qual seguro é a parcela, o valor e o vencimento. O resto pode ficar para depois. |
| `CRM_CARD.PESSOA.LINKED_CONTACT` | Pessoa deste negócio | Pessoa deste card |
| `CRM_CARD.PESSOA.EMPTY_TITLE` | Este negócio ainda não tem uma pessoa | Este card ainda não tem uma pessoa |
| `CRM_CARD.PESSOA.EDIT_HELP` | O que você muda aqui vale para esta pessoa em todo lugar. O negócio não muda. | O que você muda aqui vale para esta pessoa em todo lugar. O card não muda. |
| `CRM_CARD.ASSUNTO.TITULO_EXEMPLO` | Ex.: Troca de tamanho | Ex.: Endosso para trocar o carro |
| `CRM_DASHBOARD.ORIGIN.TITLE` | Receita por origem | Produção por origem |
| `CRM_DASHBOARD.ORIGIN.REVENUE` | Receita | Produção |
| `CRM_KANBAN.DASHBOARD.KPI.GOAL` | Meta do mês | Meta de produção do mês |
| `CRM_KANBAN.ACTIONS.NEW_CARD` | Nova oportunidade | Nova cotação |
| `CRM_KANBAN.ACTIONS.VIEW_OPPORTUNITIES` | Ver oportunidades | Ver cotações |
| `CRM_KANBAN.FILTERS.SHORTCUT_MINE` | Minhas oportunidades | Minhas cotações |
| `CRM_KANBAN.DRAWER.CARD_FIELDS.HELP` | Informações próprias deste negócio. | Informações próprias deste seguro. |
| `CRM_KANBAN.DRAWER.CARD_FIELDS.EMPTY_ADMIN` | Ainda não há campos do card. Crie em Configurações → Atributos personalizados → Card. | Ainda não há campos do card. Crie em Configurações → Atributos personalizados → Card. Ex.: Seguradora atual, Vencimento do seguro, Placa. |
| `CRM_KANBAN.CONVERSATION.SUBJECTS.TITLE_PLACEHOLDER` | Ex.: Cotação — Onix 2021 | Ex.: Cotação do seguro do carro |
| `CRM_KANBAN.PIPELINE_DRAWER.NAME_PLACEHOLDER` | Ex.: Vendas, Pós-venda, Renovações | Ex.: Venda de seguro, Renovação, Sinistro |
| `CRM_KANBAN.PIPELINE_DRAWER.STAGE_NAME_PLACEHOLDER` | Ex.: Qualificação | Ex.: Esperando a emissão |
| `CRM_KANBAN.PIPELINE_DRAWER.WHEN_TO_USE_HELP` | A IA lê este texto para saber quando uma conversa é deste funil. Diga quais produtos ou casos entram aqui. | A IA lê este texto para saber quando uma conversa é deste funil. Diga quais seguros ou casos entram aqui. |
| `CRM_KANBAN.PIPELINE_DRAWER.WHEN_TO_USE_PLACEHOLDER` | Ex.: venda dos nossos dois produtos, Agentes de IA e Chat2You. | Ex.: cotação de seguro do carro, da casa e de vida. |
| `CRM_KANBAN.STAGE_AUTOMATIONS.RULE_NAME_PLACEHOLDER` | Ex.: Criar retorno ao entrar | Ex.: Lembrar de cobrar a emissão |
| `CRM_KANBAN.AI_SETTINGS.ATTRIBUTE_EXTRACTION_HELP` | Extrai dados da conversa (cidade, segmento, valor, decisor e afins) e preenche qualquer campo customizado vazio do contato ou da conversa. Campo já preenchido nunca é sobrescrito. | Extrai dados da conversa (placa, CEP de pernoite, seguradora atual, vencimento e afins) e preenche qualquer campo customizado vazio do contato ou da conversa. Campo já preenchido nunca é sobrescrito. |
| `CRM_KANBAN.PIPELINE_EDITOR.CRITERIA_TIP` | Use sinais concretos, como “proposta enviada”. | Use sinais concretos, como “mandou as opções da cotação”. |
| `CRM_KANBAN.PASSAGEM.QUANDO.IDEIA_2` | Quando o cliente quiser fechar a compra | Quando o cliente escolher a opção e quiser fechar o seguro |
| `CRM_KANBAN.PASSAGEM.QUANDO.IDEIA_3` | Quando o cliente reclamar ou parecer irritado | Quando o cliente avisar um sinistro ou reclamar |
| `CRM_KANBAN.PASSAGEM.PREVIA.QUANDO_SIM_MSG` | Não entendi o valor da proposta. Quero falar com alguém. | Não entendi o valor da cotação. Quero falar com alguém. |
| `CRM_KANBAN.RELATIONSHIP.OPPORTUNITY_DETAILS` | Detalhes da oportunidade | Detalhes do card |
| `CRM_SLA.POLICIES.DIALOG.NAME.PLACEHOLDER` | ex.: Suporte prioritário | Ex.: Sinistro com resposta rápida |
| `CRM_CAIXAS.SOZINHO.AUTO_UM_EXEMPLO` | O cliente pede dois produtos diferentes: são dois cards em {funil}. | O cliente pede dois seguros diferentes: são dois cards em {funil}. |
| `CRM_CAIXAS.SOZINHO.MENSAGEM` | Oi! Quanto custa? | Oi! Quanto fica o seguro do meu carro? |
| `CRM_CAIXAS.SOZINHO.MENSAGEM_DOIS_PEDIDOS` | Quero saber o preço do plano básico e também do plano completo. | Quero cotar o seguro do carro e também o da casa. |

### Multifunnel e Followup (9)

| Chave | Hoje (geral) | Corretora |
|---|---|---|
| `CRM_CARD.RESUMO.NEGOCIO_DE` | Negócio: {titulo} | Seguro: {titulo} |
| `CRM_CARD.RESUMO.COBRANCA_FRASE` | {titulo}: {valor} a receber, vence {vencimento}. | {titulo}: parcela de {valor}, vence {vencimento}. |
| `CRM_CARD.RESUMO.COBRANCA_SEM_DATA` | {titulo}: {valor} a receber, sem vencimento. | {titulo}: parcela de {valor}, sem vencimento. |
| `CRM_CARD.RESUMO.COBRANCA_VENCEU` | {titulo}: {valor} a receber, venceu {vencimento}. | {titulo}: parcela de {valor}, venceu {vencimento}. |
| `CRM_CARD.COBRANCA.TITULO` | Sobre a cobrança | Sobre a parcela |
| `CRM_CARD.COBRANCA.TEXTO` | Quanto {nome} deve, quando vence e se prometeu pagar. | De quanto é a parcela de {nome}, quando vence e se prometeu pagar. |
| `CRM_CARD.COBRANCA.NOME` | O que está sendo cobrado | De qual seguro é a parcela |
| `CRM_CARD.COBRANCA.TITULO_EXEMPLO` | Ex.: Mensalidade de outubro | Ex.: Seguro do carro · parcela 3 de 10 |
| `CRM_CARD.COBRANCA.VALOR` | Valor a receber | Valor da parcela |

### Orquestração (Automações) (7)

| Chave | Hoje (geral) | Corretora |
|---|---|---|
| `AUTOMACOES.MODELOS.ORCAMENTO.TITULO` | Marcar quem pede orçamento | Marcar quem pede cotação |
| `AUTOMACOES.MODELOS.ORCAMENTO.TEXTO` | Quem pede preço ou orçamento ganha etiqueta e não se perde na fila. | Quem pede cotação recebe uma etiqueta e não fica esquecido na fila. |
| `AUTOMACOES.MODELOS.ORCAMENTO.QUANDO` | O cliente pede preço ou orçamento | O cliente pede uma cotação |
| `AUTOMACOES.MODELOS.ORCAMENTO.FAZ` | Coloca a etiqueta orçamento | Coloca a etiqueta cotação |
| `AUTOMACOES.MODELOS.ORCAMENTO.PEDIDO` | Quero uma automação: quando chegar uma mensagem de cliente pedindo preço ou orçamento, colocar a etiqueta orçamento na conversa. | Quero uma automação: quando chegar uma mensagem de cliente pedindo cotação de seguro, colocar a etiqueta cotação na conversa. |
| `AUTOMACOES.HEROI.EXEMPLO` | Ex.: quando um cliente pedir orçamento, avisar o time de vendas | Ex.: quando um cliente avisar um sinistro, passar para quem cuida de sinistros |
| `AUTOMACOES.HEROI.IDEIAS.ORCAMENTO` | Marcar quem pede orçamento | Marcar quem pede cotação |

