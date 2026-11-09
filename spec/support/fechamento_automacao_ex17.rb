# As sondas das lacunas do exemplo 17 achadas na G63 (G66, G67): rodam o código de verdade e conferem o efeito. Ficam
# fora do FechamentoAutomacao::Lacunas, que já está no limite de tamanho; o SONDAS de lá chama as daqui.
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
    FechamentoAutomacao::Lacunas.rodada_da_sonda(conta, card, nil, execucao)
  end

  # G67 (#2844; exemplo 17, passo 6): o "resumir" de uma execução que começou há 10 dias lê as 8 mensagens que chegaram
  # desde então, inclusive a primeira, e não as 5 últimas só. Monta o que iria à IA, sem chamá-la.
  def resumo_le_o_periodo?
    conta = FactoryBot.create(:account)
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
