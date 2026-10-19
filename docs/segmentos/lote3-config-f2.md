# F2 corretora · Lote 3: Configurações e entrada

autonom-ia2/chat#1802, 19/10/2026. Vem depois dos lotes 1 (#1843) e 2, que mexem no mesmo arquivo do pacote.

É só texto, no pacote `seguros/corretora`. A conta geral não muda.

## O que entra

São 68 textos do painel.

- **Configurações › Início:** "Sua corretora" e "Dados da corretora". Os cartões trazem exemplos de times, etiquetas e campos.
- **Primeiros passos:** "Vamos deixar sua corretora pronta para atender" e "Organizar vendas e renovações".
- **Conta e perfil:**
  - nome e e-mail da corretora;
  - a mensagem de encerramento automático, com cotação, segunda via e sinistro;
  - a assinatura "Ana Souza · Corretora de seguros".
- **Usuários e times:** quem vende, quem atende e quem cuida de renovação e sinistro. Times de exemplo: Vendas, Renovação e Sinistro.
- **Etiquetas e campos extras:**
  - etiquetas de exemplo: auto, residencial, vistoria pendente e sinistro;
  - campos de exemplo: Seguradora, Vencimento do seguro, Ramo e Placa.
- **Funções personalizadas:**
  - perfil "Corretor" (cota e fecha seguros novos);
  - gestor com "meta de produção";
  - atendente com dúvidas, segunda via e endosso;
  - no CRM, "card" no lugar de "oportunidade".
- **Caixas de entrada:**
  - nomes de exemplo por assunto;
  - boas-vindas do site com cotação, segunda via e sinistro;
  - a saudação manda ligar para a assistência 24 horas;
  - o caso de uso do WhatsApp fala de cotações;
  - as prévias do Híbrido usam a cotação parada e a segunda via.

## O que ficou de fora, e por quê

- **SLA:** a tela não está no menu.
- **Os passos da trilha (`trilha.yml`):** são texto fixo no código, e o pacote não alcança.
- **O setor do onboarding e o cadastro e login (`v3`):** também não carregam pacote. Vai como lacuna.
- **O "cotando" da trilha e o caso de uso do WhatsApp no pt geral:** precisam ser neutralizados no catálogo geral. É o lote 0, com PR por dono.
- **Não se mexe:** menu "Contatos", a Lia (Cotação, Conexões, Agente), modelos da Meta (CSAT), Captain e faturamento.

## Ajustes sobre o inventário

- **"Corretor" no lugar de "Vendedor (SDR)":** o Rodrigo decidiu "corretor", nunca vendedor nem produtor.
- **"Endosso" no lugar de "alteração na apólice":** é o nome certo para a mudança na apólice.
- **"Contato" no lugar de "cliente" nas etiquetas e nos campos:** valem para qualquer pessoa, não só para quem comprou. É a regra da Base de Clientes.

## Os textos, por dono

### Reorganização do sidebar: Configurações › Início (9)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `SETTINGS_INICIO.GRUPOS.SUA_EMPRESA` | Sua empresa | Sua corretora |
| 2 | `SETTINGS_INICIO.CARTOES.DADOS_EMPRESA.TITULO` | Dados da empresa | Dados da corretora |
| 3 | `SETTINGS_INICIO.CARTOES.DADOS_EMPRESA.TEXTO` | Nome, idioma e fuso da sua conta. | Nome da corretora, idioma e fuso da conta. |
| 4 | `SETTINGS_INICIO.CARTOES.TIMES.TEXTO` | Grupos de pessoas para dividir o trabalho. | Grupos de pessoas para dividir o trabalho, como Vendas, Renovação e Sinistro. |
| 5 | `SETTINGS_INICIO.CARTOES.ETIQUETAS.TEXTO` | Nomes e cores para separar conversas e clientes. | Nomes e cores para separar conversas e contatos, como auto, residencial e sinistro. |
| 6 | `SETTINGS_INICIO.CARTOES.CAMPOS.TEXTO` | Informações a mais que você quer guardar de cada cliente. | Informações a mais de cada contato, como seguradora, vencimento do seguro e placa do carro. |
| 7 | `SETTINGS_INICIO.CARTOES.RESPOSTAS.TEXTO` | Textos que você usa sempre, a um clique na conversa. | Textos que você usa sempre, como pedir a CNH ou mandar a segunda via, a um clique na conversa. |
| 8 | `SETTINGS_INICIO.CARTOES.CANAIS.TEXTO` | WhatsApp, e-mail, Instagram e site: por onde o cliente fala com você. | WhatsApp, e-mail, Instagram e site: por onde o cliente pede cotação e fala com você. |
| 9 | `SETTINGS_INICIO.CARTOES.USUARIOS.TEXTO` | Quem entra na plataforma e o que cada pessoa pode fazer. | Quem da corretora entra na plataforma e o que cada pessoa pode fazer. |

### Onboarding e Orquestração: trilha e entrada (7)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 10 | `ONBOARDING_TRAIL.TITLE` | Vamos deixar seu atendimento pronto | Vamos deixar sua corretora pronta para atender |
| 11 | `ONBOARDING_TRAIL.DONE_TITLE` | Seu atendimento está funcionando | Sua corretora já está atendendo |
| 12 | `ONBOARDING_TRAIL.DONE_SUBTITLE` | O essencial está pronto: você recebe, responde e organiza. O que sobrou é ajuste fino, no seu tempo. | O essencial está pronto: você recebe, responde e organiza cotações e renovações. O que sobrou é ajuste fino, no seu tempo. |
| 13 | `ONBOARDING_TRAIL.ETAPAS.organizar` | Organizar as vendas | Organizar vendas e renovações |
| 14 | `ONBOARDING_NEXT.PLACEHOLDERS.ENTER_COMPANY_NAME` | Nome da sua empresa | Nome da sua corretora |
| 15 | `ONBOARDING_NEXT.PLACEHOLDERS.ENTER_WEBSITE` | www.exemplo.com | www.suacorretora.com.br |
| 16 | `ONBOARDING_NEXT.COMPANY_DETAILS` | Detalhes da empresa | Dados da corretora |

### Frontend geral: conta, perfil, fluxo, usuários e times (11)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 17 | `GENERAL_SETTINGS.FORM.NAME.PLACEHOLDER` | Nome da sua conta | Nome da sua corretora |
| 18 | `GENERAL_SETTINGS.FORM.SUPPORT_EMAIL.PLACEHOLDER` | E-mail de suporte da sua empresa | E-mail de atendimento da corretora |
| 19 | `GENERAL_SETTINGS.FORM.AUTO_RESOLVE.MESSAGE.PLACEHOLDER` | A conversa foi marcada como resolvida pelo sistema por ter 15 dias de inatividade | Encerramos esta conversa por falta de resposta. Precisa de cotação, segunda via ou ajuda com sinistro? É só mandar mensagem. |
| 20 | `PROFILE_SETTINGS.FORM.MESSAGE_SIGNATURE.PLACEHOLDER` | Insira aqui a assinatura de sua mensagem pessoal. | Ex.: Ana Souza · Corretora de seguros |
| 21 | `CONVERSATION_WORKFLOW.INDEX.HEADER.DESCRIPTION` | Configure regras e campos obrigatórios para a resolução de conversas. | Escolha o que precisa estar preenchido antes de encerrar uma conversa, como o ramo do seguro. |
| 22 | `CONVERSATION_WORKFLOW.REQUIRED_ATTRIBUTES.DESCRIPTION` | Ao resolver uma conversa, os agentes serão solicitados a preencher esses atributos caso ainda não o tenham feito. | Antes de encerrar a conversa, a equipe preenche estes campos, como o ramo do seguro ou a seguradora. |
| 23 | `AGENT_MGMT.DESCRIPTION` | Um agente é um membro de seu time de atendimento ao cliente que pode visualizar e responder às mensagens de usuários. A lista abaixo mostra todos os agentes de sua conta. | Aqui ficam as pessoas da corretora que entram na plataforma: quem vende, quem atende e quem cuida de renovação e sinistro. |
| 24 | `AGENT_MGMT.ADD.DESC` | Você pode adicionar pessoas que poderão acompanhar o suporte de suas caixas de entrada. | Convide quem vai atender: vendas, renovação ou sinistro. |
| 25 | `TEAMS_SETTINGS.DESCRIPTION` | Os times permitem que você organize agentes em grupos com base em suas responsabilidades. Um agente pode pertencer a vários times. Ao trabalhar de forma colaborativa, você pode atribuir conversas a times específicos. | Times juntam as pessoas por assunto, como Vendas, Renovação e Sinistro. Uma pessoa pode estar em vários times, e a conversa pode ir direto para o time certo. |
| 26 | `TEAMS_SETTINGS.FORM.NAME.PLACEHOLDER` | Exemplo: Vendas, Suporte ao Cliente | Ex.: Vendas, Renovação, Sinistro |
| 27 | `TEAMS_SETTINGS.FORM.DESCRIPTION.PLACEHOLDER` | Breve descrição sobre este time. | Ex.: Cuida dos avisos de sinistro e dos documentos que faltam. |

### Base de Clientes: etiquetas e campos (12)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 28 | `LABEL_MGMT.DESCRIPTION` | As etiquetas ajudam você a categorizar e priorizar conversas e leads. Você pode atribuir uma etiqueta a uma conversa ou contato usando o painel lateral. | As etiquetas separam conversas e contatos por assunto, como auto, residencial, vistoria pendente ou sinistro. Você põe a etiqueta pelo painel ao lado da conversa ou do contato. |
| 29 | `LABEL_MGMT.LIST.404` | Não há etiquetas disponíveis nesta conta. | Nenhuma etiqueta ainda. Para começar, crie auto, residencial e sinistro. |
| 30 | `LABEL_MGMT.ADD.DESC` | Etiquetas permitem agrupar as conversas. | Etiquetas separam as conversas por assunto, como renovação ou sinistro. |
| 31 | `LABEL_MGMT.FORM.NAME.PLACEHOLDER` | Nome da etiqueta | Ex.: vistoria-pendente |
| 32 | `LABEL_MGMT.FORM.DESCRIPTION.PLACEHOLDER` | Descrição da etiqueta | Ex.: Cliente que ainda precisa fazer a vistoria do carro |
| 33 | `LABEL_MGMT.FORM.NAME.VALID_ERROR` | Somente Letras, Números, Hífen e Sublinhado são permitidos | Sem espaço: use hífen. Ex.: segunda-via |
| 34 | `ATTRIBUTES_MGMT.DESCRIPTION` | Um atributo personalizado controla detalhes adicionais sobre seus contatos ou conversas — como o plano de assinatura ou a data de sua primeira compra. Você pode adicionar diferentes tipos de atributos personalizados, como texto, listas ou números, para capturar as informações específicas que você precisa. | Campos extras guardam o que a corretora precisa saber de cada contato, como a seguradora atual, o vencimento do seguro, o ramo e a placa do carro. Pode ser texto, lista, número ou data. |
| 35 | `ATTRIBUTES_MGMT.ADD.FORM.NAME.PLACEHOLDER` | Digite um nome de exibição de atributo personalizado | Ex.: Vencimento do seguro |
| 36 | `ATTRIBUTES_MGMT.ADD.FORM.DESC.PLACEHOLDER` | Inserir descrição do atributo personalizado | Ex.: Dia em que o seguro atual vence |
| 37 | `ATTRIBUTES_MGMT.ADD.FORM.TYPE.LIST.PLACEHOLDER` | Por favor, digite o valor e pressione Enter | Ex.: Auto, Residencial, Vida. Digite cada um e aperte Enter |
| 38 | `ATTRIBUTES_MGMT.ADD.FORM.KEY.PLACEHOLDER` | Digite a chave de atributo personalizada | Ex.: vencimento_seguro |
| 39 | `ATTRIBUTES_MGMT.LIST.EMPTY_RESULT.404` | Não há atributos personalizados criados | Nenhum campo extra ainda. Para começar: Seguradora, Vencimento do seguro, Ramo e Placa. |

### Funções personalizadas (14)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 40 | `CUSTOM_ROLE.FORM.NAME.PLACEHOLDER` | Ex.: Atendente noturno | Ex.: Atendente de sinistro |
| 41 | `CUSTOM_ROLE.FORM.DESCRIPTION.PLACEHOLDER` | Ex.: Equipe de plantão que atende só as próprias conversas | Ex.: Quem cuida de sinistro e segunda via, só nas próprias conversas |
| 42 | `CUSTOM_ROLE.PROFILES.SDR.NAME` | Vendedor (SDR) | Corretor |
| 43 | `CUSTOM_ROLE.PROFILES.SDR.SHORT` | Prospecta e cuida do funil | Cota e fecha seguros novos |
| 44 | `CUSTOM_ROLE.PROFILES.SDR.WHO` | Para quem prospecta e qualifica leads. | Para quem faz a cotação, manda as opções e fecha seguros novos. |
| 45 | `CUSTOM_ROLE.PROFILES.SALES_MANAGER.SHORT` | Dono dos funis e da meta | Cuida dos funis e da meta de produção |
| 46 | `CUSTOM_ROLE.PROFILES.SALES_MANAGER.WHO` | Para quem é dono do funil e da meta comercial. | Para quem cuida dos funis e da meta de produção da corretora. |
| 47 | `CUSTOM_ROLE.PROFILES.AGENT.WHO` | Para quem atende clientes e cuida das próprias conversas. | Para quem atende os clientes no dia a dia: dúvidas, segunda via e endosso. |
| 48 | `CUSTOM_ROLE.MATRIX.MODULES.CRM.HINT` | Funis, oportunidades e agenda | Funis de venda, renovação e sinistro, e a agenda |
| 49 | `CUSTOM_ROLE.MATRIX.MODULES.CRM.LEVEL_VIEW` | Vê o quadro e as oportunidades. Não altera. | Vê o quadro e os cards. Não altera. |
| 50 | `CUSTOM_ROLE.MATRIX.MODULES.CRM.LEVEL_MANAGE` | Cria, edita e move oportunidades. | Cria, edita e move cards: cotações, renovações e sinistros. |
| 51 | `CUSTOM_ROLE.PROFILES.PHRASES.MANAGE_DEALS` | Criar e mover oportunidades no CRM | Criar e mover cards no CRM |
| 52 | `CUSTOM_ROLE.PROFILES.PHRASES.EDIT_DEALS` | Editar oportunidades no CRM | Editar cards no CRM |
| 53 | `CUSTOM_ROLE.EXTRAS.CRM_MOVE_CARDS` | Arrasta oportunidades entre etapas sem editar o resto. | Arrasta cards entre etapas sem editar o resto. |

### Frontend geral: caixas de entrada (8)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 54 | `INBOX_MGMT.ADD.WHATSAPP_API.CHANNEL_NAME.PLACEHOLDER` | Ex.: Suporte Viagem | Ex.: Vendas ou Sinistro |
| 55 | `INBOX_MGMT.ADD.CHANNEL_NAME.PLACEHOLDER` | Digite o nome da caixa de entrada (ex: Acme Inc) | Digite o nome da caixa (ex.: Atendimento da corretora) |
| 56 | `INBOX_MGMT.ADD.WEBSITE_NAME.PLACEHOLDER` | Informe o nome do seu site (por exemplo: Acme Inc) | Informe o nome do seu site (ex.: o nome da sua corretora) |
| 57 | `INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_WELCOME_TAGLINE.PLACEHOLDER` | Nós tornamos simples a conexão conosco. Pergunte qualquer assunto ou compartilhe seus comentários. | Peça sua cotação, a segunda via ou avise um sinistro por aqui. |
| 58 | `INBOX_MGMT.ADD.WEBSITE_CHANNEL.CHANNEL_GREETING_MESSAGE.PLACEHOLDER` | Acme Inc normalmente responde em algumas horas. | Respondemos em horário comercial. Em caso de batida ou pane, ligue para a assistência 24 horas da sua seguradora. |
| 60 | `INBOX_MGMT.ADD.EMAIL_CHANNEL.EMAIL.SUBTITLE` | E-mail para onde os seus clientes lhe enviam tickets de suporte | E-mail para onde seus clientes mandam pedidos de cotação, apólices e documentos |
| 61 | `INBOX_MGMT.EDIT.SENDER_NAME_SECTION.BUSINESS_NAME.PLACEHOLDER` | Insira o nome de sua empresa | Nome da corretora |
| 62 | `INBOX_MGMT.PRE_CHAT_FORM.PRE_CHAT_MESSAGE.PLACEHOLDER` | Esta mensagem será visível para os usuários junto com o formulário | Ex.: Para agilizar a cotação, conte seu nome e qual seguro você procura. |

### Orquestração / Canais: caso de uso do WhatsApp (1)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 59 | `INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.ACCESS_REQUEST.USE_CASE_PLACEHOLDER` | Por exemplo: somos uma corretora de seguros e usamos o WhatsApp para tirar dúvidas de apólice e acompanhar renovações. | Por exemplo: somos uma corretora de seguros e usamos o WhatsApp para mandar cotações, tirar dúvidas de apólice e acompanhar renovações. |

### Modelos WhatsApp: CSAT (só o placeholder) (1)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 63 | `INBOX_MGMT.CSAT.MESSAGE.PLACEHOLDER` | Digite uma mensagem para mostrar aos usuários com o formulário | Ex.: Como foi o atendimento da corretora hoje? |

### WhatsApp Híbrido: prévias de roteamento (5)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 64 | `INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.PREVIEW.FOLLOW_UP_WEB` | O Carlos não responde há 2 dias. O lembrete do CRM sai pelo WhatsApp API às 10:00. | O Carlos não responde a cotação há 2 dias. O lembrete do CRM sai pelo WhatsApp API às 10:00. |
| 65 | `INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.PREVIEW.FOLLOW_UP_TEMPLATE` | O Carlos não responde há 2 dias. O lembrete do CRM sai como mensagem pronta pelo número oficial. | O Carlos não responde a cotação há 2 dias. O lembrete do CRM sai como mensagem pronta pelo número oficial. |
| 66 | `INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.PREVIEW.AGENT_WEB` | A Ana, da equipe, responde a Maria 3 dias depois. A resposta sai pelo WhatsApp API. | A Ana, da equipe, manda a segunda via para a Maria 3 dias depois. A resposta sai pelo WhatsApp API. |
| 67 | `INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.PREVIEW.AGENT_TEMPLATE` | A Ana, da equipe, responde a Maria 3 dias depois. Ela só consegue mandar uma mensagem pronta. | A Ana, da equipe, quer mandar a segunda via para a Maria 3 dias depois. Ela só consegue mandar uma mensagem pronta. |
| 68 | `INBOX_MGMT.WHATSAPP_HYBRID.ROUTING.WHO.ORIGINS.HUMAN.EXAMPLE` | Quando alguém da equipe responde um cliente que sumiu. | Quando alguém da equipe retoma uma cotação parada. |

