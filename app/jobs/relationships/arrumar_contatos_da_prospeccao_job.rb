# #3176 — arruma os contatos que a Prospecção criou antes da correção do conversor (Autonomia::Prospecting::ContactConverter):
#
# - "Sobre a pessoa" (additional_attributes description) recebia a categoria do Google crua, em inglês ("doctor"). Sai,
#   mas só quando ainda é a categoria daquele lead: o texto que alguém escreveu fica.
# - O cargo do decisor ia em additional_attributes job_title, que nenhuma tela mostra. Passa para custom_attributes
#   job_title, onde o card, o Decisor e a ficha o leem, quando foi a Prospecção que o gravou (igual à marca
#   WRITTEN_JOB_TITLE_KEY) e o job_title de custom_attributes está vazio. Cargo que não é nosso fica onde está.
#
# Só o contato que o lead gravou (ContactConverter.owner_lead_id). Nenhum outro dado muda: as chaves internas (lead,
# fornecedor, código do lugar, quem converteu, as marcas) continuam gravadas, porque a Prospecção depende delas; a tela é
# que as esconde (Relationships::ChavesInternas). Idempotente: rodar de novo não acha mais nada para arrumar.
#
# Não é enfileirado por migration nem por callback: roda à mão, com OK do dono, de uma conta (account_id) ou de todas.
# Anda pelos leads com contato (índice em contact_id), e não por uma busca no JSON de todos os contatos.
class Relationships::ArrumarContatosDaProspeccaoJob < ApplicationJob
  queue_as :async_database_migration

  LOG = '[arrumar_contatos_da_prospeccao]'.freeze
  CONVERSOR = Autonomia::Prospecting::ContactConverter

  def perform(account_id = nil)
    leads = Autonomia::Prospecting::Lead.where.not(contact_id: nil).includes(:contact)
    leads = leads.where(account_id: account_id) if account_id
    arrumados = leads.find_each.count { |lead| arrumar(lead) }
    Rails.logger.info("#{LOG} account=#{account_id || 'todas'} arrumados=#{arrumados}")
    arrumados
  end

  private

  def arrumar(lead)
    contact = lead.contact
    return false unless CONVERSOR.owner_lead_id(contact) == lead.id

    proprios, adicionais = com_cargo_movido(contact.custom_attributes.to_h, sem_categoria(lead, contact.additional_attributes.to_h))
    return false if proprios == contact.custom_attributes.to_h && adicionais == contact.additional_attributes.to_h

    contact.update!(custom_attributes: proprios, additional_attributes: adicionais)
    true
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.error("#{LOG} contact=#{contact&.id} falhou: #{e.class}")
    ChatwootExceptionTracker.new(e, account: lead.account).capture_exception
    false
  end

  def sem_categoria(lead, adicionais)
    return adicionais if lead.category.blank? || adicionais['description'] != lead.category

    adicionais.except('description')
  end

  # -> [custom_attributes, additional_attributes], cópias novas; sem nada a mover, os mesmos que entraram.
  def com_cargo_movido(proprios, adicionais)
    cargo = adicionais[CONVERSOR::JOB_TITLE_KEY]
    nosso = cargo.present? && cargo == proprios[CONVERSOR::WRITTEN_JOB_TITLE_KEY]
    return [proprios, adicionais] unless nosso && proprios[CONVERSOR::JOB_TITLE_KEY].blank?

    [proprios.merge(CONVERSOR::JOB_TITLE_KEY => cargo), adicionais.except(CONVERSOR::JOB_TITLE_KEY)]
  end
end
