# F2 corretora · Lote 4: Campanhas e Modelos WhatsApp

autonom-ia2/chat#1802, 19/10/2026. Vem depois dos lotes 1 (#1843), 2 (#1853) e 3, que mexem no mesmo arquivo do pacote.

É só texto, no pacote `seguros/corretora`. A conta geral não muda.

## O que entra

São 82 textos do painel e 1 do servidor.

- **Campanhas:**
  - os vazios de SMS e WhatsApp falam de parcela, vistoria e renovação;
  - os exemplos de nome e de mensagem são de renovação do seguro do carro;
  - a planilha do público lembra que vencimento, seguradora e placa podem entrar na mensagem;
  - o chat ao vivo dá boas-vindas na página do seguro do carro;
  - o resultado conta "Viraram card no CRM".
- **Identidade visual:** o e-mail de exemplo é de uma corretora (cotação em várias seguradoras, ajuda no sinistro, aviso antes do vencimento). O erro de endereço do site mostra `suacorretora.com.br` (servidor).
- **Modelos WhatsApp:**
  - Aviso de serviço explica com parcela, vistoria, apólice emitida e sinistro; Divulgação, com renovação e seguro novo (pela Meta, renovação é Divulgação);
  - os prontos da galeria mudam de texto: "Parcela a vencer", "Retomar a cotação", "Oferta de seguro", boas-vindas e lembrete de horário;
  - "Nome da corretora" nos campos; "Título do card" e "Valor do card" no catálogo de campos;
  - os avisos de saúde do modelo dizem "quem conhece a sua corretora";
  - a apólice entra nos exemplos do que não vai no topo (é pessoal).
- **Na conversa:** o nome de arquivo de exemplo é `Apolice_2026.pdf`.

## A régua dos prontos vale para o pacote

O `prontos.spec.js` passa a montar cada pronto também com o texto composto da corretora (base + `seguros` + `seguros/corretora`), nos dois idiomas. Cada um passa na mesma conferência da tela, e a categoria fica a do pronto: o pacote troca texto, nunca categoria. O arquivo `spec/fixtures/whatsapp_templates/prontos.json` ganha os corpos da corretora, e o `submit_format_spec.rb` confere todos com a régua do servidor.

## O que ficou de fora, e por quê

- **Título "Lembrete de vencimento ou renovação" da biblioteca de e-mail:** o corpo do modelo fala de "assinatura". Trocar só o título deixaria a troca pela metade. Entra junto com os modelos de e-mail de seguro (lacuna L4).
- **Prontos novos de corretor (N1 a N15) e os 10 botões novos:** exigem código em `constants.js` (dono Modelos WhatsApp). Ficam para um PR próprio.
- **Neutralizar o geral:** os exemplos de Campanhas que citam seguro no catálogo geral ("Auto vencendo em outubro", "seguro auto") são o lote 0, com PR do dono.
- **Não se mexe:** autorização para criar modelos (consentimento versionado), cupom, catálogo de produtos, código de verificação, prontos de sistema, modelos já aprovados na Meta, prompts de IA e a Lia.

## Ajustes sobre o inventário

- **Sem artigo antes do nome da empresa:** "com [nome_empresa]" e "Lembrete de [nome_empresa]". O artigo erra quando o nome é masculino (Agendamento e Modelos WhatsApp).
- **O carrossel não promete cobertura:** os cartões de exemplo falam de cotar em várias seguradoras e de cotação sem compromisso, e não de guincho, carro reserva ou assistência 24 horas (revisão).
- **Fora o exemplo de assunto do diálogo de e-mail** (`CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.SUBJECT_PLACEHOLDER`): nenhuma tela usa essa chave (tester).
- **"Pessoas" no lugar de "clientes"** nos vazios de SMS, WhatsApp e Modelos: a vistoria e o seguro novo são para quem ainda não comprou. É a regra da Base de Clientes.
- **"Valor do card" no lugar de "Valor do seguro":** o valor do card fica "Valor", porque o card pode ser de sinistro ou de parcela (decisão do lote 1).

## Os textos, por dono

### Campanhas: lista, público, nova campanha, chat ao vivo e importação (27)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `CAMPAIGN.SMS.EMPTY_STATE.SUBTITLE` | Lance uma campanha de SMS para chegar diretamente aos seus clientes. Envie ofertas ou faça anúncios com facilidade. Clique em 'Criar campanha' para começar. | Mande um SMS para várias pessoas de uma vez: aviso de parcela, de vistoria ou de renovação. Clique em 'Criar campanha' para começar. |
| 2 | `CAMPAIGN.WHATSAPP.EMPTY_STATE.SUBTITLE` | Inicie uma campanha do WhatsApp para atingir seus clientes diretamente. Envie ofertas ou faça anúncios facilmente. Clique em "Criar campanha" para começar. | Mande um modelo aprovado para várias pessoas de uma vez: renovação, parcela ou seguro novo. Clique em "Criar campanha" para começar. |
| 3 | `CAMPAIGN.WHATSAPP_API.CREATE.FORM.TITLE.PLACEHOLDER` | Ex: Reativação Junho | Ex.: Renovação do seguro do carro, novembro |
| 4 | `CAMPAIGN.EMAIL_SENDER.DIALOG.DOMAIN_PLACEHOLDER` | ex.: mail.suaempresa.com | ex.: mail.suacorretora.com.br |
| 5 | `CAMPAIGN.EMAIL_SENDER.DIALOG.FROM_EMAIL_PLACEHOLDER` | ex.: marketing{'@'}suaempresa.com | ex.: seguros{'@'}suacorretora.com.br |
| 6 | `CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.NAME_PLACEHOLDER` | ex.: Boletim de junho | ex.: Renovação de novembro |
| 7 | `CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_NAME_PLACEHOLDER` | ex.: Marketing Acme | ex.: Sua Corretora de Seguros |
| 8 | `CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.REPLY_TO_PLACEHOLDER` | ex.: suporte{'@'}suaempresa.com | ex.: atendimento{'@'}suacorretora.com.br |
| 9 | `CAMPAIGN.EMAIL_CAMPAIGN.DIALOG.FROM_EMAIL_PLACEHOLDER` | ex.: promo{'@'}suaempresa.com | ex.: seguros{'@'}suacorretora.com.br |
| 10 | `CAMPAIGN.EMAIL_CAMPAIGN.BUILDER.SAVE_TEMPLATE_NAME_PLACEHOLDER` | ex.: Convite para live | ex.: Lembrete de renovação |
| 11 | `CAMPAIGN.EMAIL_CAMPAIGN.AI.COMPOSER.BRIEF_PLACEHOLDER` | Ex.: e-mail promocional sobre o novo plano de seguro auto, tom amigável, chamada para desconto | Ex.: e-mail para quem tem o seguro do carro vencendo no mês que vem, tom amigável, convite para cotar a renovação |
| 12 | `CAMPAIGN.EMAIL_CAMPAIGN.AI.COMPOSER.ASSET_DESCRIPTION_PLACEHOLDER` | O que é este recurso? Ex.: vídeo de depoimento do cliente | O que é este recurso? Ex.: tabela de coberturas do seguro do carro |
| 13 | `CAMPAIGN.EMAIL_CAMPAIGN.AI.COMPOSER.ROLE_PRODUCT` | Produto | Seguro |
| 14 | `CAMPAIGN_JOURNEY.AUDIENCES.EMPTY_SUBTITLE` | Público é uma lista de pessoas. Suba uma planilha para criar o primeiro. | Público é uma lista de pessoas, como a sua carteira de clientes. Suba a planilha do seu sistema da corretora para criar o primeiro. |
| 15 | `CAMPAIGN_JOURNEY.NEW_AUDIENCE.NAME_PLACEHOLDER` | Ex.: Auto vencendo em outubro | Ex.: Seguro do carro vencendo em novembro |
| 16 | `CAMPAIGN_JOURNEY.NEW_AUDIENCE.FILE_HINT` | CSV ou Excel. Nome e celular ou e-mail; empresa e outras colunas são bem-vindas. | CSV ou Excel. Nome e celular ou e-mail. Vencimento, seguradora e placa também ajudam: dá para usar na mensagem. |
| 17 | `CAMPAIGN_JOURNEY.NEW_AUDIENCE.COLUMNS.OTHER_HINT` | Ficam guardadas para usar na mensagem | Ficam guardadas para usar na mensagem, como o vencimento do seguro |
| 18 | `CAMPAIGN_JOURNEY.NEW_CAMPAIGN.MESSAGE.NAME_PLACEHOLDER` | Ex.: Renovação auto — outubro | Ex.: Renovação do seguro do carro em novembro |
| 19 | `CAMPAIGN_JOURNEY.NEW_CAMPAIGN.VARIABLES.HINT` | As colunas guardadas no público podem ser usadas aqui. | As colunas guardadas no público podem ser usadas aqui, como o vencimento ou a seguradora. |
| 20 | `CAMPAIGN_JOURNEY.NEW_CAMPAIGN.API.MESSAGE_PLACEHOLDER` | Oi, escreva a mensagem aqui | Ex.: Olá, tudo bem? O seu seguro vence este mês. Quer que a gente cote a renovação? |
| 21 | `CAMPAIGN_JOURNEY.NEW_CAMPAIGN.SMS.MESSAGE_PLACEHOLDER` | Texto curto, ex.: sua parcela vence amanhã. | Texto curto, ex.: a parcela do seu seguro vence amanhã. |
| 22 | `CAMPAIGN_JOURNEY.NEW_CAMPAIGN.EMAIL.FROM_NAME_PLACEHOLDER` | Ex.: Hub2You | Ex.: Sua Corretora de Seguros |
| 23 | `CAMPAIGN_JOURNEY.LIVE_CHAT.URL_PLACEHOLDER` | https://www.seusite.com.br/planos | https://www.suacorretora.com.br/seguro-auto |
| 24 | `CAMPAIGN_JOURNEY.LIVE_CHAT.NAME_PLACEHOLDER` | Ex.: Boas-vindas na página de planos | Ex.: Boas-vindas na página do seguro do carro |
| 25 | `CAMPAIGN_JOURNEY.LIVE_CHAT.TEXT_PLACEHOLDER` | Oi! Posso ajudar a escolher um plano? | Oi! Quer cotar o seguro do seu carro? |
| 26 | `CAMPAIGN_IMPORT.FIELDS.CAMPAIGN_NAME_PLACEHOLDER` | Ex.: campanha_junho_whatsapp | Ex.: renovacao_auto_novembro |
| 27 | `RESULT_JOURNEY.OVERVIEW.TOTALS.DEALS` | Viraram negócio no CRM | Viraram card no CRM |

### Campanhas: identidade visual (11)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `BRAND_KITS.PREVIEW.SAMPLE_SUBJECT` | Seu atendimento em um só lugar | Seu seguro com quem cuida de você |
| 2 | `BRAND_KITS.PREVIEW.SAMPLE_TITLE` | Seu atendimento em um só lugar | Seu seguro com quem cuida de você |
| 3 | `BRAND_KITS.PREVIEW.SAMPLE_TEXT` | Responda seus clientes pelo WhatsApp, pelo site e pelo e-mail sem trocar de tela. | A gente cota em várias seguradoras e manda as opções pelo WhatsApp. |
| 4 | `BRAND_KITS.PREVIEW.ITEM_1` | Todas as conversas numa lista só | Cotação em várias seguradoras |
| 5 | `BRAND_KITS.PREVIEW.ITEM_2` | Respostas prontas para o dia a dia | Ajuda na hora do sinistro |
| 6 | `BRAND_KITS.PREVIEW.ITEM_3` | Relatórios simples de entender | Aviso antes do vencimento |
| 7 | `BRAND_KITS.PREVIEW.SAMPLE_BUTTON` | Quero conhecer | Quero uma cotação |
| 8 | `BRAND_KITS.PREVIEW.SAMPLE_NOTE` | Leva poucos minutos para começar. | A cotação é sem compromisso. |
| 9 | `BRAND_KITS.FOOTER.COMPANY` | Nome da empresa | Nome da corretora |
| 10 | `BRAND_KITS.FOOTER.LINK_PLACEHOLDER` | instagram.com/suaempresa | instagram.com/suacorretora |
| 11 | `BRAND_KITS.READER.ADDRESS_PLACEHOLDER` | suaempresa.com.br | suacorretora.com.br |

### Modelos WhatsApp (43)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `MODELOS_WHATSAPP.VAZIO.TITULO` | Crie sua primeira mensagem pronta para falar com clientes pelo WhatsApp. | Crie sua primeira mensagem pronta para avisar da parcela, da vistoria ou da renovação. |
| 2 | `MODELOS_WHATSAPP.TEXTO.TIPO.aviso.PARA` | Pedido, horário, pagamento, entrega. Custa menos por envio. | Parcela, vistoria, apólice emitida, sinistro. Custa menos por envio. |
| 3 | `MODELOS_WHATSAPP.TEXTO.TIPO.divulgacao.PARA` | Oferta, novidade, convite. Custa mais por envio. | Renovação, seguro novo, oferta. Custa mais por envio. |
| 4 | `MODELOS_WHATSAPP.OBJETIVOS.boas_vindas.TEXTO` | Olá, [nome_cliente]! Aqui é da [nome_empresa]. Que bom ter você com a gente. Quando precisar de alguma coisa, é só mandar mensagem por aqui. | Olá, [nome_cliente]! Aqui é da [nome_empresa]. Que bom ter você com a gente. Quando precisar de cotação, segunda via ou ajuda com o seu seguro, é só mandar mensagem por aqui. |
| 5 | `MODELOS_WHATSAPP.OBJETIVOS.lembrete.TEXTO` | Olá, [nome_cliente]! Lembrete do seu horário na [nome_empresa]: dia [data], às [horario]. Você confirma? Toque em uma das opções abaixo. | Olá, [nome_cliente]! Lembrete do seu horário com [nome_empresa]: dia [data], às [horario]. Você confirma? Toque em uma das opções abaixo. |
| 6 | `MODELOS_WHATSAPP.OBJETIVOS.promocao.TITULO` | Promoção | Oferta de seguro |
| 7 | `MODELOS_WHATSAPP.OBJETIVOS.promocao.PARA` | Para avisar de uma oferta com prazo. | Para avisar de um desconto com prazo para fazer o seguro. |
| 8 | `MODELOS_WHATSAPP.OBJETIVOS.promocao.TEXTO` | Oi, [nome_cliente]! Até [data], você tem [desconto] de desconto na [nome_empresa]. Quer aproveitar? Veja as ofertas no botão abaixo. | Oi, [nome_cliente]! Até [data], você tem [desconto] de desconto para fazer o seu seguro com [nome_empresa]. Quer uma cotação? Veja no botão abaixo. |
| 9 | `MODELOS_WHATSAPP.OBJETIVOS.cobranca.TITULO` | Lembrete de pagamento | Parcela a vencer |
| 10 | `MODELOS_WHATSAPP.OBJETIVOS.cobranca.PARA` | Para lembrar o cliente de um pagamento que vai vencer. | Para lembrar o cliente da parcela do seguro que vai vencer. |
| 11 | `MODELOS_WHATSAPP.OBJETIVOS.cobranca.TEXTO` | Olá, [nome_cliente]. Lembrete da [nome_empresa]: o pagamento de [valor] vence em [data]. Se já pagou, pode desconsiderar. Se precisar da segunda via, toque no botão abaixo. | Olá, [nome_cliente]. Lembrete de [nome_empresa]: a parcela do seu seguro, de [valor], vence em [data]. Se já pagou, pode desconsiderar. Se for boleto, confira se está no nome da seguradora. Se precisar da segunda via, toque no botão abaixo. |
| 12 | `MODELOS_WHATSAPP.OBJETIVOS.retomar.TITULO` | Retomar conversa | Retomar a cotação |
| 13 | `MODELOS_WHATSAPP.OBJETIVOS.retomar.PARA` | Para voltar a falar com quem sumiu. | Para voltar a falar com quem pediu cotação e sumiu. |
| 14 | `MODELOS_WHATSAPP.OBJETIVOS.retomar.TEXTO` | Oi, [nome_cliente]! Aqui é da [nome_empresa]. Ficou alguma dúvida da nossa última conversa? É só responder aqui que a gente continua. | Oi, [nome_cliente]! Aqui é da [nome_empresa]. Ficou alguma dúvida sobre a cotação do seu seguro? É só responder aqui que a gente continua. |
| 15 | `MODELOS_WHATSAPP.CAMPOS.nome_empresa.ROTULO` | Nome da empresa | Nome da corretora |
| 16 | `MODELOS_WHATSAPP.CAMPOS.nome_empresa.EXEMPLO` | Sua Empresa | Sua Corretora |
| 17 | `MODELOS_WHATSAPP.CAMPOS.link.EXEMPLO` | sualoja.com.br/b/123 | suacorretora.com.br/v/123 |
| 18 | `MODELOS_WHATSAPP.TIPOS_DE_BOTAO.site.EXEMPLO` | Ex.: Ver ofertas | Ex.: Fazer a vistoria |
| 19 | `MODELOS_WHATSAPP.EXTRAS.RODAPE_EXEMPLO` | Ex.: Sua Empresa · atendimento de segunda a sexta | Ex.: Sua Corretora · atendimento de segunda a sexta |
| 20 | `MODELOS_WHATSAPP.EXTRAS.TOPO_AJUDA` | Opcional. O mesmo arquivo vai para todas as pessoas que receberem. Use para algo igual para todos (cardápio, catálogo, regulamento). Boleto, comprovante ou documento de cada cliente não vão aqui. | Opcional. O mesmo arquivo vai para todas as pessoas que receberem. Use para algo igual para todos (tabela de coberturas, regulamento). Boleto, apólice ou documento de cada cliente não vão aqui. |
| 21 | `MODELOS_WHATSAPP.TOPOS.documento.AJUDA` | Escolha um PDF. O mesmo arquivo vai para todas as pessoas: não use para boleto ou documento de uma pessoa só. | Escolha um PDF. O mesmo arquivo vai para todas as pessoas: não use para boleto, apólice ou documento de uma pessoa só. |
| 22 | `MODELOS_WHATSAPP.FORMATOS.carrossel.NOME_PADRAO` | Novidades | Nossos seguros |
| 23 | `MODELOS_WHATSAPP.FORMATOS.carrossel.TEXTO` | Oi, [nome_cliente]! Separamos algumas novidades para você: | Oi, [nome_cliente]! Veja alguns seguros que a gente faz para você: |
| 24 | `MODELOS_WHATSAPP.FORMATOS.carrossel.BOTAO` | Ver produto | Quero cotar |
| 25 | `MODELOS_WHATSAPP.FORMATOS.carrossel.CARTAO_1.TEXTO` | Novidade da semana, com entrega rápida. | Seguro do carro: a gente cota em várias seguradoras. |
| 26 | `MODELOS_WHATSAPP.FORMATOS.carrossel.CARTAO_2.TEXTO` | O mais pedido do mês, com preço especial. | Seguro da casa: cotação sem compromisso. |
| 27 | `MODELOS_WHATSAPP.FORMATOS.formulario.NOME_PADRAO` | Cadastro rápido | Dados para a cotação |
| 28 | `MODELOS_WHATSAPP.FORMATOS.formulario.TEXTO` | Oi, [nome_cliente]! Leva 1 minuto: preencha o formulário para a gente te atender melhor. | Oi, [nome_cliente]! Leva 1 minuto: preencha o formulário e a gente prepara a sua cotação. |
| 29 | `MODELOS_WHATSAPP.IA.OBJETIVO_EXEMPLO` | Ex.: lembrar o cliente do horário marcado para amanhã | Ex.: avisar que a apólice foi emitida e vai chegar por aqui |
| 30 | `MODELOS_WHATSAPP.JANELA.GAVETA.O_QUE_EXEMPLO` | Ex.: avisar que chegou a coleção nova e que dá para reservar respondendo | Ex.: avisar que o seguro vence este mês e que dá para cotar a renovação respondendo |
| 31 | `MODELOS_WHATSAPP.JANELA.GAVETA.LINK_DIGITADO` | Link não pode ser digitado no texto. Use o botão do campo (ex.: o link da oferta, vindo do público). | Link não pode ser digitado no texto. Use o botão do campo (ex.: o link da vistoria, vindo do público). |
| 32 | `MODELOS_WHATSAPP.JANELA.GAVETA.PARECE_LINK` | Parece um link. Para link, use o botão do campo (ex.: o link da oferta). | Parece um link. Para link, use o botão do campo (ex.: o link da vistoria). |
| 33 | `MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.negocio.titulo` | Título do negócio | Título do card |
| 34 | `MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.negocio.valor` | Valor do negócio | Valor do card |
| 35 | `MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.minha_empresa.nome` | Nome da minha empresa | Nome da minha corretora |
| 36 | `MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.minha_empresa.endereco` | Endereço da minha empresa | Endereço da minha corretora |
| 37 | `MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.minha_empresa.telefone` | Telefone da minha empresa | Telefone da minha corretora |
| 38 | `MODELOS_WHATSAPP.CATALOGO_DE_CAMPOS.minha_empresa.site` | Site da minha empresa | Site da minha corretora |
| 39 | `MODELOS_WHATSAPP.SITUACOES.pausado.DICA` | mande só para quem conhece a sua empresa e deixe claro, logo no começo, quem está falando. | mande só para quem conhece a sua corretora e deixe claro, logo no começo, quem está falando. |
| 40 | `MODELOS_WHATSAPP.SITUACOES.desativado.DICA` | duplique o modelo, reescreva o texto dizendo logo no começo quem está falando, e mande só para quem conhece a sua empresa. | duplique o modelo, reescreva o texto dizendo logo no começo quem está falando, e mande só para quem conhece a sua corretora. |
| 41 | `MODELOS_WHATSAPP.PONTE.SINAL.ruim` | O WhatsApp está vendo muita gente bloquear ou denunciar o modelo "{nome}". Ele pode pausar o modelo a qualquer momento, e a campanha para junto. Dá para enviar, mas o melhor é mandar só para quem conhece a sua empresa. | O WhatsApp está vendo muita gente bloquear ou denunciar o modelo "{nome}". Ele pode pausar o modelo a qualquer momento, e a campanha para junto. Dá para enviar, mas o melhor é mandar só para quem conhece a sua corretora. |
| 42 | `MODELOS_WHATSAPP.PONTE.SINAL.atencao` | Algumas pessoas bloquearam ou denunciaram o modelo "{nome}". Se piorar, o WhatsApp pausa o modelo e a campanha para junto. Dá para enviar, mas mande só para quem conhece a sua empresa. | Algumas pessoas bloquearam ou denunciaram o modelo "{nome}". Se piorar, o WhatsApp pausa o modelo e a campanha para junto. Dá para enviar, mas mande só para quem conhece a sua corretora. |
| 43 | `MODELOS_WHATSAPP.SAUDE.SINAIS.bom.TEXTO` | Quase ninguém bloqueou ou denunciou esta mensagem. Continue mandando para quem conhece a sua empresa. | Quase ninguém bloqueou ou denunciou esta mensagem. Continue mandando para quem conhece a sua corretora. |

### Modelos na conversa (catálogo do Chatwoot) (1)

| # | Chave | Geral | Corretora |
|---|---|---|---|
| 1 | `WHATSAPP_TEMPLATES.PARSER.DOCUMENT_NAME_PLACEHOLDER` | Informe o nome do arquivo do documento (ex.: Comprovante_2025.pdf) | Informe o nome do arquivo do documento (ex.: Apolice_2026.pdf) |

### Servidor (1)

| Chave | Geral | Corretora |
|---|---|---|
| `brand_kits.import_errors.invalid_url` | Digite o endereço completo do site, por exemplo https://suaempresa.com.br. | Digite o endereço completo do site, por exemplo https://suacorretora.com.br. |
