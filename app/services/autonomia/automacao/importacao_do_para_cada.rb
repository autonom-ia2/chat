# O registro de importação do passo "para cada item" (#2414 G24, #2771, decisão 15 do Rodrigo): a lista que a IA achou
# aparece em Contatos > Importações como uma importação de contatos (CampaignImport, flow "contacts"), com a origem
# "automacao", os ids da automação e da execução, e quem ligou como quem importou. Uma linha por item, como a da
# planilha: telefone só mascarado e em hash (PhoneMask, o mesmo do import), o contato, se já existia e a empresa.
#
# - Um registro por rodada do passo. A nova tentativa (erro passageiro, ou a automação religada depois de `sem_acesso`)
#   acha o mesmo registro pelo id guardado na execução e reescreve as linhas pelo número delas: nada duplica.
# - O item sem telefone de celular do Brasil e o contato que a conta recusa ficam de fora (linha `invalid`, com o
#   motivo), como as linhas com problema da planilha. O item que não chegou a rodar (quem ligou perdeu a permissão no
#   meio) conta em `failed_contacts_count`.
# - Sem arquivo: não há CSV de problemas, nem `source_filename`. O nome é o da automação.
class Autonomia::Automacao::ImportacaoDoParaCada
  TELEFONE_INVALIDO = 'invalid_brazilian_mobile_number'.freeze
  CONTATO_RECUSADO = 'contact_rejected'.freeze

  def self.abrir(execucao:, passo_id:, account_user:, total:)
    chave = "#{passo_id}.importacao"
    importacao = execucao.account.campaign_imports.contact_imports.find_by(id: execucao.textos.to_h[chave])
    importacao ||= criar(execucao, account_user, total).tap { |nova| execucao.guardar_texto!(chave, nova.id.to_s) }
    new(importacao)
  end

  def self.criar(execucao, account_user, total)
    agora = Time.current
    execucao.account.campaign_imports.create!(
      user: account_user.user, status: :importing, mode: 'single_label', batch_count: 1, name: execucao.automacao.nome,
      total_rows: total, confirmed_at: agora, import_started_at: agora,
      options: { flow: CampaignImport::CONTACTS_FLOW, origem: CampaignImport::AUTOMATION_ORIGIN, default_country: 'BR',
                 automacao_id: execucao.automacao_id, execucao_id: execucao.id }
    )
  end
  private_class_method :criar

  attr_reader :campaign_import

  def initialize(campaign_import)
    @campaign_import = campaign_import
  end

  # escrito: o CampaignImports::ContactRow::Result do item.
  def entrou(numero, escrito, nome:, telefone:)
    linha(numero, nome, telefone && ::CampaignImports::PhoneMask.mask(telefone)).update!(
      status: :imported, error_messages: [], contact_id: escrito.contact.id, was_existing_contact: escrito.existing,
      normalized_name: nome, normalized_phone_hash: telefone && Digest::SHA256.hexdigest(telefone),
      company_id: escrito.company&.company&.id, company_result: escrito.company&.status&.to_s
    )
  end

  def ficou_de_fora(numero, nome:, telefone_escrito:, motivo:)
    mascarado = telefone_escrito.present? ? ::CampaignImports::PhoneMask.mask(telefone_escrito) : nil
    linha(numero, nome, mascarado).update!(status: :invalid, error_messages: [motivo], contact_id: nil)
  end

  def atributos_criados(quantos)
    return if quantos.zero?

    resumo = campaign_import.validation_summary.to_h
    campaign_import.update!(validation_summary: resumo.merge('contact_attributes_created' => resumo['contact_attributes_created'].to_i + quantos))
  end

  # Os números saem das linhas gravadas, como no fim do import da planilha.
  def fechar!
    linhas = campaign_import.campaign_import_rows
    entraram = linhas.status_imported.count
    de_fora = linhas.status_invalid.count
    nao_rodaram = [campaign_import.total_rows - entraram - de_fora, 0].max
    campaign_import.update!(
      status: (de_fora + nao_rodaram).zero? ? :completed : :completed_with_failures,
      valid_rows: campaign_import.total_rows - de_fora, invalid_rows: de_fora,
      imported_contacts_count: entraram, existing_contacts_count: linhas.status_imported.where(was_existing_contact: true).count,
      failed_contacts_count: nao_rodaram, import_finished_at: Time.current,
      **::CampaignImports::ImportCompanies.new(campaign_import).counters
    )
  end

  private

  def linha(numero, nome, telefone_mascarado)
    campaign_import.campaign_import_rows.find_or_initialize_by(row_number: numero).tap do |registro|
      registro.assign_attributes(raw_name: nome, raw_phone_masked: telefone_mascarado)
    end
  end
end
