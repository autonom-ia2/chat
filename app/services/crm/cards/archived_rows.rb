# As linhas da tela "Arquivados" (#2095): cada card arquivado com quando, por quem e por que saiu do quadro, e se a
# pessoa pode restaurá-lo. Quem arquivou vem da última atividade 'archive' do card: a pessoa (`user`), a IA
# (`ai`, atividade com `by: 'ai'`, Crm::Ai::NaoENegocio) ou o sistema (`system`). O motivo é só o código que a IA grava
# (`motivo`, ex.: nao_e_negocio); o raciocínio da IA não sai daqui.
#
# `desfecho` é o desfecho guardado ao arquivar um card fechado (Parte A, Crm::Card#desfecho_arquivado: won, lost,
# resolved, cancelled), para a tela avisar para onde o card vai ao restaurar; nil no que estava aberto. `retornos_parados`
# são os lembretes que o arquivar cancelou (`lembretes_cancelados` da mesma atividade).
#
# Na busca em todos os funis entram também os cards guardados com um funil arquivado, de qualquer status
# (ArchivedController): `status` diz qual é, e só o arquivado tem data, autor e `can_restore`.
#
# O valor segue o Valor de venda (#2075): sem ver o valor do card, `value_cents` vem nil e `value_hidden` true.
class Crm::Cards::ArchivedRows
  def initialize(cards:, user_context:)
    @cards = cards.to_a
    @user_context = user_context
  end

  def perform
    @cards.map { |card| row(card) }
  end

  private

  def row(card)
    {
      id: card.id,
      title: card.title,
      status: card.status,
      contact_id: card.contact_id,
      # O nome do cliente, para as frases "o card de {nome}" e "{nome} já tem outro card aberto" (decisão 6).
      contact: card.contact && { id: card.contact.id, name: card.contact.name },
      stage: { id: card.stage_id, name: card.stage&.name },
      pipeline: { id: card.pipeline_id, name: card.pipeline&.name, status: card.pipeline&.status },
      # Card fechado antes de arquivar guarda a data do fechamento (Parte A, #2091).
      closed_at: card.closed_at,
      desfecho: card.desfecho_arquivado
    }.merge(archive_fields(card)).merge(value(card))
  end

  # Só o card arquivado tem quando, por quem e por que saiu do quadro; o guardado com o funil vem sem.
  def archive_fields(card)
    return { retornos_parados: 0, archived_at: nil, archived_by: nil, archive_reason: nil, can_restore: false } unless card.archived?

    activity = last_archive_by_card[card.id]
    payload = activity&.payload.to_h
    {
      retornos_parados: payload['lembretes_cancelados'].to_i,
      archived_at: activity&.created_at || card.last_activity_at,
      archived_by: archived_by(activity),
      archive_reason: payload['motivo'],
      can_restore: Pundit.policy!(@user_context, card).restore?
    }
  end

  def value(card)
    payload = { value_cents: card.value_cents, currency: card.currency }
    return payload if Crm::ValorDeVenda.ve_o_card?(@user_context[:account_user], card)

    Crm::ValorDeVenda.oculta_card!(payload)
  end

  def archived_by(activity)
    return if activity.blank?
    return { type: 'ai' } if activity.payload.to_h['by'] == 'ai'
    return { type: 'system' } if activity.actor_type != 'user' || activity.actor_id.blank?

    { type: 'user', id: activity.actor_id, name: users_by_id[activity.actor_id]&.name }
  end

  def last_archive_by_card
    @last_archive_by_card ||= Crm::Activity.where(account_id: @user_context[:account].id, card_id: archived_ids, event_type: 'archive')
                                           .select('DISTINCT ON (crm_activities.card_id) crm_activities.*')
                                           .order(:card_id, created_at: :desc, id: :desc)
                                           .index_by(&:card_id)
  end

  def archived_ids
    @cards.select(&:archived?).map(&:id)
  end

  def users_by_id
    @users_by_id ||= User.where(id: last_archive_by_card.values.filter_map { |a| a.actor_id if a.actor_type == 'user' }).index_by(&:id)
  end
end
