# F2 corretora · Lote 5: Agentes, Agendamento e Relatórios

autonom-ia2/chat#1802, 19/10/2026. Vem depois dos lotes 1 (#1843), 2 (#1853), 3 (#1860) e 4, que mexem no mesmo arquivo do pacote.

É só texto, no pacote `seguros/corretora`. A conta geral não muda.

## O que entra

São 56 textos do painel e 7 do servidor.

- **Agentes de IA:**
  - os modelos prontos falam de seguro: "Atender quem quer fazer seguro", a segunda via do boleto, "Oi, bati o carro";
  - as perguntas de teste deixam o corretor ver como o agente responde a preço e cobertura ("Quanto fica o seguro do meu carro?", "Meu seguro cobre carro reserva?"); são só sugestões de pergunta, sem conferência automática;
  - as ideias do primeiro passo são de corretora (auto, vários seguros, vida, empresarial);
  - a base de conhecimento pede condições gerais e lista de documentos, e não cardápio nem tabela de preços.
- **Automação e robôs:** a descrição e os exemplos falam da etiqueta do seguro e de passar a conversa para quem cuida.
- **Agendamento (painel):** os modelos de página viram "Conversa para cotar", "Atendimento no escritório" e "Reunião com empresa"; o link vai junto com a cotação ou a renovação.
- **Agendamento (servidor):** a página nova nasce com o título e a descrição do modelo da corretora, e o card do agendamento herda esse título ("Ana - Conversa para cotar o seguro").
- **Relatórios:** etiquetas e times com exemplos de corretora.
- **Lembrete por e-mail (servidor):** "Marcado para" no lugar de "Vence em", que o corretor leria como o vencimento do seguro. Serve também ao lembrete que não é retorno ao cliente (lembretes novos).

## O que ficou de fora, e por quê

- **Avisos do agendamento ao cliente:** continuam com "horário" (decisão D5, opção b). Eles saem por job, e o job ainda não carrega o pacote; trocar só a prévia do painel faria a equipe ver um texto e o cliente receber outro.
- **Página pública de agendamento e prévia do link:** o pacote não chega lá (exige código).
- **Ferramentas do agente** (exemplo "Busca no estoque"): o exemplo é preenchido pelo código; trocar só o texto deixaria a ajuda e o exemplo em desacordo. Vai com o código.
- **Valor na planilha do CRM:** fica "Valor", como no card (decisão do lote 1).
- **Não se mexe:** a Lia (Cotação), os sinais e rascunhos do Construtor, o modelo de estoque da tela antiga, os modelos aprovados na Meta e os botões dos avisos.

## Ajustes sobre o inventário

- **"Pessoa" no lugar de "cliente"** onde a pessoa ainda está cotando: as perguntas "achou a cotação cara" e "sumiu depois das opções", o subtítulo da página de agendamento e o texto do link publicado. É a regra da Base de Clientes.
- **"Sobra tempo" no lugar de "ganha tempo"** na descrição da automação: o pacote não usa "ganh" (trava de cobertura).
- **Times de exemplo do relatório iguais aos do lote 3:** vendas, renovação, sinistro.
- **O agente não faz o trabalho da Lia (cotação) nem promete o que não faz** (Agentes IA): o SDR entende qual seguro a pessoa procura e passa para a equipe, sem levantar dados de cotação; o suporte chama a equipe para a segunda via; os exemplos falam de condições gerais e documentos, não de coberturas; o SDR ganha um teste de preço ("Quanto fica, mais ou menos?"); a recepção testa "Oi, bati o carro".
- **Etiquetas com inicial maiúscula** nos exemplos do relatório, como aparecem na tela (Max).
- **"Escreva" no lugar de "Rascunhe"** na pergunta de teste do copiloto (revisão).
- **Inglês:** "bill copy" no lugar de "duplicate bill" em todo o pacote, inclusive nos textos dos lotes 2 e 3, para o inglês ficar igual em tudo (revisão).

## Os textos, por dono

### Agentes IA: modelos prontos, perguntas de teste, Conte e página do agente (43)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `AGENTS.JORNADA.MODELOS.SUPPORT.TEXTO` | Responde sobre preços, horários, entrega e o que mais perguntarem. | Tira dúvidas sobre o seguro, a parcela, a segunda via e o que mais perguntarem. |
| 2 | `AGENTS.JORNADA.MODELOS.SUPPORT.CLIENTE` | Vocês abrem no sábado? | Como peço a segunda via do boleto? |
| 3 | `AGENTS.JORNADA.MODELOS.SUPPORT.AGENTE` | Abrimos sim, das 9h às 13h. Posso ajudar em mais alguma coisa? | Eu chamo alguém da equipe para te ajudar com a segunda via. |
| 4 | `AGENTS.JORNADA.MODELOS.SDR.TITULO` | Atender quem quer comprar | Atender quem quer fazer seguro |
| 5 | `AGENTS.JORNADA.MODELOS.SDR.TEXTO` | Entende o que a pessoa procura e passa para a equipe fechar. | Entende qual seguro a pessoa procura e passa para a equipe. |
| 6 | `AGENTS.JORNADA.MODELOS.SDR.CLIENTE` | Quero fazer um pedido | Quero fazer o seguro do meu carro |
| 7 | `AGENTS.JORNADA.MODELOS.SDR.AGENTE` | Que bom! Me conta o que você procura que já chamo alguém da equipe. | Que bom! Me conta qual é o carro que já chamo alguém da equipe. |
| 8 | `AGENTS.JORNADA.MODELOS.RECEPTION.TEXTO` | Dá as boas-vindas, entende o assunto e passa para a equipe. | Dá as boas-vindas, entende se é cotação, parcela ou sinistro e passa para a equipe. |
| 9 | `AGENTS.JORNADA.MODELOS.RECEPTION.CLIENTE` | Oi, preciso de ajuda | Oi, bati o carro |
| 10 | `AGENTS.JORNADA.MODELOS.RECEPTION.AGENTE` | Oi! Que bom ter você aqui. Sobre qual assunto você quer falar? | Poxa, sinto muito. Está todo mundo bem? Já chamo a equipe para te ajudar. |
| 11 | `AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.A` | Quanto custa? | Quanto fica o seguro do meu carro? |
| 12 | `AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.B` | Vocês abrem no sábado? | Meu seguro cobre carro reserva? |
| 13 | `AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SDR.A` | Quero fazer um pedido | Quero fazer o seguro do meu carro |
| 14 | `AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SDR.B` | Tem desconto? | Quanto fica, mais ou menos? |
| 15 | `AGENTS.JORNADA.PAGINA.TESTE.CHIPS.RECEPTION.B` | Quero trocar um produto | Troquei de carro. Como mudo no seguro? |
| 16 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.QUANTO_CUSTA` | Quanto custa? | Quanto fica o seguro do meu carro? |
| 17 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.SABADO` | Vocês abrem no sábado? | Meu seguro cobre carro reserva? |
| 18 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.PEDIDO` | Quero fazer um pedido | Quero fazer o seguro do meu carro |
| 19 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.DESCONTO` | Tem desconto? | Quanto fica, mais ou menos? |
| 20 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.TROCAR` | Quero trocar um produto | Troquei de carro. Como mudo no seguro? |
| 21 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.COMO_RESPONDO` | Um cliente pediu desconto. Como respondo? | A pessoa achou a cotação cara. Como respondo? |
| 22 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.PROXIMO_PASSO` | O cliente parou de responder. Qual o próximo passo? | Mandei as opções da cotação e a pessoa sumiu. Qual o próximo passo? |
| 23 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.RASCUNHO` | Rascunhe uma resposta sobre o prazo de entrega | Escreva uma mensagem pedindo a CNH e o documento do carro |
| 24 | `AGENTS.JORNADA.CRIAR.CONTE.IDEIAS.ROUPAS` | Loja de roupas | Corretora de seguro auto |
| 25 | `AGENTS.JORNADA.CRIAR.CONTE.IDEIAS.DOCES` | Confeitaria | Corretora de vários seguros |
| 26 | `AGENTS.JORNADA.CRIAR.CONTE.IDEIAS.ESTETICA` | Clínica de estética | Corretora de vida e saúde |
| 27 | `AGENTS.JORNADA.CRIAR.CONTE.IDEIAS.OFICINA` | Oficina mecânica | Seguro empresarial e de carga |
| 28 | `AGENTS.JORNADA.CRIAR.CONTE.EXEMPLO_DO_MEU_JEITO` | Ex.: responder dúvidas de preço e entrega da minha loja | Ex.: tirar dúvidas sobre o seguro do carro e passar para a equipe |
| 29 | `AGENTS.JORNADA.CRIAR.CONTE.EXEMPLO_COPILOTO` | Ex.: resumir as conversas e sugerir respostas para a equipe | Ex.: resumir a conversa e dizer o que falta para cotar |
| 30 | `AGENTS.JORNADA.CRIAR.CONTE.EXEMPLO_AJUDANTE` | Ex.: tirar as dúvidas mais difíceis sobre os produtos para os outros agentes | Ex.: tirar as dúvidas sobre as condições gerais para os outros agentes |
| 31 | `AGENTS.JORNADA.CRIAR.CONTE.ANEXO_FRASE` | Tem um cardápio, uma tabela ou o seu site? {acao} Não é obrigatório. | Tem as condições gerais, uma lista de perguntas comuns ou o seu site? {acao} Não é obrigatório. |
| 32 | `AGENTS.JORNADA.CRIAR.BASE.VAZIO` | Ainda não tem nada aqui. Mande um cardápio, uma tabela de preços ou o endereço do seu site. | Ainda não tem nada aqui. Mande as condições gerais, a lista de documentos de cada seguro ou o endereço do seu site. |
| 33 | `AGENTS.JORNADA.CRIAR.BASE.SITE_EXEMPLO` | www.sualoja.com.br | www.suacorretora.com.br |
| 34 | `AGENTS.JORNADA.PAGINA.SABE.ENVIAR_ARQUIVO_TEXTO` | Cardápio, tabela de preços, catálogo. Até 25 MB. | Condições gerais, lista de documentos, perguntas comuns. Até 25 MB. |
| 35 | `AGENTS.JORNADA.PAGINA.SABE.SITE_ERRO` | Confira o endereço do site. Ex.: www.sualoja.com.br | Confira o endereço do site. Ex.: www.suacorretora.com.br |
| 36 | `AGENTS.JORNADA.PAGINA.MUDAR_VISTA.CHIPS_GERAL.B` | Mudar preços ou regras | Mudar regras ou documentos pedidos |
| 37 | `AGENTS.JORNADA.AJUDANTE.QUANDO.EXEMPLO` | Ex.: quando a dúvida for sobre trocas e devoluções | Ex.: quando a dúvida for sobre as condições gerais ou os documentos |
| 38 | `AGENTS.JORNADA.PAGINA.GAVETA_AGENDA.EXEMPLO.CLIENTE` | Oi! Queria marcar um horário. | Oi! Queria conversar sobre o seguro da minha empresa. |
| 39 | `AGENTS.OUTRO_SISTEMA.NOME_EXEMPLO` | Ex.: Automação Vendas | Ex.: Robô do site |
| 40 | `AGENTS.OUTRO_SISTEMA.DESCRICAO_EXEMPLO` | Ex.: Responde dúvidas de preço e passa para a equipe. | Ex.: tira dúvidas sobre o seguro e passa para a equipe |
| 41 | `AGENTS.TUNE.GREETING_PLACEHOLDER` | Olá! Como posso ajudar você hoje? | Olá! Tudo bem? Como posso ajudar com o seu seguro? |
| 42 | `AGENTS.JORNADA.PAGINA.TESTE.CHIPS.RECEPTION.A` | Oi, preciso de ajuda | Oi, bati o carro |
| 43 | `AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.AJUDA` | Oi, preciso de ajuda | Oi, bati o carro |

### Agentes IA: automação e robôs (4)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `AUTOMATION.DESCRIPTION` | A automação pode substituir e simplificar processos existentes que requerem esforço manual, como a adição de etiquetas e a atribuição de conversas ao agente mais adequado. Isso permite que o time se concentre em seus pontos fortes e reduza o tempo gasto em tarefas rotineiras. | A automação faz sozinha o trabalho repetido, como pôr a etiqueta certa (auto, residencial, sinistro) e passar a conversa para quem cuida dela. Assim sobra tempo para a equipe cotar e atender. |
| 2 | `AUTOMATION.ADD.FORM.NAME.PLACEHOLDER` | Inserir nome da regra | Ex.: Etiqueta de sinistro |
| 3 | `AUTOMATION.ADD.FORM.DESC.PLACEHOLDER` | Inserir descrição de regra | Ex.: põe a etiqueta sinistro e passa para o time de sinistro |
| 4 | `AGENT_BOTS.FORM.DESCRIPTION.PLACEHOLDER` | O que esse robô faz? | Ex.: tira dúvidas sobre o seguro e passa para a equipe |

### Página de agendamento: painel (6)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `BOOKING.PAGE.SUBTITLE` | Crie a página onde o cliente marca um horário com você. | Crie a página onde a pessoa marca um horário para falar do seguro com você. |
| 2 | `BOOKING.TEMPLATE.SALES.NAME` | Conversa de vendas | Conversa para cotar |
| 3 | `BOOKING.TEMPLATE.CONSULT.NAME` | Consulta ou atendimento | Atendimento no escritório |
| 4 | `BOOKING.TEMPLATE.VISIT.NAME` | Visita | Reunião com empresa |
| 5 | `BOOKING.LOOK.HEADLINE_PLACEHOLDER` | Escolha o melhor horário para você | Escolha o melhor horário para falar do seu seguro |
| 6 | `BOOKING.PREVIEW.PUBLISHED_TEXT` | Mande o link para seus clientes ou mostre o QR code. | Mande o link junto com a cotação ou a renovação, ou mostre o QR code. |

### Frontend geral: relatórios (3)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `LABEL_REPORTS.DESCRIPTION` | Acompanhe o desempenho da sua etiqueta com métricas-chave incluindo conversas, tempo de resposta, tempos de resolução e casos resolvidos. Clique no nome da etiqueta para obter detalhes. | Veja, por etiqueta, quantas conversas chegaram e quanto tempo a equipe levou para responder e resolver. Ex.: Auto, Residencial, Sinistro, Segunda via. Clique numa etiqueta para ver mais. |
| 2 | `LABEL_REPORTS.FILTERS.INPUT_PLACEHOLDER.LABELS` | Pesquisar etiquetas | Buscar etiqueta. Ex.: sinistro |
| 3 | `TEAM_REPORTS.DESCRIPTION` | Tenha uma visão geral do desempenho dos seus times com métricas essenciais, incluindo conversas, tempos de resposta, tempos de resolução e casos resolvidos. Clique no nome do time para ver mais detalhes. | Veja como cada time está: conversas, tempo para responder e tempo para resolver. Ex.: vendas, renovação, sinistro. Clique num time para ver mais. |

### Servidor (7)

| Chave | Geral | Corretora |
|---|---|---|
| `crm.follow_up_reminder.due_at` | Vence em: %{time} | Marcado para: %{time} |
| `crm.booking_v2.templates.sales_30.title` | Conversa de vendas de 30 min | Conversa para cotar o seguro |
| `crm.booking_v2.templates.sales_30.description` | Escolha um horário e a gente conversa por vídeo no WhatsApp. | Escolha um horário e a gente faz a cotação do seu seguro por vídeo no WhatsApp. |
| `crm.booking_v2.templates.consult_45.title` | Consulta de 45 min | Atendimento no escritório |
| `crm.booking_v2.templates.consult_45.description` | Escolha um horário para a consulta presencial. | Escolha um horário para falar do seu seguro aqui no escritório. |
| `crm.booking_v2.templates.visit_60.title` | Visita de 60 min | Reunião sobre o seguro da empresa |
| `crm.booking_v2.templates.visit_60.description` | Escolha um horário para a visita presencial de uma hora. | Escolha um horário para a reunião presencial sobre o seguro da sua empresa. |
