# Cancela as reuniões futuras de cards que vão sair (excluir de vez) ou perder o cliente (contato excluído com os cards
# mantidos sem dado pessoal), #2096. Pelo Crm::Meetings::CancelService: no Google e na Microsoft o cliente recebe o
# cancelamento e o card ganha a atividade "reunião cancelada"; a reunião só do WhatsApp (interna) é cancelada só aqui,
# como no "Cancelar" da agenda.
#
# Reunião do Google ou da Microsoft cujo calendário não se alcança mais (a caixa foi removida e o inbox_id ficou nulo, a
# caixa não é mais de e-mail ou o calendário foi desligado nela) não tem a quem pedir o cancelamento: é cancelada só
# aqui, com aviso no log. Esperar por ela travaria a exclusão para sempre.
#
# Fora de transação, de preferência: a chamada ao calendário leva segundos e não volta atrás. Qualquer outra falha ao
# cancelar (erro do provedor, rede, token que não renova) para e levanta Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada,
# com as que já foram canceladas antes dela (essas ficam canceladas: o cliente já foi avisado). Erro do banco não é
# falha do calendário e sobe como veio.
class Crm::Meetings::CancelarFuturas
  def initialize(account:, card_ids:)
    @account = account
    @card_ids = Array(card_ids)
    @canceladas = []
    @so_aqui = []
  end

  # As canceladas só aqui (calendário fora de alcance): o evento pode continuar vivo no Google ou na Microsoft.
  attr_reader :so_aqui

  # Devolve os ids das reuniões canceladas agora.
  def perform
    return @canceladas if @card_ids.empty?

    Crm::Meeting.where(account_id: @account.id, card_id: @card_ids).upcoming.order(:id).each do |meeting|
      cancelar!(meeting)
      @canceladas << meeting.id
    end
    @canceladas
  end

  def self.calendario_alcancavel?(meeting)
    return true if meeting.internal?

    canal = meeting.email_channel
    canal.is_a?(Channel::Email) && canal.calendar_enabled?
  end

  private

  def cancelar!(meeting)
    alcancavel = self.class.calendario_alcancavel?(meeting)
    Crm::Meetings::CancelService.new(meeting: meeting, propagate: alcancavel, validar: false).perform
    avisar_so_aqui(meeting) unless alcancavel
    @so_aqui << meeting.id unless alcancavel
  rescue ActiveRecord::ActiveRecordError
    raise
  rescue StandardError => e
    Rails.logger.warn("[crm][cancelar_futuras] meeting=#{meeting.id} provider=#{meeting.provider} not canceled: #{e.class.name}")
    raise Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada.new(meeting.id, @canceladas.dup)
  end

  def avisar_so_aqui(meeting)
    Rails.logger.warn("[crm][cancelar_futuras] meeting=#{meeting.id} provider=#{meeting.provider} " \
                      "inbox=#{meeting.inbox_id.inspect} canceled only here: calendar unreachable")
  end
end
