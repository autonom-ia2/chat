# As sondas das lacunas do exemplo 17 achadas na G63 (G66, G67): rodam o motor de verdade e conferem o efeito. Ficam
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
end
