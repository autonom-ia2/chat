# Guia: trocas do pacote seguros/corretora (#1802)

Por cima de `pacotes/seguros/porques.md`. Só os campos de texto que mudam, pelo mesmo cabeçalho.
Rode `pnpm guia:build` depois de mexer aqui.


### mover_card_ganhar_perder_ou_reabrir_oportunidade
- passos: Arraste o card entre colunas no Kanban, ou abra o card e toque na coluna certa em **Onde está no funil** (à direita) e confirme em **Mover**; a etapa também muda pela linha "Etapa X, a Nª de N" do cartão **Seguro** (num funil de Atender, cartão **Assunto**); quem cuida muda na mesma linha "Fulano cuida deste cliente", com **Salvar** no rodapé. Para fechar, use os botões da faixa do topo do card. Num funil de Vender: **Fechou o seguro** (confira quanto ficou e clique em **Marcar: fechou o seguro**) ou **Não fechou** (o motivo é opcional; clique em **Marcar: não fechou**). Num funil de Atender: **Resolvido** ou **Cancelado** (com motivo de cancelamento de atendimento); não pede valor. No modelo Cobrança, os botões são **Pago** e **Cancelado**. Para reabrir, use o botão azul **Reabrir** em **Próximo passo**; para arquivar, **Mais detalhes > Arquivar** e confirme.

### escolher_se_o_funil_e_de_vender_ou_de_atender
- intent: "Como faço o funil de renovação?"; "E o de sinistro?"; "E o de endosso?"; "Como faço um funil de suporte, pós-venda ou cobrança?"; "Qual a diferença entre Vender e Atender?"; "Este funil conta como venda?"; "Como mudo o funil para atendimento?"
- passos: Ao criar o funil, responda **Para que serve este funil?**. **Vender** é para conquistar um cliente novo: o card termina em Fechou o seguro ou Não fechou, tem valor, entra na meta do mês e pode avisar os Anúncios. **Atender** é para resolver algo para quem já é cliente: o card termina em Resolvido ou Cancelado, sem valor, sem meta e sem Anúncios. Em Vender, os modelos prontos são **Venda de seguro** e **Renovação** (termina em Renovou ou Não renovou). Em Atender: **Sinistro** e **Endosso** (terminam em Encerrado e Feito), e também **Suporte**, **Pós-venda**, **Cobrança** e **Agendamento**. Num funil que já existe, abra **Editar funil**; o primeiro cartão do resumo é **Para que serve**; clique em **Alterar**, escolha Vender ou Atender e salve.

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
