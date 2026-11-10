# As sondas das lacunas do exemplo 17 (G63, G64, G66, G67): rodam o código de verdade e conferem o efeito. Ficam fora
# do FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama as daqui.
module FechamentoAutomacao::SondasDoExemplo17
  extend CrmHelpers

  module_function

  # G66 (#2843, decisão 14; exemplo 17, passo 4): a rodada do motor de verdade, num card cuja conversa segue com a
  # antiga dona (a Júlia) depois da troca. O passo "passar a conversa para o responsável do card" a entrega à Renata,
  # pelo mesmo pedido do Atribuir. Roda na transação do exemplo, que desfaz tudo.
  def conversa_acompanha_o_responsavel?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true') do
      conta = FactoryBot.create(:account)
      conta.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
      paula, julia, renata = %i[administrator agent agent].map { |papel| FactoryBot.create(:user, account: conta, role: papel) }
      card = card_da_cobertura(conta, paula, julia, renata)
      passo = { 'id' => 'conversa', 'tipo' => 'conversa_ao_responsavel' }
      rodada_no_card(conta, paula, card, [passo])
      card.primary_conversation.reload.assignee_id == renata.id
    end
  end

  # Decisão 18, corrigida (G66, ex. 17, passos 4 e 5): numa execução só, a conversa vai para a Renata, a agente de IA a
  # assume mesmo com a Renata no nome (a opção "cobrir a pessoa") e registra de quem tirou, e a execução segue aberta
  # (esperando). A Renata escreve na conversa: a conversa volta sozinha para ela, sem passo na receita, e o histórico
  # registra a volta.
  def ia_assume_e_devolve?
    ClimateControl.modify(CRM_KANBAN_ENABLED: 'true', AUTONOMIA_AGENTS_ENABLED: 'true') do
      conta = FactoryBot.create(:account)
      conta.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_gatilhos')
      paula, julia, renata = %i[administrator agent agent].map { |papel| FactoryBot.create(:user, account: conta, role: papel) }
      card = card_da_cobertura(conta, paula, julia, renata)
      conversa = card.primary_conversation
      agente = agente_de_ia_na_caixa(conta, conversa.inbox)
      passos = [{ 'id' => 'conversa', 'tipo' => 'conversa_ao_responsavel' },
                { 'id' => 'sofia', 'tipo' => 'ia_assumir', 'agente_id' => agente.id, 'cobrir_pessoa' => true },
                { 'id' => 'espera', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }]
      cobre_e_devolve?(rodada_no_card(conta, paula, card, passos), conversa, renata)
    end
  end

  # A agente tirou a conversa da Renata e ficou com ela; a Renata escreve, e a conversa volta, com o registro da volta.
  def cobre_e_devolve?(execucao, conversa, renata)
    cobertura = Autonomia::Automacao::Registro.find_by(execucao: execucao, motivo: Autonomia::Automacao::Cobertura::COMECOU)
    assumiu = cobertura&.dados.to_h['tirada_de'] == renata.id
    com_a_ia = conversa.reload.assignee_id.nil? && conversa.assignee_agent_bot_id.present?
    renata_escreve(conversa, renata)
    voltou = Autonomia::Automacao::Registro.exists?(execucao: execucao, motivo: Autonomia::Automacao::Cobertura::VOLTOU)
    assumiu && com_a_ia && voltou && conversa.reload.assignee_id == renata.id
  end

  # A Renata responde o cliente na conversa; o evento message.created chega à escuta da automação
  # (AutomacaoListener#message_created), como em produção.
  def renata_escreve(conversa, renata)
    mensagem = FactoryBot.create(:message, conversation: conversa, account: conversa.account, inbox: conversa.inbox,
                                           message_type: :outgoing, sender: renata, content: 'Oi, Maria! Voltei.')
    evento = Events::Base.new('message.created', Time.zone.now, { message: mensagem })
    Autonomia::AutomacaoListener.instance.message_created(evento)
  end

  # Os Agentes e as áreas de IA ligados na conta, e uma agente atendendo cliente na caixa.
  def agente_de_ia_na_caixa(conta, caixa)
    conta.update!(internal_attributes: conta.internal_attributes.to_h.merge(Autonomia::Agents::Config::INTERNAL_ATTR_KEY => true))
    Autonomia::Agents::Fase2.ligar!(conta)
    agente = Autonomia::Agents::Agent.create!(account: conta, name: 'Sofia', agent_type: 'custom', status: :active, enabled: true)
    Autonomia::Agents::Areas.vincular!(agent: agente, inbox: caixa)
    agente
  end

  # O card já com a Renata e a conversa dele ainda com a Júlia, numa caixa das duas.
  def card_da_cobertura(conta, paula, julia, renata)
    caixa = create_crm_whatsapp_api_inbox(account: conta, members: [paula, julia, renata])
    contato = conta.contacts.create!(name: 'Maria')
    conversa = create_crm_conversation(account: conta, inbox: caixa, contact: contato, assignee: julia)
    funil, etapa = create_crm_pipeline(account: conta, user: paula)
    conta.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Sonda G66', currency: 'BRL', contact: contato,
                            primary_conversation: conversa, owner: renata)
  end

  def rodada_no_card(conta, quem, card, passos)
    gatilho = 'card.responsavel_mudou'
    definicao = FactoryBot.create(:autonomia_automacao, account: conta, ligada_por: quem)
    versao = definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => gatilho }, 'passos' => passos }, autor: nil)
    definicao.update!(ativa: true)
    execucao = FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: card, chave_gatilho: gatilho)
    rodada_da_sonda(conta, card, nil, execucao)
  end

  # G63 e G64 (#2830, #2839; exemplo 17, passos 4 e 5): a rodada do motor de verdade, numa conversa. O "esperar até" sem
  # prazo, com a condição já cumprida, espera a próxima conferência das 8h no fuso da conta (só ali confere) e, com a
  # mensagem nova do cliente, entra no galho "a cada mensagem".
  def espera_enquanto_espera(campos)
    conta = FactoryBot.create(:account, reporting_timezone: 'America/Sao_Paulo')
    conta.enable_features!('automacao_fundacao', 'automacao_motor')
    conversa = FactoryBot.create(:conversation, account: conta, status: :open, priority: :urgent)
    urgente = { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' }
    espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'prazo' => 'sem_prazo', 'condicao' => urgente }.merge(campos)
    execucao = rodada_da_sonda(conta, conversa, [espera], nil)
    [conta, conversa, execucao]
  end

  def rodada_da_sonda(conta, conversa, passos, execucao)
    marca = Time.current.floor(6)
    unless execucao
      definicao = FactoryBot.create(:autonomia_automacao, account: conta,
                                                          ligada_por: FactoryBot.create(:user, account: conta, role: :administrator))
      versao = definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }, autor: nil)
      definicao.update!(ativa: true)
      execucao = FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: conversa, chave_gatilho: 'conversa.resolvida')
    end
    execucao.update!(estado: 'andando', travada_em: marca)
    Autonomia::Automacao::Executor.rodar(execucao.id, marca.iso8601(6))
    execucao.reload
  end

  def conferencia_marcada?
    conta, _conversa, execucao = espera_enquanto_espera('conferir_as' => 8)
    execucao.estado == 'esperando' && execucao.due_at == Autonomia::Automacao::Tempo.proxima_hora(conta, 8)
  end

  def galho_a_cada_mensagem?
    galho = [{ 'id' => 'galho', 'tipo' => 'esperar', 'duracao' => { 'valor' => 1, 'unidade' => 'dias' } }]
    conta, conversa, execucao = espera_enquanto_espera('conferir_as' => 8, 'a_cada_mensagem' => galho)
    FactoryBot.create(:message, account: conta, conversation: conversa, inbox: conversa.inbox, message_type: :incoming,
                                sender: conversa.contact)
    rodada_da_sonda(conta, conversa, nil, execucao).cursor == 'galho'
  end

  # G67 (#2844; exemplo 17, passo 6): o "resumir" de uma execução que começou há 10 dias lê as 8 mensagens que chegaram
  # desde então, inclusive a primeira, e não as 5 últimas só. Monta o que iria à IA, sem chamá-la.
  def resumo_le_o_periodo?
    conta = FactoryBot.create(:account)
    conta.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_ia')
    conversa = FactoryBot.create(:conversation, account: conta)
    quem = FactoryBot.create(:user, account: conta, role: :administrator)
    passo = { 'id' => 'conta', 'tipo' => 'resumir', 'le' => %w[mensagens_com_respostas], 'destino' => 'nota' }
    execucao = execucao_de_10_dias(conta, quem, conversa, passo)
    (1..8).each do |dia|
      FactoryBot.create(:message, conversation: conversa, account: conta, inbox: conversa.inbox, sender: conversa.contact,
                                  message_type: :incoming, content: "Dia #{dia} das férias",
                                  created_at: (10 - dia).days.ago)
    end
    lidas = o_que_o_resumo_le(execucao, passo, conversa)
    lidas.size == 8 && lidas.first.end_with?('Dia 1 das férias')
  end

  def execucao_de_10_dias(conta, quem, conversa, passo)
    definicao = FactoryBot.create(:autonomia_automacao, account: conta, ligada_por: quem)
    versao = definicao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }, autor: nil)
    FactoryBot.create(:autonomia_automacao_execucao, versao: versao, alvo: conversa, chave_gatilho: 'conversa.resolvida',
                                                     created_at: 10.days.ago)
  end

  # A leitura do passo, a mesma que vai à IA na execução (PassoDeResumir#leitura_da_execucao, privada).
  def o_que_o_resumo_le(execucao, passo, conversa)
    acesso = Autonomia::Automacao::Acesso.new(execucao.automacao, chave_gatilho: execucao.chave_gatilho)
    resumir = Autonomia::Automacao::PassoDeResumir.new(execucao: execucao, passo: passo, alvo: conversa, acesso: acesso)
    Array(resumir.send(:leitura_da_execucao).conversa[:messages])
  end
end
