class Contacts::BulkDeleteService
  def initialize(account:, contact_ids: [], user: nil)
    @account = account
    @contact_ids = Array(contact_ids).compact
    @user = user
  end

  def perform
    return if @contact_ids.blank?
    # Sem a flag crm_arquivados, como na main (decisão do Rodrigo, 23/10).
    return contacts.find_each(&:destroy!) unless Crm::Cards::Anonimizador.ligado?(@account)

    contacts.find_each { |contact| destroy_contact(contact) }
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end

  # LGPD (#2096, com a flag crm_arquivados): os cards do CRM ficam sem dado pessoal (ContactCrmCards), e a reunião futura
  # deles é cancelada antes, fora da transação. Um contato que não sai (o calendário falhou, um card mudou sob a trava ou
  # qualquer outro erro) fica inteiro, vai para o log com o motivo em código, e o lote segue com os outros.
  def destroy_contact(contact)
    anonimizador = Crm::Cards::Anonimizador.new(contact: contact)
    anonimizador.cancelar_reunioes!
    contact.crm_reunioes_canceladas = anonimizador.reunioes_canceladas
    contact.crm_excluido_por = @user
    contact.destroy!
  rescue StandardError => e
    Rails.logger.warn("[contacts][bulk_delete] contact=#{contact.id} kept: #{motivo(e)}")
  end

  def motivo(error)
    case error
    when Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada then "meeting #{error.meeting_id} not canceled at the calendar"
    when Crm::ExclusaoDefinitiva::Mudou then error.motivo
    else error.class.name
    end
  end
end
