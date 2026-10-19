# Guia: trocas do pacote seguros/saude_beneficios (#1802)

Por cima de `pacotes/seguros/porques.md`. Só os campos de texto que mudam, pelo mesmo cabeçalho.
Rode `pnpm guia:build` depois de mexer aqui.


### mover_card_ganhar_perder_ou_reabrir_oportunidade
- titulo: Mover card, marcar que fechou o plano ou que não fechou, resolver, cancelar ou reabrir
- intent: "Como movo um card de etapa?"; "Como marco que fechou o plano?"; "Como marco que o cliente não fechou?"; "O cliente fechou com a concorrência, como marco?"; "Como reabro um card que não fechou?"; "Como marco um atendimento como resolvido?"; "Como cancelo um atendimento?"
- passos: Arraste o card entre colunas no Kanban, ou abra o card e toque na coluna certa em **Onde está no funil** (à direita) e confirme em **Mover**; a etapa também muda pela linha "Etapa X, a Nª de N" do cartão **Negócio** (num funil de Atender, cartão **Assunto**); quem cuida muda na mesma linha "Fulano cuida deste cliente", com **Salvar** no rodapé. Para fechar, use os botões da faixa do topo do card. Num funil de Vender: **Fechou o plano** (confira quanto ficou e clique em **Marcar: fechou o plano**) ou **Não fechou** (o motivo é opcional; clique em **Marcar: não fechou**). Num funil de Atender: **Resolvido** ou **Cancelado** (com motivo de cancelamento de atendimento); não pede valor. No modelo Cobrança, os botões são **Pago** e **Cancelado**. Para reabrir, use o botão azul **Reabrir** em **Próximo passo**; para arquivar, **Mais detalhes > Arquivar** e confirme.
- gotchas: se o movimento falhar, o front restaura o estado anterior; cards fechados podem aparecer melhor na Lista com filtro de resultado; marcar que não fechou, cancelar e arquivar não deletam contato nem conversa; Resolvido e Cancelado não somam em vendas nem avisam anúncios; card Resolvido ou Cancelado movido para um funil de Vender entra lá Aberto (não vira Plano ativo e não faz o contato virar cliente); o tipo do funil (Vender ou Atender) muda em Editar funil > Para que serve > Alterar.


### abrir_o_crm_kanban_e_filtrar_oportunidades
- intent: "Onde vejo o CRM?"; "Como filtro oportunidades?"; "Onde vejo os planos fechados e os que não fecharam?"; "Onde vejo o que não fechou?"; "Onde vejo os atendimentos resolvidos ou cancelados?"; "Como alterno entre Kanban, lista e calendário?"
- passos: Abra **CRM Kanban**; selecione o funil; use **Buscar por nome** para localizar o negócio, contato ou empresa; abra **Mais filtros** para empresa, etiquetas, status, prioridade, atenção da IA, responsável, time, caixa de entrada, campanha, valor e retornos; alterne **Kanban/Lista/Calendário** no seletor superior. Para acompanhar o que fechou (**Plano ativo / Não fechou** num funil de Vender, **resolvidos/cancelados** num funil de Atender): use a visão **Lista** com filtros e veja os números no **Dashboard CRM**.
- gotchas: fechar o card (Fechou o plano/Não fechou ou Resolvido/Cancelado) define o **status** do card (acompanhado no **Dashboard CRM** e na visão **Lista**), diferente da **etapa** do funil; a rota do Calendário é separada, mas o seletor de visualização também existe dentro do Kanban; custom roles sem `crm_view` não veem a entrada; filtros ativos viram chips removíveis e podem esconder cards; Encontrar com IA está desabilitado, aguardando uma integração específica; para mudar a etapa, arraste o card ou abra **Resumo > Etapa**; o botão Mover não aparece na face do card; no card, empresa aparece em destaque, pessoa abaixo e negócio em texto secundário; sem empresa, a pessoa aparece em destaque; cards da Prospecção preservam a empresa do negócio mesmo quando compartilham um contato.


### escolher_se_o_funil_e_de_vender_ou_de_atender
- passos: Ao criar o funil, responda **Para que serve este funil?**. **Vender** é para conquistar um cliente novo: o card termina em Fechou o plano ou Não fechou, tem valor, entra na meta do mês e pode avisar os Anúncios. **Atender** é para resolver algo para quem já é cliente: o card termina em Resolvido ou Cancelado, sem valor, sem meta e sem Anúncios. Em Atender, escolha um modelo pronto: **Suporte**, **Pós-venda**, **Cobrança** ou **Agendamento**. Num funil que já existe, abra **Editar funil**; o primeiro cartão do resumo é **Para que serve**; clique em **Alterar**, escolha Vender ou Atender e salve.
- gotchas: no modelo Cobrança o card termina em Pago ou Cancelado e mostra o valor a receber, o vencimento e "Prometeu pagar em"; num funil de Atender o Kanban mostra **Novo atendimento** em vez de Nova oportunidade e não mostra valor (só a Cobrança mostra o valor a receber); card Resolvido ou Cancelado movido para um funil de Vender entra lá Aberto (não vira Plano ativo e não faz o contato virar cliente); funis que já existiam: os que contavam como venda viraram Vender e os outros, Atender; nada muda sozinho.


### ver_dashboard_crm_e_metricas_de_funil
- intent: "Onde vejo relatório do CRM?"; "Como acompanho conversão do funil?"; "Como comparo IA e humano?"; "Quantos atendimentos resolvemos?"; "Quantos planos fechei no mês?"; "Qual a minha taxa de fechamento?"
- passos: Abra CRM Dashboard; selecione funil; escolha período; revise os números do topo, funil, fechados, retornos, carga por responsável e IA versus humano; use atualizar se dados mudaram. Os números do topo seguem o tipo do funil: num funil de Vender, **Planos fechados**, **Não fecharam**, **Taxa de fechamento**, **Valor fechado** e a meta do mês; num funil de Atender, **Resolvidos** e **Cancelados**.


### marcar_contato_como_cliente
- passos: O contato vira cliente sozinho quando um plano dele fecha num funil de Vender. Para quem comprou de outro jeito, clique em **Marcar como cliente** e confirme em **Sim, marcar**. Para desfazer um engano, **Não é cliente** e **Sim, tirar**.
- gotchas: o selo **Cliente desde** guarda o primeiro plano fechado e aparece também no painel da conversa; fechar outro plano não muda a data. Fechar um card num funil de Atender (Resolvido ou Cancelado) não faz o contato virar cliente; mover esse card para um funil de Vender também não: ele entra lá Aberto. Desfazer volta o contato para lead e não mexe em cards nem conversas.


### consultar_oportunidades_na_ficha_do_contato
- intent: "Quais oportunidades este contato tem?"; "Quais planos este contato já fechou ou não fechou?"; "Quais atendimentos este contato já teve?"


### criar_funis_estagios_e_conectar_caixas_ao_crm
- gotchas: sugestões da IA não são aplicadas nem movem cards automaticamente; os recursos de IA do funil vêm incluídos e a reavaliação padrão é de 7 dias, respeitando os gates globais; o retorno automático existente conserva sua ativação e agenda; Google Ads exige importação agendada do feed e Meta exige integração e atribuição do anúncio — ligar a opção no funil não comprova recebimento externo; Anúncios só existe em funil de Vender; a venda do anúncio conta quando o card fecha o plano, em qualquer coluna; a criação automática vem marcada na caixa ainda não configurada; trocar o funil da caixa move a criação automática para o funil novo e avisa na tela antes de salvar, e os cards que já existem ficam onde estão; desligar o CRM na caixa para a criação automática; a caixa que alimenta mais de um funil também se configura em Canais de cada funil; excluir uma etapa abre confirmação e pode falhar se houver cards dependentes; arquivar funil não apaga cards.


### ver_gestao_e_relatorio_de_campanhas_de_e_mail
- gotchas: com a jornada ligada, o detalhe de uma campanha (gráfico, cliques por link, tabela por pessoa, exportação, saúde) fica no Resultado dela, e links antigos com uma campanha de e-mail escolhida abrem esse Resultado; viraram negócio conta os cards do CRM ligados a uma conversa marcada pela campanha, e fecharam é a parte que já fechou o plano; pessoas alcançadas soma as entregues, e no WhatsApp API, que não confirma entrega, as enviadas; abertura é aproximada por limitação de tracking; exportar CSV só aparece com campanha específica; esta tela é relatório, não o lugar de editar campanha.
