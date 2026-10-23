class Contacts::BulkDeleteService
  def initialize(account:, contact_ids: [])
    @account = account
    @contact_ids = Array(contact_ids).compact
  end

  def perform
    return if @contact_ids.blank?

    contacts.find_each { |contact| destroy_contact(contact) }
  end

  private

  def contacts
    @account.contacts.where(id: @contact_ids)
  end

  # LGPD (#2096): os cards do CRM ficam sem dado pessoal (ContactCrmCards), e a reunião futura deles é cancelada antes,
  # fora da transação. Se o calendário falhar, esse contato fica, inteiro, e o lote segue com os outros.
  def destroy_contact(contact)
    Crm::Cards::Anonimizador.new(contact: contact).cancelar_reunioes!
    contact.destroy!
  rescue Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada => e
    Rails.logger.warn("[contacts][bulk_delete] contact=#{contact.id} kept: meeting #{e.meeting_id} not canceled at the calendar")
  end
end
