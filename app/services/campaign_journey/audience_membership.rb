# Põe e tira pessoas de um Público que já existe (#2775). O CampaignJourney::AudienceWriter só cria; este serviço muda
# o Público depois, para a Prospecção (listas que juntam buscas) e para quem mais precisar (a Automação, G4).
#
# - add(audience, rows): rows são CampaignJourney::AudienceWriter::Row, as mesmas do writer. Quem já está (linha
#   imported) não entra de novo. Quem tinha sido tirado volta na MESMA linha, com os dados novos (o hash atual do
#   telefone e do e-mail, que é a prova de consentimento que o envio confere de novo). Quem não tem linha ganha uma no
#   fim (row_number = maior + 1). Nunca há duas linhas do mesmo contato por causa deste serviço.
# - remove(audience, contact_ids): a linha não é apagada; vai para o status removed, que nenhum leitor de envio,
#   contagem ou amostra lê (todos filtram por imported ou valid).
#
# Os dois:
# - trancam a linha do Público (lock!) antes de ler o maior row_number e as linhas; é a mesma ordem do
#   EmailAudienceGate (o Público primeiro), que tranca a mesma linha antes de sincronizar a lista de e-mail;
# - recusam o Público já usado em campanha que saiu (CampaignJourney::AudienceUsage, Error 'audience_locked');
# - recusam o que não é Público concluído (Error 'not_audience');
# - acertam os contadores do Público (total_rows, valid_rows, imported_contacts_count, existing_contacts_count) pela
#   diferença de linhas imported, e recontam os canais pelos contatos (AudienceWriter.recount_channels);
# - gravam linha a linha (create!/update!), nunca em lote: quem observa as linhas (callback do #2717) vê cada mudança.
#
# Canal: aqui só se reconta. O canal nunca é ligado (nem fora do zero): o CampaignImport não registra se a pessoa
# desligou o canal à mão (channels guarda só enabled e count), então ligar poderia desfazer a escolha dela. Quem passa a
# ter gente num canal desligado o liga em Campanhas > Públicos. Um canal que fica sem ninguém desliga sozinho, como em
# todo recount (CampaignJourney::AudienceContacts.recounted_channels).
module CampaignJourney::AudienceMembership
  Error = Class.new(StandardError)
  LOCKED = 'audience_locked'.freeze
  # O Público pronto: o da planilha que terminou (com ou sem falhas em algumas linhas) e o salvo pelo writer.
  EDITABLE_STATUSES = %w[completed completed_with_failures].freeze
  AddResult = Struct.new(:audience, :added_contact_ids, :skipped_contact_ids, keyword_init: true)
  RemoveResult = Struct.new(:audience, :removed_contact_ids, keyword_init: true)

  module_function

  def add(audience, rows)
    rows = rows.uniq(&:contact_id)
    raise Error, 'no_rows' if rows.empty?

    ensure_audience!(audience)
    raise Error, 'foreign_contact' unless own_contacts?(audience, rows)

    ActiveRecord::Base.transaction do
      lock!(audience)
      added, skipped, existing_delta = place_rows(audience, rows)
      update_counters!(audience, added.size, existing_delta)
      CampaignJourney::AudienceWriter.recount_channels(audience)
      AddResult.new(audience: audience, added_contact_ids: added, skipped_contact_ids: skipped)
    end
  end

  def remove(audience, contact_ids)
    ensure_audience!(audience)

    ActiveRecord::Base.transaction do
      lock!(audience)
      rows = audience.campaign_import_rows.status_imported.where(contact_id: Array(contact_ids)).to_a
      rows.each { |row| row.update!(status: :removed) }
      update_counters!(audience, -rows.size, -rows.count(&:was_existing_contact))
      CampaignJourney::AudienceWriter.recount_channels(audience)
      RemoveResult.new(audience: audience, removed_contact_ids: rows.map(&:contact_id).uniq)
    end
  end

  def ensure_audience!(audience)
    raise Error, 'not_audience' unless audience&.audience? && EDITABLE_STATUSES.include?(audience.status)
  end

  def own_contacts?(audience, rows)
    audience.account.contacts.where(id: rows.map(&:contact_id)).count == rows.size
  end

  def lock!(audience)
    audience.lock!
    raise Error, LOCKED if CampaignJourney::AudienceUsage.locked?(audience)
  end

  # [ids que entraram, ids que já estavam, quantos dos que entraram já eram contato antes].
  def place_rows(audience, rows)
    existing = audience.campaign_import_rows.where(contact_id: rows.map(&:contact_id)).group_by(&:contact_id)
    numbers = (audience.campaign_import_rows.maximum(:row_number).to_i + 1..).each
    outcomes = rows.map { |row| place_row(audience, row, existing[row.contact_id].to_a, numbers) }
    added = outcomes.reject { |outcome| outcome[:skipped] }
    [added.pluck(:contact_id), outcomes.select { |outcome| outcome[:skipped] }.pluck(:contact_id), added.count { |outcome| outcome[:existing] }]
  end

  # Quem tem linha ativa (qualquer status que não removed) fica como está; quem foi tirado volta na mesma linha; o resto
  # ganha a próxima linha.
  def place_row(audience, row, lines, numbers)
    return { contact_id: row.contact_id, skipped: true } if lines.any? { |line| !line.status_removed? }

    line = lines.first
    line ? reactivate!(line, row) : create_row!(audience, row, numbers.next)
    { contact_id: row.contact_id, skipped: false, existing: line.nil? || line.was_existing_contact }
  end

  def reactivate!(line, row)
    line.update!(CampaignJourney::AudienceWriter.row_attributes(row).merge(status: :imported))
  end

  def create_row!(audience, row, row_number)
    audience.campaign_import_rows.create!(
      CampaignJourney::AudienceWriter.row_attributes(row).merge(
        row_number: row_number, batch_index: 0, status: :imported, was_existing_contact: true,
        labels_applied: [], error_messages: []
      )
    )
  end

  def update_counters!(audience, delta, existing_delta)
    return if delta.zero?

    audience.update!(
      total_rows: audience.total_rows.to_i + delta, valid_rows: audience.valid_rows.to_i + delta,
      imported_contacts_count: audience.imported_contacts_count.to_i + delta,
      existing_contacts_count: audience.existing_contacts_count.to_i + existing_delta
    )
  end
end
