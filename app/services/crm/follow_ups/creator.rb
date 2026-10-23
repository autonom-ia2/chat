# #1460/#1461/#1462 — cria um lembrete pelo painel: de uma vez só (como antes) ou que repete (uma série e a primeira
# vez). Com ou sem card: sem card, pode ser de um cliente (contact_id) ou de uma empresa (company_id, ficha do
# Relacionamento). Quem recebe vem do RecipientParams. A repetição é só para lembrete da equipe (fase 1).
class Crm::FollowUps::Creator
  RECURRENCE_KEYS = %i[frequency weekdays weekdays_only ends_mode ends_on occurrences_count].freeze
  # #1590: folga para o relógio de quem marca "agora" e para a ida e volta da requisição.
  PAST_GRACE = 1.minute

  # Card arquivado não ganha lembrete pedido por pessoa. A série nasceria encerrada, sem nenhuma vez ("Ends on leaves
  # no date to remind", #2101), e o lembrete de uma vez seria cancelado pelo DueProcessor em silêncio (#2130). Os
  # lembretes automáticos não passam por aqui. O controller responde 422 dizendo o motivo, dentro da ação (não num
  # rescue_from), para a mensagem sair no idioma da pessoa.
  class CardArchived < StandardError; end

  def initialize(account:, user:, card:, conversation:, attributes:)
    @account = account
    @user = user
    @card = card
    @conversation = conversation
    @attributes = attributes
  end

  def perform
    raise CardArchived if @card&.archived?

    attributes = base_attributes
    return create_single(attributes) if recurrence.blank?

    create_series(attributes)
  end

  def self.recurrence_attributes(raw)
    {
      frequency: raw[:frequency], weekdays: Array(raw[:weekdays]).compact_blank.map(&:to_i),
      weekdays_only: ActiveModel::Type::Boolean.new.cast(raw[:weekdays_only]) || false,
      ends_mode: raw[:ends_mode].presence || 'never', ends_on: raw[:ends_on].presence,
      occurrences_count: raw[:occurrences_count].presence
    }
  end

  private

  def create_single(attributes)
    follow_up = @account.crm_follow_ups.new(attributes)
    reject_past_auto_send!(follow_up)
    follow_up.transaction do
      # A barreira do arquivamento (a mesma do SeriesMaterializer): espera um arquivamento em curso e, com o card
      # aberto, o segura até gravar. Sem ela, o card arquivado entre a conferência de `perform` e o save ficaria com um
      # lembrete que o DueProcessor cancela em silêncio.
      raise CardArchived if @card && Crm::Cards::Archiver.arquivado_sob_trava?(@card.id)

      follow_up.save!
    end
    follow_up
  end

  # #1590: mensagem automática com horário que já passou não tem como sair "na hora marcada" (sairia na hora, no
  # primeiro giro do cron). Reagendar tem trava parecida, sem a folga (Rescheduler). Só com a flag
  # crm_mensagem_marcada: sem ela, venha de onde vier a criação, aceita como sempre aceitou.
  def reject_past_auto_send!(follow_up)
    return unless follow_up.auto_send_message?
    return unless Crm::FollowUps::SendErrorCode.enabled?(@account)
    return if follow_up.due_at.blank? || follow_up.due_at >= PAST_GRACE.ago

    follow_up.errors.add(:due_at, :in_the_past, message: 'must be in the future for auto-send follow-ups')
    raise ActiveRecord::RecordInvalid, follow_up
  end

  def base_attributes
    resolved = Crm::FollowUps::ParamsResolver.new(
      account: @account, user: @user, card: @card, conversation: @conversation, attributes: @attributes
    ).perform
    recipients = Crm::FollowUps::RecipientParams.new(account: @account, card: @card, attributes: @attributes, user: @user).perform
    resolved.merge(recipients).merge(standalone_links).merge(card: @card, created_by: @user)
  end

  # Sem card: o cliente e a empresa escolhidos (da própria conta). Com card, valem os do card.
  def standalone_links
    return {} if @card.present?

    links = {}
    links[:contact_id] = @account.contacts.find(@attributes[:contact_id]).id if @attributes[:contact_id].present?
    links[:company_id] = @account.companies.find(@attributes[:company_id]).id if @attributes[:company_id].present?
    links
  end

  def recurrence
    @recurrence ||= begin
      raw = @attributes[:recurrence].to_h.with_indifferent_access.slice(*RECURRENCE_KEYS)
      raw[:frequency].present? && raw[:frequency] != 'none' ? raw : nil
    end
  end

  def create_series(attributes)
    series = @account.crm_follow_up_series.new(series_attributes(attributes))
    series.errors.add(:automation_mode, :inclusion) unless attributes[:automation_mode].to_s == 'reminder_only'
    raise ActiveRecord::RecordInvalid, series if series.errors.any?

    series.transaction do
      series.save!
      Crm::FollowUps::SeriesMaterializer.new(series).perform || without_first_time!(series)
    end
  end

  # A série nasceu sem nenhuma vez: o card foi arquivado entre a conferência de cima e a trava do SeriesMaterializer,
  # ou o fim escolhido não deixa nenhuma data.
  def without_first_time!(series)
    raise CardArchived if @card&.reload&.archived?

    series.errors.add(:ends_on, 'leaves no date to remind')
    raise ActiveRecord::RecordInvalid, series
  end

  def series_attributes(attributes)
    attributes.slice(:contact_id, :company_id, :conversation, :title, :description, :timezone, :recipient_user_ids,
                     :recipient_team_id)
              .merge(card: @card, created_by: @user, starts_at: attributes[:due_at],
                     recipient_mode: attributes[:recipient_mode] || 'legacy')
              .merge(self.class.recurrence_attributes(recurrence))
              .compact
  end
end
