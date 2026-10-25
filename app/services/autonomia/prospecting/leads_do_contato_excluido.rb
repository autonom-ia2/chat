# Contato excluído (#2143, LGPD): o lead da Prospecção que é desta pessoa sai de vez. Sem isto, a chave estrangeira só
# soltava o lead do contato e do card, e ficavam nome, telefone, e-mail e WhatsApp achados, o decisor e as redes dele.
#
# O lead é desta pessoa quando:
# - é o dono do contato: o lead que gravou o contato (ContactConverter.owner_lead_id) e continua ligado a ele;
# - ou chega a ela só pelo card: aponta para um card do contato (crm_card_id) e para contato nenhum. O lead que aponta
#   para outro contato vivo (o card foi religado a outra pessoa, Crm::Cards::ContactLinker) é daquela pessoa e fica.
# O mesmo telefone ou e-mail pode ser de mais de um negócio (central única, franquia, escritório): a conversão liga o
# lead de outra empresa ao contato que já existia, sem renomeá-lo (ContactConverter). Esse lead não é desta pessoa e só
# perde o vínculo, pela chave estrangeira, como na main. O lead importado antes de o contato existir é o caso comum: a
# busca o achou no Google e a conversão gravou o contato a partir dele.
#
# A linha inteira sai, e não só as colunas com dado pessoal: o lead não entra em número de venda nem de meta (o total de
# cada busca fica gravado nela, em results_count), e uma coluna nova não escapa da limpeza por esquecimento. As
# listas perdem o lead pela cascata do banco. Enriquecimento, pesquisa e verificação de WhatsApp que estejam rodando
# relêem o lead antes de gravar e param ao não achá-lo.
#
# O lead que recusou contato (consent_refused) não sai: a recusa é a prova de que a pessoa pediu para não receber
# mensagem, e o telefone, o WhatsApp e o e-mail dele vetam a campanha a quem tem o mesmo número
# (Autonomia::Prospecting::ConsentVeto). Ele fica só com isso (PROVA_DA_RECUSA e METADATA_DA_RECUSA, as verificações de
# WhatsApp que o veto lê), mais o que a linha precisa para existir. O resto é zerado: cada coluna volta ao padrão do
# banco (nula, quando pode), o nome vira "Lead removido #id", e o lead sai das listas.
#
# Roda dentro da transação de quem exclui o contato, depois da trava do contato e dos cards, com as linhas dos leads
# travadas: um lead que recusa no mesmo instante (Autonomia::Prospecting::ContactOptOutSync) ou é lido já recusado e
# fica, ou espera esta exclusão terminar.
class Autonomia::Prospecting::LeadsDoContatoExcluido
  LEAD = Autonomia::Prospecting::Lead
  # pluck devolve o status como o nome do enum.
  RECUSA = 'no_consent'.freeze
  PROVA_DA_RECUSA = %w[phone enriched_whatsapp enriched_email consent_refused_at consent_refused_by_id status].freeze
  METADATA_DA_RECUSA = %w[whatsapp_verification site_whatsapp_verification].freeze
  # O que a linha precisa para existir.
  ESTRUTURA = %w[id account_id provider created_at updated_at].freeze
  # Escritas à parte, no mesmo UPDATE: o nome, o metadata reduzido e a chave de duplicidade (nome_e_metadata).
  A_PARTE = %w[name metadata dedupe_key].freeze
  FICAM = (PROVA_DA_RECUSA + ESTRUTURA + A_PARTE).freeze
  # Pesquisa e enriquecimento encerrados: nada volta à fila para um lead que só existe como prova.
  ENCERRADO = { 'enrichment_status' => 'skipped' }.freeze

  attr_reader :apagados, :minimizados

  # Criado antes de os cards do contato saírem ou serem anonimizados (que soltam o lead deles), e já dentro da transação
  # de quem exclui. O perform roda depois, com os cards travados: a mesma ordem de travas do resto do CRM.
  def initialize(contact:)
    @contact = contact
    # Relido do banco, sob a trava do contato: a conversão que terminou enquanto a exclusão esperava já gravou o dono.
    @dono = Autonomia::Prospecting::ContactConverter.owner_lead_id(Contact.select(:id, :custom_attributes).find(contact.id))
    @pelos_cards = LEAD.where(account_id: contact.account_id, crm_card_id: contact.crm_cards.select(:id))
                       .where(contact_id: nil).pluck(:id)
    @apagados = []
    @minimizados = []
  end

  def perform
    leads = desta_pessoa.order(:id).lock.pluck(:id, :consent_refused_at, :status)
    @minimizados = leads.select { |_id, recusado_em, status| recusado_em.present? || status == RECUSA }.map(&:first)
    @apagados = leads.map(&:first) - @minimizados
    LEAD.where(id: @apagados).delete_all if @apagados.any?
    minimizar! if @minimizados.any?
    self
  end

  private

  def desta_pessoa
    da_conta = LEAD.where(account_id: @contact.account_id)
    dono = @dono ? da_conta.where(id: @dono, contact_id: @contact.id) : da_conta.none
    dono.or(da_conta.where(id: @pelos_cards))
  end

  def minimizar!
    Autonomia::Prospecting::ListLead.where(prospect_lead_id: @minimizados).delete_all
    LEAD.where(id: @minimizados).update_all(zerados.merge(nome_e_metadata)) # rubocop:disable Rails/SkipsModelValidations
  end

  # Cada coluna fora de FICAM volta ao padrão do banco: nula quando pode, senão o valor padrão dela.
  def zerados
    LEAD.columns.each_with_object({}) do |coluna, valores|
      next if FICAM.include?(coluna.name)

      valores[coluna.name] = coluna.null ? nil : LEAD.column_defaults[coluna.name]
    end.merge(ENCERRADO).merge('updated_at' => Time.current)
  end

  def nome_e_metadata
    prefixo = LEAD.connection.quote(I18n.t('autonomia.prospecting.lead_removido'))
    chaves = METADATA_DA_RECUSA.map { |chave| LEAD.connection.quote(chave) }.join(', ')
    {
      'name' => Arel.sql("#{prefixo} || id::text"),
      # Sem o lugar no Google, a chave é o nome do negócio (Lead#ensure_dedupe_key): sai também. Com ele, fica (pergunta
      # em aberto no PR: liberar ou não a reimportação do mesmo lugar).
      'dedupe_key' => Arel.sql("CASE WHEN COALESCE(provider_place_id, '') = '' THEN provider || ':removido-' || id::text " \
                               'ELSE dedupe_key END'),
      'metadata' => Arel.sql("(SELECT COALESCE(jsonb_object_agg(chave, valor), '{}'::jsonb) FROM jsonb_each(" \
                             "CASE WHEN jsonb_typeof(metadata) = 'object' THEN metadata ELSE '{}'::jsonb END) " \
                             "AS item(chave, valor) WHERE chave IN (#{chaves}))")
    }
  end
end
