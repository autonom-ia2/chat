# Proposta: as 108 chaves do painel que só a corretora troca (#2083, lote 3)

Hoje a conta de saúde vê nessas chaves o texto da base, genérico. Para cada uma, a proposta é:

- **A. Igual à corretora:** o texto da corretora serve à saúde porque a conta também é uma corretora (nome,
  e-mail, site, "segunda via", "cotação parada").
- **B. Texto próprio da saúde.**
- **C. Fica a base:** o texto da base já serve, ou a decisão do lote 1 continua valendo.

O texto em inglês (`en.json`) sai junto, na implementação.

## B. Texto próprio da saúde (41)

| Chave | Hoje a saúde vê | Proposta |
|---|---|---|
| AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.AJUDA | Oi, preciso de ajuda | Oi, preciso da segunda via do boleto |
| AGENTS.JORNADA.CRIAR.CONFIRA.PERGUNTAS.SABADO | Vocês abrem no sábado? | Como faço o reembolso de uma consulta? |
| AGENTS.JORNADA.MODELOS.RECEPTION.AGENTE | Oi! Que bom ter você aqui. Sobre qual assunto você quer falar? | Oi! Que bom falar com você. É sobre um plano novo ou sobre o plano que você já tem? |
| AGENTS.JORNADA.MODELOS.RECEPTION.CLIENTE | Oi, preciso de ajuda | Oi, quero cotar um plano de saúde |
| AGENTS.JORNADA.MODELOS.RECEPTION.TEXTO | Dá as boas-vindas, entende o assunto e passa para a equipe. | Dá as boas-vindas, entende se é cotação, boleto ou reembolso e passa para a equipe. |
| AGENTS.JORNADA.PAGINA.GAVETA_AGENDA.EXEMPLO.CLIENTE | Oi! Queria marcar um horário. | Oi! Queria conversar sobre o plano de saúde da minha empresa. |
| AGENTS.JORNADA.PAGINA.TESTE.CHIPS.RECEPTION.A | Oi, preciso de ajuda | Oi, quero cotar um plano de saúde |
| AGENTS.JORNADA.PAGINA.TESTE.CHIPS.SUPPORT.B | Vocês abrem no sábado? | Como faço o reembolso de uma consulta? |
| AUTONOMIA_GUIDE.MEMORY.EXAMPLE_COMPANY_1 | Lembra que relatório aqui é sempre do mês corrente | Lembra que a venda conta no mês em que o plano é implantado |
| AUTONOMIA_GUIDE.MEMORY.EXAMPLE_COMPANY_2 | Lembra que a gente chama o funil principal de funil de vendas | Lembra que o funil principal é o de planos empresariais (PME) |
| BOOKING.PAGE.SUBTITLE | Crie a página onde o cliente marca um horário com você. | Crie a página onde a pessoa marca um horário para falar do plano com você. |
| BOOKING.PREVIEW.PUBLISHED_TEXT | Mande o link para seus clientes ou mostre o QR code. | Mande o link junto com a cotação ou no aniversário do contrato, ou mostre o QR code. |
| CAMPAIGN.EMAIL_CAMPAIGN.AI.COMPOSER.ASSET_DESCRIPTION_PLACEHOLDER | Ex.: vídeo de depoimento do cliente | Ex.: tabela de preços do plano por faixa de idade |
| CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_NAME_PLACEHOLDER | ex.: Convite para live | ex.: Aniversário do contrato |
| CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_PLACEHOLDER | ex.: promo@suaempresa.com | ex.: planos@suacorretora.com.br |
| CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_PLACEHOLDER | ex.: Marketing Acme | ex.: Sua Corretora de Planos de Saúde |
| CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_PLACEHOLDER | ex.: Boletim de junho | ex.: Planos PME de novembro |
| CAMPAIGN.EMAIL_SENDER.DIALOG.FROM_EMAIL_PLACEHOLDER | ex.: marketing@suaempresa.com | ex.: planos@suacorretora.com.br |
| CAMPAIGN.WHATSAPP_API.CREATE.FORM.TITLE.PLACEHOLDER | Ex: Reativação Junho | Ex.: Plano PME, novembro |
| CAMPAIGN_JOURNEY.LIVE_CHAT.URL_PLACEHOLDER | https://www.seusite.com.br/planos | https://www.suacorretora.com.br/planos-de-saude |
| CONVERSA_CANAL.JANELA.LOCALIZACAO.AJUDA | O cliente recebe o lugar no mapa. | O cliente recebe o lugar no mapa. Ex.: o endereço da corretora. |
| CRM_CALENDARIO.EXEMPLO.LEMBRETE | Ex.: ligar para um cliente na sexta | Ex.: ligar para o cliente sobre o aniversário do contrato na sexta |
| CRM_CARD.NEGOCIO.OBSERVACOES_EXEMPLO | O que a equipe precisa saber | Ex.: quer manter o mesmo hospital da rede atual |
| CRM_KANBAN.CALENDAR.MEETING_SCHEDULER.SUBTITLE | Agende uma reunião para este card… | Agende uma reunião sobre este plano e envie convites de agenda aos convidados. |
| CRM_KANBAN.PASSAGEM.QUANDO.IDEIA_3 | Quando o cliente reclamar ou parecer irritado | Quando o cliente reclamar de uma autorização negada ou da operadora |
| CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.NEGOTIATION.HELP | O cliente está acertando valores, condições ou próximos passos. | O cliente está acertando valor, operadora ou rede. |
| CRM_KANBAN.STAGE_AUTOMATIONS.RULE_NAME_PLACEHOLDER | Ex.: Criar retorno ao entrar | Ex.: Lembrar de cobrar a documentação |
| CUSTOM_ROLE.MATRIX.MODULES.CRM.HINT | Funis, cards e agenda | Funis de venda e de carteira, e a agenda |
| CUSTOM_ROLE.MATRIX.MODULES.CRM.LEVEL_MANAGE | Cria, edita e move cards. | Cria, edita e move cards: cotações e planos da carteira. |
| CUSTOM_ROLE.PROFILES.SALES_MANAGER.WHO | Para quem é dono do funil e da meta comercial. | Para quem cuida dos funis e da meta da corretora. |
| HELP_CENTER.CENTRAL_DE_AJUDA.BUSCA.DICA | Exemplos: conectar o WhatsApp, trocar a senha, criar um funil. | Exemplos: conectar o WhatsApp, marcar que o plano foi implantado, ver os planos implantados. |
| HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.FAMILIAS.VENDER | Vender e medir | Vender planos e medir |
| HELP_CENTER.CENTRAL_DE_AJUDA.POR_ASSUNTO.NOMES.CRM | CRM e funis | CRM: vendas e carteira |
| MODELOS_WHATSAPP.OBJETIVOS.promocao.PARA | Para avisar de uma oferta com prazo. | Para avisar de uma condição especial com prazo para contratar o plano. |
| MODELOS_WHATSAPP.OBJETIVOS.promocao.TITULO | Promoção | Oferta de plano |
| ONBOARDING_TRAIL.ETAPAS.organizar | Organizar as vendas | Organizar vendas e carteira |
| RELATIONSHIPS.MEDIA.EMPTY_HINT | Os arquivos das conversas autorizadas desta empresa aparecerão aqui. | Os arquivos das conversas autorizadas desta empresa, como boletos e carteirinhas, aparecem aqui. |
| RELATIONSHIPS.MEDIA.SUBTITLE | Arquivos compartilhados nas conversas. | Boletos, carteirinhas, documentos e fotos trocados nas conversas. |
| CRM_KANBAN.PIPELINE_EDITOR.META_PROGRESS.INTEREST.HELP | O cliente iniciou contato ou pediu informações. | O cliente pediu uma cotação ou informação. |
| AGENTS.JORNADA.CRIAR.CONTE.EXEMPLO_COPILOTO | Ex.: resumir as conversas e sugerir respostas para a equipe | Ex.: resumir a conversa e dizer o que falta para cotar |
| CRM_KANBAN.CALENDAR.QUICK_ADD.TITLE_PLACEHOLDER | Ex.: Ligar para confirmar a proposta | Ex.: Mandar as opções da cotação |

## A. Igual à corretora (30)

Nome, e-mail e site da corretora:
- AUTONOMIA_GUIDE.MEMORY.ABOUT_COMPANY, EMPTY_COMPANY_TITLE, ONLY_ADMIN;
- BRAND_KITS (3 chaves);
- CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_PLACEHOLDER;
- CAMPAIGN.EMAIL_SENDER.DIALOG.DOMAIN_PLACEHOLDER;
- GENERAL_SETTINGS.FORM (2 chaves);
- INBOX_MGMT.EDIT.SENDER_NAME_SECTION.BUSINESS_NAME.PLACEHOLDER;
- MODELOS_WHATSAPP.CAMPOS.nome_empresa (2 chaves) e EXTRAS.RODAPE_EXEMPLO;
- MODELOS_WHATSAPP.OBJETIVOS.lembrete.TEXTO;
- ONBOARDING_NEXT (3 chaves);
- ONBOARDING_TRAIL.TITLE e DONE_TITLE;
- SETTINGS_INICIO.CARTOES (3 chaves).

Cotação, segunda via e reunião com empresa, palavras que a saúde também usa:
- BOOKING.TEMPLATE.VISIT.NAME;
- CRM_NUMEROS_V2.TOPO.BOTAO.MEUS_PARADOS;
- INBOX_MGMT.WHATSAPP_HYBRID.ROUTING (5 chaves).

## C. Fica a base (37)

- **Texto igual ao da corretora** (a corretora só repete a base), 13 chaves:
  - CRM_CALENDARIO.NOVO.SEM_NEGOCIO_TEXTO;
  - CRM_CARD.CONTATO.TEXTO;
  - CRM_CARD.PESSOA (2 chaves);
  - CRM_KANBAN.RELATIONSHIP (4 chaves);
  - CRM_LEMBRETE.LIGAR (2 chaves);
  - CRM_MENSAGEM_MARCADA.CONFIRMAR (2 chaves);
  - CUSTOM_ROLE.MATRIX.MODULES.CRM.LEVEL_VIEW.
- **Também iguais ou neutras:** MODELOS_WHATSAPP.PONTE (2 chaves), CRM_KANBAN.CALENDAR.QUICK_ADD.ADVANCED_HINT e AGENTS.OUTRO_SISTEMA.NOME_EXEMPLO.
- **"Card" continua card:** CRM_KANBAN.ACTIONS.NEW_CARD e VIEW_OPPORTUNITIES, FILTERS.SHORTCUT_MINE, CONTACT_OPPORTUNITIES (4 chaves).
  - É a regra da instrução do Guia da saúde ("o item do funil é card").
  - A aba do contato também lista o card de Carteira, que não é cotação.
- **Meta e receita:** CRM_KANBAN.DASHBOARD.KPI.GOAL, CRM_DASHBOARD.ORIGIN (2 chaves), CRM_FUNIL.RESUMO.META e CUSTOM_ROLE.PROFILES.SALES_MANAGER.SHORT.
  - "Produção" é jargão de seguro.
- **Já servem:** CRM_FUNIL.TIPO.VENDER.TEXTO, CAMPAIGN_JOURNEY.LIVE_CHAT (NAME e TEXT, que já falam de planos) e CRM_KANBAN.PIPELINE_EDITOR.CRITERIA_TIP ("proposta enviada").
- **Desfecho (decisão do lote 1):** CRM_CARD.DESFECHO.MOTIVO.NAO_ERA_HORA e PERDEU_TEXTO.
  - A recusa da operadora não é perda.
  - "Não fechou" vale para todo o pacote seguros.
- **Cuidado:** HELP_CENTER…NOMES.FINANCEIRO continua "Financeiro".
  - A corretora usa "Seu plano e faturas", mas na saúde "plano" quer dizer plano de saúde e confundiria.
- **Já sem apólice:** MODELOS_WHATSAPP.TOPOS.documento.AJUDA. A base já não fala em apólice.

Total: 41 + 30 + 37 = 108. Aprovada pelo Rodrigo em 25/10/2026, com o chip do dermatologista trocado pela pergunta
de reembolso.
