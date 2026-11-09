# O registro de importação do passo "para cada item" (#2414 G24, #2771, decisão 15 do Rodrigo): a lista que a IA achou
# aparece em Contatos > Importações como uma importação de contatos (CampaignImport, flow "contacts"), com a origem
# "automacao", os ids da automação e da execução, e quem ligou como quem importou. Uma linha por item, como a da
# planilha: telefone só mascarado e em hash (PhoneMask, o mesmo do import), o contato, se já existia e a empresa.
#
# - Um registro por rodada do passo. A nova tentativa na mesma execução (erro passageiro) acha o mesmo registro pelo id
#   guardado nela e reescreve as linhas pelo número delas: nada duplica. A automação religada depois de `sem_acesso`
#   começa outra execução e outro registro; o da rodada pausada fica em `importing` com o que entrou.
# - O item sem telefone de celular do Brasil e o contato que a conta recusa ficam de fora (linha `invalid`, com o
#   motivo), como as linhas com problema da planilha. O item que não chegou a rodar (quem ligou perdeu a permissão no
#   meio) não conta como falha: a rodada que pausou (`sem_acesso`) ou deu erro passageiro deixa a importação em
#   `importing`, com os números do que já rodou (#pausar!). Só o fim real fecha (#fechar!): a rodada que terminou, ou a
#   falha definitiva, quando o que não rodou conta em `failed_contacts_count`.
# - O registro nasce junto com o id guardado na execução. Execução já encerrada (desligaram no meio) não guarda o id:
#   o registro não fica (sem órfão) e `abrir` devolve nil.
# - Sem arquivo: não há CSV de problemas, nem `source_filename`. O nome é o da automação.
class Autonomia::Automacao::ImportacaoDoParaCada
  TELEFONE_INVALIDO = 'invalid_brazilian_mobile_number'.freeze
  CONTATO_RECUSADO = 'contact_rejected'.freeze

  def self.abrir(execucao:, passo_id:, account_user:, total:)
    chave = "#{passo_id}.importacao"
    existente = execucao.account.campaign_imports.contact_imports.find_by(id: execucao.textos.to_h[chave])
    return new(existente) if existente

    nova = ActiveRecord::Base.transaction(requires_new: true) do
      criar(execucao, account_user, total).tap { |importacao| raise ActiveRecord::Rollback unless execucao.guardar_texto!(chave, importacao.id.to_s) }
    end
    nova && new(nova)
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

  # O fim real: os números saem das linhas gravadas, como no fim do import da planilha, e o que não rodou é falha.
  def fechar!
    numeros = contagem
    nao_rodaram = [campaign_import.total_rows - numeros[:imported_contacts_count] - numeros[:invalid_rows], 0].max
    status = (numeros[:invalid_rows] + nao_rodaram).zero? ? :completed : :completed_with_failures
    campaign_import.update!(**numeros, failed_contacts_count: nao_rodaram, import_finished_at: Time.current, status: status)
  end

  # A rodada parou no meio e pode voltar: segue `importing`, só com os números do que já rodou.
  def pausar!
    campaign_import.update!(**contagem, failed_contacts_count: 0)
  end

  private

  def contagem
    linhas = campaign_import.campaign_import_rows
    de_fora = linhas.status_invalid.count
    { valid_rows: campaign_import.total_rows - de_fora, invalid_rows: de_fora, imported_contacts_count: linhas.status_imported.count,
      existing_contacts_count: linhas.status_imported.where(was_existing_contact: true).count,
      **::CampaignImports::ImportCompanies.new(campaign_import).counters }
  end

  def linha(numero, nome, telefone_mascarado)
    campaign_import.campaign_import_rows.find_or_initialize_by(row_number: numero).tap do |registro|
      registro.assign_attributes(raw_name: nome, raw_phone_masked: telefone_mascarado)
    end
  end
end
