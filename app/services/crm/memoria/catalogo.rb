# O catálogo de chaves da conta (#1601). Nasce dos campos personalizados (contato, card, conversa) mais as chaves do
# sistema, e só ACRESCENTA: a linha que já existe (com o que o administrador ajustou) não muda. Barato: um INSERT ... ON
# CONFLICT DO NOTHING das chaves que faltam.
#
# Padrões: campo do contato de texto, número ou link é identidade (o valor tem de estar na prova); campo do card não é,
# até o administrador marcar (a placa como item natural, por exemplo).
module Crm::Memoria::Catalogo
  DECISAO = 'decisao'.freeze
  PEDIDO_ENCERRADO = 'pedido_encerrado'.freeze
  RESULTADO_FERRAMENTA = 'resultado_ferramenta'.freeze
  SISTEMA = 'sistema'.freeze
  CHAVES_DO_SISTEMA = {
    DECISAO => { rotulo: 'Decisão', cardinalidade: 2 },
    PEDIDO_ENCERRADO => { rotulo: 'Pedido encerrado', cardinalidade: 2, validade_dias: 360 },
    RESULTADO_FERRAMENTA => { rotulo: 'Resultado de ferramenta', cardinalidade: 2 }
  }.freeze
  MODELOS = %w[contact_attribute card_attribute conversation_attribute].freeze
  TIPOS_DE_IDENTIDADE = %w[text number link].freeze
  COLUNAS = %i[attribute_model chave rotulo nivel cardinalidade validade_dias identidade].freeze

  module_function

  # -> { [attribute_model, chave] => Crm::MemoriaChave }
  def da_conta(account)
    sincronizar_se_mudou!(account)
    Crm::MemoriaChave.where(account_id: account.id).index_by { |linha| [linha.attribute_model, linha.chave] }
  end

  # Só escreve quando os campos personalizados da conta mudaram (contagem e última alteração) ou o catálogo ainda não
  # tem as chaves do sistema: a leitura quente (Leitor, avaliação) não grava a cada chamada.
  def sincronizar_se_mudou!(account)
    definicoes = account.custom_attribute_definitions.where(attribute_model: MODELOS)
    marca = [definicoes.count, definicoes.maximum(:updated_at)&.to_f, Crm::MemoriaChave.where(account_id: account.id).count]
    Rails.cache.fetch(['crm_memoria_catalogo', account.id, *marca], expires_in: 1.day) do
      sincronizar!(account)
      true
    end
  end

  def sincronizar!(account)
    agora = Time.current
    linhas = (dos_campos(account) + do_sistema(account)).map { |linha| linha.merge(account_id: account.id, created_at: agora, updated_at: agora) }
    Crm::MemoriaChave.insert_all(linhas, unique_by: :idx_crm_memoria_chaves_unica) if linhas.any? # rubocop:disable Rails/SkipsModelValidations
    sem_campo!(account)
  end

  # O campo personalizado apagado sai do catálogo: a IA deixa de poder gravar fato nele (os fatos que existem ficam).
  def sem_campo!(account)
    existentes = account.custom_attribute_definitions.where(attribute_model: MODELOS).pluck(:attribute_model, :attribute_key)
    Crm::MemoriaChave.where(account_id: account.id, attribute_model: MODELOS)
                     .reject { |linha| existentes.include?([linha.attribute_model, linha.chave]) }.each(&:destroy!)
  end

  def dos_campos(account)
    account.custom_attribute_definitions.where(attribute_model: MODELOS).map do |definicao|
      modelo = definicao.attribute_model
      { attribute_model: modelo, chave: definicao.attribute_key, rotulo: definicao.attribute_display_name,
        nivel: Crm::MemoriaChave::MODELOS.fetch(modelo), cardinalidade: 1, validade_dias: nil,
        identidade: modelo == 'contact_attribute' && TIPOS_DE_IDENTIDADE.include?(definicao.attribute_display_type.to_s) }
    end
  end

  def do_sistema(_account)
    CHAVES_DO_SISTEMA.map do |chave, padrao|
      padrao_do_sistema = { attribute_model: SISTEMA, chave: chave, nivel: SISTEMA, identidade: false, validade_dias: nil }
      padrao_do_sistema.merge(padrao).slice(*COLUNAS)
    end
  end
end
