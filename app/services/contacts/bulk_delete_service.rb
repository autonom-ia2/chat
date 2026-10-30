class Contacts::BulkDeleteService
  INTERNO = 'internal_error'.freeze

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
  # deles é cancelada antes, fora da transação, pelo mesmo anonimizador que o destroy usa (a Auditoria soma as reuniões).
  # Um contato que não sai (o calendário falhou, um card mudou sob a trava ou qualquer outro erro) fica inteiro e o lote
  # segue com os outros. O motivo vai para a Auditoria da conta (só ids e código) e, no erro inesperado, para o
  # rastreador de erros: o log some no deploy.
  def destroy_contact(contact)
    anonimizador = Crm::Cards::Anonimizador.new(contact: contact)
    anonimizador.cancelar_reunioes!
    contact.crm_anonimizador = anonimizador
    contact.crm_excluido_por = @user
    # Impasse com a conversão de um lead do mesmo contato (#2143): refaz, como a exclusão definitiva.
    Crm::ExclusaoDefinitiva.com_retentativa { contact.destroy! }
  rescue StandardError => e
    contato_ficou(contact, e)
  end

  def contato_ficou(contact, error)
    motivo, extras = motivo(error)
    Rails.logger.warn("[contacts][bulk_delete] contact=#{contact.id} kept: #{motivo}")
    ChatwootExceptionTracker.new(error, account: @account, user: @user).capture_exception if motivo == INTERNO
    Crm::ExclusaoDefinitiva.contato_falhou!(contact: contact, user: @user, motivo: motivo, **extras)
  end

  def motivo(error)
    case error
    when Crm::ExclusaoDefinitiva::ReuniaoNaoCancelada
      ['meeting_cancel_failed', { meeting_id: error.meeting_id, canceled_meeting_ids: error.canceladas.presence }]
    when Crm::ExclusaoDefinitiva::Mudou then [error.motivo, { canceled_meeting_ids: error.canceladas.presence }]
    else [INTERNO, { error_class: error.class.name }]
    end
  end
end
