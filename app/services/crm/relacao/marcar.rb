# Este contato é (#2084/#2085): grava a relação escolhida na tela. Ao tirar o contato do funil (parceiro do mercado,
# não é negócio), as sugestões de card que ainda esperam uma pessoa nas conversas dele expiram na hora (decisão do
# Rodrigo: ninguém recusa uma por uma), e, se a pessoa escolheu "Arquivar", os cards abertos dele que ela pode arquivar
# são arquivados pelo mesmo lote do CRM (Crm::Cards::BulkAction 'delete', que confere de novo card a card).
#
# Os cards que contam são os mesmos da pergunta "Arquivar?" (`arquivaveis`): abertos, que a pessoa vê e que a regra
# deixa arquivar (Crm::CardPolicy#destroy?). Card escondido dela não entra em conta nenhuma, nem no que ficou aberto.
#
#   Crm::Relacao::Marcar.new(contact:, user:, account_user:, relacao:, arquivar_cards:).perform
#   -> { relacao:, cards_arquivados:, cards_nao_arquivados: }
class Crm::Relacao::Marcar
  def self.arquivaveis(contact:, user:, account_user:)
    abertos = contact.account.crm_cards.where(contact_id: contact.id, status: :open)
    visiveis = Crm::Cards::VisibleScopeQuery.new(scope: abertos, account: contact.account, user: user, account_user: account_user).perform
    contexto = { user: user, account: contact.account, account_user: account_user }
    visiveis.order(:id).select { |card| Pundit.policy!(contexto, card).destroy? }
  end

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

  # Trava as sugestões que expira e devolve as conversas delas, para o painel Assuntos ler de novo.
  def expirar_sugestoes
    sugestoes = Crm::SubjectDecision.suggested.where(account_id: @contact.account_id, conversation_id: conversas_do_contato)
                                    .lock.pluck(:id, :conversation_id)
    return [] if sugestoes.empty?

    Crm::SubjectDecision.where(id: sugestoes.map(&:first)).update_all(state: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    Conversation.where(id: sugestoes.map(&:last).uniq).to_a
  end

  def conversas_do_contato
    Conversation.where(account_id: @contact.account_id, contact_id: @contact.id).select(:id)
  end

  # Em lotes do tamanho que o BulkAction aceita: contato com muitos cards abertos não fica pela metade.
  def arquivar
    ids = self.class.arquivaveis(contact: @contact, user: @user, account_user: @account_user).map(&:id)
    ids.each_slice(Crm::Cards::BulkAction::MAX_IDS).with_object({ updated: [], failed: [] }) do |lote, soma|
      resultado = Crm::Cards::BulkAction.new(account: @contact.account, user: @user, account_user: @account_user,
                                             ids: lote, action: 'delete').perform
      soma[:updated].concat(resultado[:updated])
      soma[:failed].concat(resultado[:failed])
    end
  end
end
