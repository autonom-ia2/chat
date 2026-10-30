# Restaurar vários cards arquivados de uma vez (#2095, "Restaurar (N)" da tela Arquivados).
#
# Tudo ou nada: os cards restaurados e os pulados saem de uma transação só, e um erro inesperado desfaz o lote inteiro
# (a tela diz "nada mudou"). Pular não é erro: o card que a pessoa não pode restaurar (`forbidden`, mesma regra de um
# card só, Crm::CardPolicy#restore?), o que não está arquivado, o de funil arquivado e o do cliente que já voltou (outro
# card aberto do contato no mesmo funil; decisão 9 do protótipo: pular e avisar no fim) voltam em `skipped` com o motivo.
# Com `force: true`, o do cliente que voltou também é restaurado, como no card único.
#
# Result: `{ restored: [card_id, ...], skipped: [{ id:, error:, open_card_id:, open_card: { id:, title:, stage_name: } }] }`.
# `open_card_id` e `open_card` só no conflito, e só se a pessoa enxerga o card aberto: a tela mostra os dois lado a lado.
class Crm::Cards::BulkRestorer
  MAX_IDS = Crm::Cards::BulkAction::MAX_IDS
  FORBIDDEN = 'forbidden'.freeze

  def initialize(account:, user:, account_user:, ids:, force: false)
    @account = account
    @user = user
    @account_user = account_user
    # Em ordem de id: dois lotes com os mesmos cards travam na mesma ordem (sem ciclo entre eles).
    @ids = Array(ids).filter_map { |id| Integer(id.to_s, exception: false) }.uniq.first(MAX_IDS).sort
    @force = force
  end

  def perform
    restored = []
    skipped = []
    ActiveRecord::Base.transaction do
      travar_antes!
      @ids.each do |id|
        outcome = restore(id)
        outcome[:restored] ? restored << id : skipped << outcome.except(:restored)
      end
    end
    restored.each { |id| Crm::Cards::Broadcaster.broadcast(visible_cards_by_id[id], Events::Types::CRM_CARD_UPDATED) }
    { restored: restored, skipped: skipped }
  end

  private

  # Antes de qualquer trava de linha: a trava compartilhada de arquivar da conta (um arquivamento em curso termina antes,
  # e nenhum começa no meio do lote) e as chaves de cliente e funil de todos os cards, em ordem.
  def travar_antes!
    Crm::Pipelines::TravaDeArquivar.compartilhar!(@account.id)
    Crm::Cards::Restorer.travar_contatos_no_funil!(visible_cards_by_id.values)
  end

  def restore(id)
    card = visible_cards_by_id[id]
    return { id: id, error: FORBIDDEN } if card.blank? || !Pundit.policy!(user_context, card).restore?

    result = Crm::Cards::Restorer.new(card: card, actor: @user, force: @force).perform
    return { restored: true } if result.restored?

    open_card = visible(result.open_card)
    { id: id, error: result.error, open_card_id: open_card&.id, open_card: open_card && open_card_payload(open_card) }.compact
  end

  # O card aberto do conflito só vai na resposta se a pessoa o enxerga (como no card único).
  def visible(card)
    card if card && Pundit.policy!(user_context, card).show?
  end

  def open_card_payload(card)
    { id: card.id, title: card.title, stage_name: card.stage&.name }
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
