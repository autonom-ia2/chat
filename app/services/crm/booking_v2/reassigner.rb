# "Passar reuniões" (#1195, J8-A10): o admin (ou quem tem `agendamento_manage`) passa as reuniões futuras de uma
# pessoa para outra, de uma página ou de todas as páginas novas da conta. `preview` mostra antes o que vai acontecer
# sem gravar nada; `perform` faz.
#
# Para cada reunião, confere se a pessoa nova está livre naquele horário, com o intervalo entre reuniões da página
# (mesma regra do `Slots`: reuniões `scheduled` dela, de qualquer caixa e as internas). Livre, a reunião passa
# (`MeetingHandover`); ocupada, fica como está e volta na lista de conflitos. Uma reunião passada conta como ocupação
# para as seguintes, então duas reuniões no mesmo horário nunca vão para a mesma pessoa.
#
# Provedor (Google/Microsoft): não entra na conferência. A agenda do provedor é a da CAIXA da página, não a da pessoa;
# trocar o responsável não muda a caixa, e a própria reunião já ocupa aquele horário lá (o freebusy a acusaria como
# conflito dela mesma).
#
# Corrida: tudo acontece numa transação, sob a trava de agente (`Booker::LOCK_NS_AGENT`) das DUAS pessoas, em ordem
# crescente de id. O Booker toma caixa, agente e telefone, nessa ordem, e uma só trava de agente; aqui não se toma
# trava de caixa nem de telefone, então não há espera cruzada: uma reserva para a pessoa nova termina antes da
# conferência (e é vista por ela) ou espera a passagem terminar (e vê as reuniões que chegaram). Duas passagens
# simultâneas para a mesma pessoa se enfileiram na trava dela.
class Crm::BookingV2::Reassigner
  class InvalidPeople < StandardError; end

  Result = Struct.new(:moved, :conflicts, keyword_init: true) do
    def as_json(*)
      { moved: moved, conflicts: conflicts }
    end
  end

  REASON = 'manual'.freeze

  def initialize(account:, from_user_id:, to_user_id:, page: nil, actor: nil)
    @account = account
    @from_user_id = from_user_id.to_i
    @to_user = account.users.find_by(id: to_user_id)
    @page = page
    @actor = actor
  end

  def preview
    validate!
    run(write: false)
  end

  def perform
    validate!
    ActiveRecord::Base.transaction do
      lock_people!
      validate!
      run(write: true)
    end
  end

  private

  attr_reader :account, :from_user_id, :to_user, :page

  def validate!
    raise InvalidPeople if from_user_id.zero? || to_user.blank? || to_user.id == from_user_id
    raise InvalidPeople unless Crm::BookingV2::HostEligibility.eligible?(account: account, user: to_user)
  end

  def lock_people!
    connection = ActiveRecord::Base.connection
    [from_user_id, to_user.id].sort.each do |user_id|
      connection.execute("SELECT pg_advisory_xact_lock(#{Crm::BookingV2::Booker::LOCK_NS_AGENT}, #{user_id.to_i})")
    end
  end

  def run(write:)
    planned = []
    conflicts = []
    meetings.each do |meeting|
      next conflicts << conflict_row(meeting) if busy?(meeting, planned)

      planned << { start: meeting.starts_at, end: meeting.ends_at }
      handover(meeting) if write
    end
    Result.new(moved: planned.size, conflicts: conflicts)
  end

  def meetings
    page_ids = page ? [page.id] : account.crm_agent_booking_profiles.new_pages.pluck(:id)
    account.crm_meetings.upcoming.by_agent(from_user_id)
           .where("crm_meetings.metadata ->> 'booking_profile_id' IN (?)", page_ids.map(&:to_s))
           .includes(:card, :reminder).order(:starts_at, :id).to_a
  end

  def busy?(meeting, planned)
    buffer = buffer_for(meeting)
    window_start = meeting.starts_at - buffer
    window_end = meeting.ends_at + buffer
    taken = Crm::BookingV2::Slots.busy_intervals(account_id: account.id, host_id: to_user.id, from: window_start, to: window_end)
    (taken + planned).any? { |interval| window_start < interval[:end] && interval[:start] < window_end }
  end

  def buffer_for(meeting)
    @buffers ||= account.crm_agent_booking_profiles.new_pages.pluck(:id, :buffer_minutes).to_h
    @buffers.fetch(meeting.metadata.to_h['booking_profile_id'].to_i, 0).minutes
  end

  def conflict_row(meeting)
    { meeting_id: meeting.id, starts_at: meeting.starts_at.iso8601, title: meeting.title }
  end

  def handover(meeting)
    Crm::BookingV2::MeetingHandover.new(meeting: meeting, from_user_id: from_user_id, to_user: to_user, actor: @actor, reason: REASON).perform
  end
end
