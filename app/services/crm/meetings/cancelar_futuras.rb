# Cancela as reuniões futuras de cards que vão sair (excluir de vez) ou perder o cliente (contato excluído com os cards
# mantidos sem dado pessoal), #2096. Pelo Crm::Meetings::CancelService: no Google e na Microsoft o cliente recebe o
# cancelamento e o card ganha a atividade "reunião cancelada"; a reunião só do WhatsApp (interna) é cancelada só aqui,
# como no "Cancelar" da agenda.
#
# Fora de transação, de preferência: a chamada ao calendário leva segundos e não volta atrás. Se uma reunião não
# cancela, para e levanta Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada com as que já foram canceladas antes dela (essas
# ficam canceladas: o cliente já foi avisado).
class Crm::Meetings::CancelarFuturas
  def initialize(account:, card_ids:)
    @account = account
    @card_ids = Array(card_ids)
    @canceladas = []
  end

  # Devolve os ids das reuniões canceladas agora.
  def perform
    return @canceladas if @card_ids.empty?

    Crm::Meeting.where(account_id: @account.id, card_id: @card_ids).upcoming.order(:id).each do |meeting|
      Crm::Meetings::CancelService.new(meeting: meeting).perform
      @canceladas << meeting.id
    rescue *erros_do_calendario
      raise Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada.new(meeting.id, @canceladas.dup)
    end
    @canceladas
  end

  private

  # Os mesmos erros de calendário que o "Cancelar" da agenda trata (MeetingsController#calendar_provider_error?).
  # Google::CalendarError e Microsoft::CalendarError moram no arquivo do serviço de cada um: carregar o serviço os define.
  def erros_do_calendario
    [Google::CalendarEventService, Microsoft::CalendarEventService].map { |servico| servico.module_parent::CalendarError } +
      [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED]
  end
end
