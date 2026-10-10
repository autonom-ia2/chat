# Conferência de agenda de quem RECEBE reuniões (#1195): usada por quem passa reuniões de uma pessoa para outra — o
# "Passar reuniões" do admin (`Reassigner`) e a saída de alguém da conta (`OrphanReassigner`). As duas seguem a mesma
# regra, para nunca deixar duas reuniões no mesmo horário com a mesma pessoa.
#
# Travas (`lock!`): as de agente (`Booker::LOCK_NS_AGENT`) de TODAS as pessoas envolvidas, numa vez só e em ordem
# crescente de id. O Booker toma caixa (1), UMA de agente (2) e telefone (4), nessa ordem; quem passa reuniões só
# toma travas de agente, sempre em ordem crescente, então duas passagens (ou uma passagem e uma saída) que envolvem
# as mesmas pessoas nunca esperam uma pela outra em cruz, e uma reserva para quem recebe termina antes da conferência
# ou espera a passagem terminar.
#
# Livre (`free?`): a pessoa não tem reunião `scheduled` (de qualquer caixa, e as internas) que cruze o horário com o
# intervalo da página da reunião (mesma regra do `Slots`), nem reunião que esta mesma passagem já lhe deu (`reserve`).
# A agenda Google/Microsoft fica de fora: é da CAIXA da página, não da pessoa (ver `Reassigner`).
class Crm::BookingV2::HostSchedule
  def self.lock!(user_ids)
    connection = ActiveRecord::Base.connection
    user_ids.compact.map(&:to_i).uniq.sort.each do |user_id|
      connection.execute("SELECT pg_advisory_xact_lock(#{Crm::BookingV2::Booker::LOCK_NS_AGENT}, #{user_id})")
    end
  end

  def initialize(account:)
    @account = account
    @planned = Hash.new { |hash, key| hash[key] = [] }
  end

  def free?(meeting, host_id)
    window_start, window_end = window(meeting)
    taken = Crm::BookingV2::Slots.busy_intervals(account_id: account.id, host_id: host_id, from: window_start, to: window_end)
    (taken + planned[host_id]).none? { |interval| window_start < interval[:end] && interval[:start] < window_end }
  end

  # A reunião passou (ou vai passar, na prévia) para a pessoa: ocupa o horário dela nas conferências seguintes.
  def reserve(meeting, host_id)
    planned[host_id] << { start: meeting.starts_at, end: meeting.ends_at }
  end

  private

  attr_reader :account, :planned

  def window(meeting)
    buffer = buffer_for(meeting)
    [meeting.starts_at - buffer, meeting.ends_at + buffer]
  end

  def buffer_for(meeting)
    @buffers ||= account.crm_agent_booking_profiles.new_pages.pluck(:id, :buffer_minutes).to_h
    @buffers.fetch(meeting.metadata.to_h[Crm::BookingV2::AttentionReport::PAGE_KEY].to_i, 0).minutes
  end
end
