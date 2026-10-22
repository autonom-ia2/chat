# Restaurar vários cards arquivados de uma vez (#2095, "Restaurar (N)" da tela Arquivados).
#
# Tudo ou nada: os cards restaurados e os pulados saem de uma transação só, e um erro inesperado desfaz o lote inteiro
# (a tela diz "nada mudou"). Pular não é erro: o card que a pessoa não pode restaurar (`forbidden`, mesma regra de um
# card só, Crm::CardPolicy#restore?), o que não está arquivado, o de funil arquivado e o do cliente que já voltou (outro
# card aberto do contato no mesmo funil; decisão 9 do protótipo: pular e avisar no fim) voltam em `skipped` com o motivo.
# Com `force: true`, o do cliente que voltou também é restaurado, como no card único.
#
# Result: `{ restored: [card_id, ...], skipped: [{ id:, error:, open_card_id: }, ...] }`.
class Crm::Cards::BulkRestorer
  MAX_IDS = Crm::Cards::BulkAction::MAX_IDS
  FORBIDDEN = 'forbidden'.freeze

  def initialize(account:, user:, account_user:, ids:, force: false)
    @account = account
    @user = user
    @account_user = account_user
    @ids = Array(ids).filter_map { |id| Integer(id.to_s, exception: false) }.uniq.first(MAX_IDS)
    @force = force
  end

  def perform
    restored = []
    skipped = []
    ActiveRecord::Base.transaction do
      @ids.each do |id|
        outcome = restore(id)
        outcome[:restored] ? restored << id : skipped << outcome.except(:restored)
      end
    end
    restored.each { |id| Crm::Cards::Broadcaster.broadcast(visible_cards_by_id[id], Events::Types::CRM_CARD_UPDATED) }
    { restored: restored, skipped: skipped }
  end

  private

  def restore(id)
    card = visible_cards_by_id[id]
    return { id: id, error: FORBIDDEN } if card.blank? || !Pundit.policy!(user_context, card).restore?

    result = Crm::Cards::Restorer.new(card: card, actor: @user, force: @force).perform
    return { restored: true } if result.restored?

    { id: id, error: result.error, open_card_id: visible_id(result.open_card) }.compact
  end

  # O card aberto do conflito só vai na resposta se a pessoa o enxerga (como no card único).
  def visible_id(card)
    card.id if card && Pundit.policy!(user_context, card).show?
  end

  def user_context
    { user: @user, account: @account, account_user: @account_user }
  end

  def visible_cards_by_id
    @visible_cards_by_id ||= Crm::Cards::VisibleScopeQuery.new(
      scope: @account.crm_cards, account: @account, user: @user, account_user: @account_user
    ).perform.where(id: @ids).includes(:pipeline).index_by(&:id)
  end
end
