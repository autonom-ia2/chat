# Guia: trocas do pacote seguros/corretora (#1802)

Por cima de `pacotes/seguros/porques.md`. Só os campos de texto que mudam, pelo mesmo cabeçalho.
Rode `pnpm guia:build` depois de mexer aqui.


### mover_card_ganhar_perder_ou_reabrir_oportunidade
- passos: Arraste o card entre colunas no Kanban, ou abra o card e toque na coluna certa em **Onde está no funil** (à direita) e confirme em **Mover**; a etapa também muda pela linha "Etapa X, a Nª de N" do cartão **Seguro** (num funil de Atender, cartão **Assunto**); quem cuida muda na mesma linha "Fulano cuida deste cliente", com **Salvar** no rodapé. Para fechar, use os botões da faixa do topo do card. Num funil de Vender: **Fechou o seguro** (confira quanto ficou e clique em **Marcar: fechou o seguro**) ou **Não fechou** (o motivo é opcional; clique em **Marcar: não fechou**). Num funil de Atender: **Resolvido** ou **Cancelado** (com motivo de cancelamento de atendimento); não pede valor. No modelo Cobrança, os botões são **Pago** e **Cancelado**. Para reabrir, use o botão azul **Reabrir** em **Próximo passo**; para arquivar, **Mais detalhes > Arquivar** e confirme.

### escolher_se_o_funil_e_de_vender_ou_de_atender
- intent: "Como faço o funil de renovação?"; "E o de sinistro?"; "E o de endosso?"; "Como faço um funil de suporte, pós-venda ou cobrança?"; "Qual a diferença entre Vender e Atender?"; "Este funil conta como venda?"; "Como mudo o funil para atendimento?"
- passos: Ao criar o funil, responda **Para que serve este funil?**. **Vender** é para conquistar um cliente novo: o card termina em Fechou o seguro ou Não fechou, tem valor, entra na meta do mês e pode avisar os Anúncios. **Atender** é para resolver algo para quem já é cliente: o card termina em Resolvido ou Cancelado, sem valor, sem meta e sem Anúncios. Em Vender, os modelos prontos são **Venda de seguro** e **Renovação** (termina em Renovou ou Não renovou). Em Atender: **Sinistro** e **Endosso** (terminam em Encerrado e Feito), e também **Suporte**, **Pós-venda**, **Cobrança** e **Agendamento**. Num funil que já existe, abra **Editar funil**; o primeiro cartão do resumo é **Para que serve**; clique em **Alterar**, escolha Vender ou Atender e salve.
- gotchas: no modelo Cobrança o card termina em Pago ou Cancelado e mostra o valor a receber, o vencimento e "Prometeu pagar em"; num funil de Atender o Kanban mostra **Novo atendimento** em vez de Nova cotação e não mostra valor (só a Cobrança mostra o valor a receber); card Resolvido ou Cancelado movido para um funil de Vender entra lá Aberto (não vira Seguro ativo e não faz o contato virar cliente); funis que já existiam: os que contavam como venda viraram Vender e os outros, Atender; nada muda sozinho; a IA de assunto usa o tipo para separar a venda do pedido de quem já é cliente (cancelamento, problema, troca), mas o nome e o **Quando usar** do funil valem mais que o tipo: um funil de suporte marcado como Vender recebe pós-venda se o nome ou o Quando usar disserem isso; sem funil de Atender que sirva, o pedido de pós-venda fica no card que a conversa já tem e, sem card aberto, abre no funil de Vender mais próximo.

### ver_dashboard_crm_e_metricas_de_funil
- intent: "Onde vejo relatório do CRM?"; "Como acompanho conversão do funil?"; "Como comparo IA e humano?"; "Quantos atendimentos resolvemos?"; "Quantos seguros fechei no mês?"; "Qual a minha taxa de fechamento?"; "Onde vejo a produção do mês?"

### criar_e_compartilhar_links_e_qr_codes
- intent: Como crio um QR code para o WhatsApp do escritório?; Onde crio um link rastreável de corretor?; Como identifico as conversas que vêm da bio?; Onde baixo o QR code de uma origem?; Como ligo o botão de WhatsApp da minha landing page ao CRM?; O que colo nos Parâmetros de URL do anúncio da Meta?; Como vejo quais campanhas da Meta trouxeram conversas e vendas pelo site?; Por que o lead da landing page chegou sem origem?
- passos: 1. Abra Links e QR codes e clique em Nova origem; 2. Em Onde você vai usar, escolha QR code ou link direto (escritório, corretor, bio, impresso) ou Botão de site ou landing page; 3. No QR ou link: informe o nome da origem, o WhatsApp de destino e a mensagem opcional, confira a prévia e crie; depois copie o link, baixe o QR ou veja o material; 4. No site: informe o nome da origem, o WhatsApp de destino e, em Site onde fica o botão, cole o endereço da página como aparece no navegador (pode ser o link inteiro; usamos só o site, até 5, um por linha) e crie; 5. Na origem do site, copie o Texto para os anúncios da Meta e cole em Parâmetros de URL de cada anúncio; 6. Passe ao desenvolvedor o Endereço de aviso e o código da origem (em Para o desenvolvedor); 7. Confira o Último aviso recebido (verde nas últimas 24 horas, âmbar se mais antigo, cinza se nunca chegou) e acompanhe, no painel da origem selecionada, os Resultados por campanha (cliques, conversas, fecharam e valor).

### criar_card_ou_oportunidade_no_crm
- titulo: Criar card ou cotação no CRM
- intent: "Como crio uma cotação nova?"; "Como adiciono um card no funil?"; "Como associo contato, caixa e responsável?"
- onde_fica: Sidebar > CRM > CRM Kanban > Nova cotação (num funil de Atender, o botão se chama Novo atendimento)
- passos: Clique em **Nova cotação** (ou **Novo atendimento**, num funil de Atender); em **Quem é o cliente?** (Passo 1 de 2), escolha **Já está nos contatos** (procure e clique em **Procurar**), **Pessoa nova** ou **Sem pessoa por enquanto**, e clique em **Continuar**. Para pessoa nova, a empresa pode ficar sem, ser escolhida ou criada. Em **Sobre o seguro** (Passo 2 de 2), escreva **Qual seguro** (único obrigatório; ex.: nome do cliente · seguro do carro), confira **Funil**, **Em que etapa entra**, **Quem cuida** e **Caixa de entrada**; abra **Mais detalhes** para o resto; confira o resumo do rodapé e clique em **Colocar no funil**.

### configurar_link_publico_de_agendamento
- intent: "Como crio um link de agenda?"; "Onde configuro /book/:slug?"; "Como deixo o link da agenda mais curto?"; "Como mudo o endereço da página de agendamento?"; "Como cada corretor tem seu próprio link?"

### passar_reunioes_para_outra_pessoa
- intent: Como passo as reuniões de um corretor para outro?; Alguém saiu de férias, como troco quem atende as reuniões marcadas?; Como mudo o responsável das reuniões futuras de uma vez?; Por que algumas reuniões não passaram para a outra pessoa?

### configurar_pagina_de_agendamento_em_caixa_compartilhada_e_links_por_agente
- intent: "Como vários corretores usam o mesmo e-mail para agenda?"; "Como gero um link de agendamento para cada agente?"; "O que significa caixa compartilhada no booking?"

### criar_oportunidade_pela_ficha_do_contato
- intent: "Como crio um card para este contato?"; "Como crio uma cotação para este contato?"; "Como levo o contato de Relacionamentos para o CRM?"
- passos: Na ficha do contato, clique em **Novo card**. O CRM abre em outra aba com a pessoa e sua empresa cadastrada selecionadas. Preencha os dados do seguro e confirme em **Colocar no funil**. O card criado abre com o mesmo contato vinculado. **Voltar ao contato** retorna à ficha; se houver dados comerciais não salvos, confirme o descarte ou continue editando.

### ver_meus_numeros_do_mes
- passos: Abra Números; leia o topo (o seu mês até agora: seguros fechados e valor, ou casos resolvidos); use o botão do topo para abrir a sua lista (retornos atrasados, senão cotações paradas, senão os seus cards); veja o próximo passo, os blocos Vendendo e Atendendo, **A IA te ajudou** e a barra da equipe; troque de mês pelas setas; **Como contamos** explica as regras.

### ver_anuncios_sem_login
- passos: 1. Abra Anúncios: a página já mostra quantas conversas vieram de anúncio no período, quantas viraram cotação e quantas viraram venda, com o valor e o tempo de resposta; 2. Escolha 7 ou 30 dias; 3. Clique em Conversas, Cotações ou Vendas para abrir a lista daquela etapa, com Abrir conversa em cada linha; 4. Em Anúncios, clique num anúncio para ver a foto, as conversas por dia e quem veio dele, com a situação de cada pessoa e Abrir conversa.


### consultar_oportunidades_na_ficha_do_contato
- passos: Abra **Seguros** no painel Acompanhamento. A lista reúne os cards do mesmo contato em todos os funis. Use a busca pelo título e **Situação**; avance por **Próxima** quando houver mais resultados. Clique num card para abri-lo no CRM em outra aba. Use **Atualizar cards** ou retorne à ficha para buscar o estado atual.


### consultar_oportunidades_na_ficha_da_empresa
- passos: Abra **Seguros** no painel da empresa. Cada item mostra o card, o contato vinculado, funil, etapa, situação e valor. Busque pelo título, ajuste **Situação** e use **Próxima** para mais resultados. Clique para abrir o mesmo card no CRM em outra aba; a ficha original permanece aberta.


### ver_numeros_da_equipe
- passos: Abra Números e escolha **Equipe**; leia o topo (o mês da empresa, ou da equipe de vendas ou de atendimento, com a meta do funil quando houver); use o botão do topo para abrir a lista do funil (negociações paradas, retornos atrasados ou lembretes para trás); veja o próximo passo, os blocos **Cotando** e **Atendendo** e **Quem precisa de ajuda** (o motivo e o botão que abre a lista daquela pessoa); abra **Quem cuidou** para ver uma linha por pessoa e a IA numa linha própria; troque de mês pelas setas.
- gotchas: os blocos seguem os funis que a pessoa enxerga no painel: quem só vê funis de Vender vê Cotando, quem só vê funis de Atender vê Atendendo; o valor fechado de cada pessoa aparece para quem vê a equipe, mas o custo da IA só para o administrador ou o Financeiro (quem tem Ver custos da conta); a IA conta como uma linha só, mesmo com vários agentes ou robôs, e uma conversa conta uma vez; a IA não tem meta nem entra em "Quem precisa de ajuda"; contamos só os clientes que entraram num funil; "passou" conta só as passagens que ficam registradas, e algumas passagens da IA ainda não ficam (#1887); "precisa de ajuda" é quem soma 5 ou mais retornos atrasados e casos parados há 7 dias no funil principal, uma linha por pessoa com os dois números, de quem tem mais atraso para quem tem menos, até 3 pessoas, sem posição numerada; a caixa aberta pelo "a IA está esperando" abre em Todos e em Abertas, para bater com o número; o prazo por pessoa ainda não é gravado, por isso a tela não fala em "no prazo"; a meta por pessoa só aparece quando as metas do mês existirem; a função só com "Visualizar relatórios do CRM", sem acesso ao CRM, vê em modo leitura, sem os botões; sem a flag crm_numeros_equipe a aba Equipe continua o painel de sempre (fluxo ver_dashboard_crm_e_metricas_de_funil).


### exportar_a_lista_do_crm_para_excel
- onde_fica: Sidebar > CRM > CRM Kanban > alternar para Lista > botao Exportar, ao lado de Nova cotação


### criar_pagina_de_agendamento
- passos: 1. Abra CRM > Agendamento > Páginas e links e clique em Criar página; 2. Escolha um modelo (Conversa para cotar, Atendimento no escritório, Reunião com empresa ou Começar do zero); 3. Em Conte, confira o nome que o cliente vê, o link em Endereço da página (já vem pronto; Mudar endereço abre o campo para trocar o final), quanto tempo dura e toque em quem atende; 4. Em Onde acontece, escolha um ou mais locais (Vídeo no WhatsApp, Ligação no WhatsApp, Meu link com o endereço completo, No local com o endereço); 5. Em Dias e horas, toque nos dias, escolha Das, Até, Avisar com e Intervalo, e deixe ligado ou desligue Fechar nos feriados nacionais; 6. Em Sua marca, envie logo e foto, escolha de que lado a logo fica (À esquerda, No centro ou À direita), a cor (uma das prontas ou Outra cor) e escreva a frase de boas-vindas, confira em Assim fica na página (Claro e Escuro mostram os dois temas) e clique em Continuar; a logo de fundo escuro é criada sozinha, e Trocar imagem em Em fundo escuro envia outra; para não repetir isso a cada página, o administrador clica em Salvar como identidade da conta, e numa página que já existe quem gerencia páginas usa Usar a identidade salva e confirma em Sim, usar; 7. Em Avisos, escolha por qual WhatsApp sai o aviso ao cliente (ou Sem avisos), quando avisar e até quando o cliente pode mudar, e clique em Ver como fica; 8. Na prévia, confira a frase do funil e a dos avisos e use Alterar se quiser mudar; 9. Clique em Publicar e use Copiar link, QR code ou Abrir.


### escolher_o_tipo_ao_criar_agente
- passos: 1. Abra Agentes e clique em Criar agente; 2. Na página Criar agente, escolha um dos modelos prontos (Tirar dúvidas dos clientes, Atender quem quer fazer seguro ou Receber quem chega) e clique em Usar este, ou clique em Do meu jeito para contar com suas palavras; 3. Se o agente deve só ajudar as pessoas da equipe dentro das conversas, desça até Precisa de outro tipo? e escolha Copiloto da equipe; 4. Siga a conversa de criação (Conte, Confira, Comece); o canal do agente normal é escolhido no fim.


### ver_os_primeiros_passos
- gotchas: cada passo so fica Feito quando o estado real da conta muda, nunca por clique; os passos ficam em tres etapas (Ligar a plataforma, Organizar vendas e renovações, Crescer); passos opcionais trazem Pular por enquanto; o painel mostra os pre-requisitos externos (por exemplo, conta na OpenAI com credito) e o tempo estimado; passo que depende de outro mostra Precisa antes, sem bloquear; clicar num passo da lista abre ele no painel; Preciso de ajuda abre o Guia; a lista some do centro da tela quando o essencial termina, mas continua no menu.


### abrir_a_pagina_de_configuracoes
- gotchas: os cartões ficam em grupos (Sua corretora, Canais, Pessoas e acesso, Atendimento, Conexões, Segurança); cada cartão diz o estado real quando há (quantos canais, usuários, times e etiquetas) ou o que falta, com o mesmo dado dos Primeiros passos; Prospecção não está aqui (fica em Prospecção > Configurações), Modelos também não (Campanhas > Modelos WhatsApp) e Cobrança virou Plano e faturas; Atribuição é a dona de política, capacidade e passagem do robô para a pessoa; Canais de cada funil (caixas e funis do CRM) fica ao lado da Atribuição; Custos do WhatsApp (a autorização para criar modelos que a Meta cobra) fica em Sua corretora, junto do Plano; E-mail de envio das campanhas fica em Canais; Agentes externos são robôs de outros sistemas (os Agentes da plataforma ficam em No automático); o cartão Canais de atendimento fica vermelho quando alguma caixa precisa reconectar; quem não administra mas cuida da IA do CRM vê o cartão Passar para uma pessoa; o horário hoje mora dentro de cada canal (aba Horário de funcionamento), e os Prazos de resposta usam outro calendário; configuração nova da plataforma que ainda não tem cartão aparece no grupo Outros; com o menu novo desligado, Configurações continua sendo a lista de sempre no menu.


### usar_modelo_do_whatsapp_em_campanha
- gotchas: Nome do cliente e Nome da corretora já vêm ligados ao cadastro (primeiro nome do contato e nome da sua empresa no Chat2You); os outros campos você liga a uma coluna do público ou escreve um texto fixo; havendo um rascunho de campanha guardado, a tela pergunta se continua ele ou começa de novo; carrossel, oferta, código de verificação e botão de copiar código ainda não vão em campanha.
