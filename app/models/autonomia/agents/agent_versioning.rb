# #1428 — A VERSÃO GUARDA O AGENTE INTEIRO. Até aqui a versão guardava só a instrução, e o Construtor não
# gravava versão nenhuma: em 13/10 (conta 16) uma pergunta virou aplicação e regravou o agente sem rastro
# nem caminho de volta. Agora toda versão leva, em `metadata['agente']`, os campos que o Construtor e a
# edição mudam; voltar a ela devolve todos. A instrução continua na coluna própria da versão.
#
# `reason` diz a origem: builder_create / builder_adjust (Construtor), base (o estado de antes da primeira
# aplicação com versão completa), manual_edit, kb_refresh e rollback (nomes que já estão no banco).
#
# Nada daqui sai pela API: o jbuilder da versão não lê `metadata`, e instrução e andaime continuam ocultos.
module Autonomia::Agents::AgentVersioning
  extend ActiveSupport::Concern

  # As colunas que `Builder.map_attributes` escreve, menos a instrução (coluna própria da versão).
  CAMPOS = %w[name agent_type scaffold tone handoff_rule greeting fallback_message starter_questions human_card].freeze
  # As chaves do jsonb `config` que o Construtor escreve. As demais (topic_map, model, agenda…) não são
  # versionadas e ficam como estão ao voltar.
  CHAVES_DA_CONFIG = %w[guardrails voice].freeze

  # Grava um snapshot do agente ATUAL persistido. IDEMPOTENTE pela instrução: no-op (nil) se o agente não
  # tem instrução ou se a última versão já tem o mesmo texto (o refresh que produz o mesmo texto).
  # `created_by` = quem editou (nil = sistema).
  def record_instruction_version!(reason:, created_by: nil)
    return if instruction.blank?

    last = instruction_versions.order(created_at: :desc, id: :desc).first
    return if last&.instruction_hash == hash_da_instrucao

    gravar_versao!(reason, created_by&.id)
  end

  # VOLTAR A UMA VERSÃO. Versão completa devolve todos os campos guardados; versão antiga, só com a
  # instrução, devolve só a instrução. Grava uma versão 'rollback' na MESMA transação (sem dedup: voltar é
  # um evento pedido pelo usuário). A versão tem de ser deste agente (false caso contrário).
  # update_columns: o agente não tem callback nos campos versionados e o snapshot já foi validado ao gravar.
  def restore_instruction!(version, created_by: nil)
    recusar_se_instrucao_mantida!
    return false if version.blank? || version.autonomia_agent_id != id

    transaction do
      lock!
      update_columns(atributos_da_versao(version).merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
      gravar_versao!('rollback', created_by&.id)
    end
    true
  end

  # Envolve a escrita do Construtor (`apply_builder_config!`, dentro da trava do agente). Antes: se ainda
  # não há versão completa e o agente já tem instrução, guarda o estado de antes ('base'). Depois, se a
  # escrita venceu, grava 1 versão da aplicação — mesmo sem mudança, porque é o rastro da aplicação.
  def versionar_aplicacao_do_construtor(autor_id)
    antes = estado_versionado
    criacao = instruction.blank?
    gravar_versao!('base', nil) unless criacao || versao_completa?
    venceu = yield
    # Sem instrução não há versão (a coluna é obrigatória); a escrita do Construtor não cai por isso.
    return venceu unless venceu && instruction.present?

    extra = estado_versionado == antes ? { 'sem_mudanca' => true } : {}
    gravar_versao!(criacao ? 'builder_create' : 'builder_adjust', autor_id, extra: extra)
    venceu
  end

  private

  def estado_versionado
    { 'instruction' => instruction.to_s, 'agente' => retrato_da_versao }
  end

  def retrato_da_versao
    atual = config.to_h
    CAMPOS.index_with { |campo| self[campo] }.merge('config' => CHAVES_DA_CONFIG.index_with { |chave| atual[chave] })
  end

  def versao_completa?
    instruction_versions.where("metadata ? 'agente'").exists?
  end

  def atributos_da_versao(version)
    agente = version.metadata.to_h['agente']
    return { instruction: version.instruction } unless agente.is_a?(Hash)

    config_guardada = agente['config'].to_h.slice(*CHAVES_DA_CONFIG)
    agente.slice(*CAMPOS).merge('instruction' => version.instruction, 'config' => config.to_h.merge(config_guardada))
  end

  def hash_da_instrucao
    Digest::SHA256.hexdigest(instruction.to_s)
  end

  # Cria a linha de versão com o agente inteiro (sem dedup — o dedup é do chamador público).
  def gravar_versao!(reason, autor_id, extra: {})
    instruction_versions.create!(
      account_id: account_id, instruction: instruction.to_s, instruction_hash: hash_da_instrucao,
      reason: reason, created_by_id: autor_id,
      metadata: { 'agente' => retrato_da_versao }.merge(extra)
    )
  end
end
