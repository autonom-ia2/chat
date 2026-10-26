# Este contato é (#2084/#2085): grava a relação escolhida na tela. Ao tirar o contato do funil (parceiro do mercado,
# não é negócio), as sugestões de card que ainda esperam uma pessoa nas conversas dele expiram na hora (decisão do
# Rodrigo: ninguém recusa uma por uma), e, se a pessoa escolheu "Arquivar", os cards abertos dele são arquivados pelo
# mesmo lote do CRM (Crm::Cards::BulkAction 'delete'), card a card com a regra de quem pode arquivar
# (Crm::CardPolicy#destroy?) e só os que a pessoa vê. O que a regra recusa fica aberto e volta contado.
#
#   Crm::Relacao::Marcar.new(contact:, user:, account_user:, relacao:, arquivar_cards:).perform
#   -> { relacao:, cards_arquivados:, cards_nao_arquivados: }
class Crm::Relacao::Marcar
  def initialize(contact:, user:, account_user:, relacao:, arquivar_cards: false)
    @contact = contact
    @user = user
    @account_user = account_user
    @relacao = relacao.to_s
    @arquivar_cards = arquivar_cards
  end

  def perform
    conversas = []
    ActiveRecord::Base.transaction do
      @contact.update!(relacao: @relacao)
      conversas = expirar_sugestoes if fora?
    end
    conversas.each { |conversa| Crm::Subjects::Notifier.notify(conversa) }
    arquivados = fora? && @arquivar_cards ? arquivar : { updated: [], failed: [] }
    { relacao: @contact.relacao, cards_arquivados: arquivados[:updated].size, cards_nao_arquivados: arquivados[:failed].size }
  end

  private

  def fora?
    !@contact.relacao_interessado?
  end

  # As conversas que tinham sugestão esperando, para o painel Assuntos ler de novo.
  def expirar_sugestoes
    sugestoes = Crm::SubjectDecision.suggested.where(account_id: @contact.account_id, conversation_id: conversas_do_contato)
    conversa_ids = sugestoes.distinct.pluck(:conversation_id)
    sugestoes.update_all(state: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Conversation.where(id: conversa_ids).to_a
  end

  def conversas_do_contato
    Conversation.where(account_id: @contact.account_id, contact_id: @contact.id).select(:id)
  end

  def arquivar
    ids = @contact.account.crm_cards.where(contact_id: @contact.id, status: :open).order(:id).limit(Crm::Cards::BulkAction::MAX_IDS).ids
    Crm::Cards::BulkAction.new(account: @contact.account, user: @user, account_user: @account_user, ids: ids, action: 'delete').perform
  end
end
