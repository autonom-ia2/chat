# #3098 (F2 do épico #3095): no topo do histórico da automação, quanto compraram as pessoas com quem ela agiu.
#
# Passaram = pessoas distintas das execuções dos últimos 30 dias (a janela do histórico). A pessoa sai do alvo: o
# próprio contato, o contato da conversa, ou o do card (o contact_id dele ou o da conversa principal), como no
# Contexto#contato. Execução na conta inteira não tem pessoa. Compraram = quem fechou uma venda (a régua do resultado
# da campanha, CampaignJourney::ComprasNaJanela) até 7 dias depois da primeira vez que a automação agiu com ela no
# período. Decisão do Rodrigo: janela fixa de 7 dias, sem campo novo na automação.
#
# O valor só vai para quem vê valor de venda (Crm::ValorDeVenda); funis que a pessoa não vê nos relatórios ficam de fora.
class Autonomia::Automacao::ComprasDoHistorico
  JANELA_DE_COMPRA = 7
  CONVERSA = 'INNER JOIN conversations ON conversations.id = autonomia_automacao_execucoes.alvo_id'.freeze
  CARD = 'INNER JOIN crm_cards ON crm_cards.id = autonomia_automacao_execucoes.alvo_id ' \
         'LEFT JOIN conversations ON conversations.id = crm_cards.conversation_id'.freeze

  def initialize(automacao:, user:, account_user:)
    @automacao = automacao
    @user = user
    @account_user = account_user
  end

  def resumo
    inicios = primeira_vez_por_pessoa
    compras = CampaignJourney::ComprasNaJanela.new(@automacao.account, dias: JANELA_DE_COMPRA, pipeline_ids: pipeline_ids)
                                              .de(inicios)
    {
      dias: Autonomia::Automacao::Historico::JANELA.in_days.to_i,
      janela: JANELA_DE_COMPRA,
      passaram: inicios.size,
      compraram: compras.pluck(:contato).uniq.size,
      valor: (CampaignJourney::ComprasNaJanela.valor(compras) if Crm::ValorDeVenda.ve?(@account_user))
    }
  end

  private

  # { contact_id => primeira execução no período }
  def primeira_vez_por_pessoa
    recentes = @automacao.execucoes.where(created_at: Autonomia::Automacao::Historico::JANELA.ago..)
    [
      recentes.where(alvo_type: 'Contact').group(:alvo_id),
      recentes.where(alvo_type: 'Conversation').joins(CONVERSA).group('conversations.contact_id'),
      recentes.where(alvo_type: 'Crm::Card').joins(CARD).group(Arel.sql('COALESCE(crm_cards.contact_id, conversations.contact_id)'))
    ].map { |consulta| consulta.minimum('autonomia_automacao_execucoes.created_at') }
      .reduce({}) { |todos, parte| todos.merge(parte) { |_contato, a, b| [a, b].min } }
      .except(nil)
  end

  def pipeline_ids
    visible = Crm::Access::VisiblePipelines.new(user: @user, account: @automacao.account, account_user: @account_user)
    visible.report_ids if visible.restricted?
  end
end
