# #1428 — A VERSÃO GUARDA O AGENTE INTEIRO. Até aqui a versão guardava só a instrução, e o Construtor não
# gravava versão nenhuma: em 13/10 (conta 16) uma pergunta virou aplicação e regravou o agente sem rastro
# nem caminho de volta. Agora toda versão leva, em `metadata['agente']`, os campos que o Construtor e a
# edição mudam; voltar a ela devolve todos. A instrução continua na coluna própria da versão.
#
# `reason` diz a origem: builder_create / builder_adjust (Construtor), base (o estado de antes da primeira
# aplicação com versão completa), antes_de_voltar (o estado de antes de uma volta, quando não estava em
# versão nenhuma), manual_edit, kb_refresh e rollback (nomes que já estão no banco).
#
# O que é oculto não sai pela API: o jbuilder da versão não lê o retrato, e o texto da instrução só sai de
# versão gravada em modo manual (`InstructionVersion#instrucao_visivel?`, #1484).
module Autonomia::Agents::AgentVersioning
  extend ActiveSupport::Concern

  # As colunas que `Builder.map_attributes` escreve, menos a instrução (coluna própria da versão), mais o
  # `mode`: voltar a uma versão guiada num agente que hoje é manual devolve o modo guiado junto — a
  # instrução gerada pelo Construtor nunca fica num agente manual, onde a API a mostraria (#1484).
  CAMPOS = %w[name agent_type mode scaffold tone handoff_rule greeting fallback_message starter_questions
              human_card].freeze
  # As chaves do jsonb `config` que o Construtor escreve. As demais (topic_map, model, agenda…) não são
  # versionadas e ficam como estão ao voltar.
  CHAVES_DA_CONFIG = %w[guardrails voice with_knowledge].freeze
  # Guardadas no retrato só para saber se a aplicação mudou algo (`sem_mudanca`); voltar NÃO as devolve.
  # `actuation`: o controller recusa agente interno com canal conectado (`reject_internal_with_channels`), e
  # a volta, que não passa por ele, poderia gravar exatamente esse estado.
  SO_PARA_COMPARAR = %w[actuation].freeze

  # Grava um snapshot do agente ATUAL persistido. IDEMPOTENTE pela instrução: no-op (nil) se o agente não
  # tem instrução ou se a última versão já tem o mesmo texto (o refresh que produz o mesmo texto).
  # `created_by` = quem editou (nil = sistema).
  def record_instruction_version!(reason:, created_by: nil)
    return if instruction.blank?
    return if ultima_versao&.instruction_hash == hash_da_instrucao

    gravar_versao!(reason, created_by&.id)
  end

  # VOLTAR A UMA VERSÃO. Versão completa devolve todos os campos guardados; versão antiga, só com a
  # instrução (ou com retrato inválido), devolve só a instrução. Antes de voltar, se o estado atual não está
  # na última versão (a saudação editada à mão não gera versão), guarda-o como 'antes_de_voltar' — voltar
  # nunca apaga trabalho sem rastro. Depois grava 'rollback' (sem dedup: é um evento pedido pelo usuário).
  # Tudo na mesma transação. A versão tem de ser deste agente (false caso contrário).
  # update_columns: o agente não tem callback nos campos versionados e o retrato é conferido antes.
  def restore_instruction!(version, created_by: nil)
    recusar_se_instrucao_mantida!
    return false if version.blank? || version.autonomia_agent_id != id

    transaction do
      lock!
      gravar_versao!('antes_de_voltar', created_by&.id) unless estado_atual_guardado?
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
    (CAMPOS + SO_PARA_COMPARAR).index_with { |campo| self[campo] }
                               .merge('config' => CHAVES_DA_CONFIG.index_with { |chave| atual[chave] })
  end

  def ultima_versao
    instruction_versions.order(created_at: :desc, id: :desc).first
  end

  # O estado atual já está na última versão? Compara pelo JSON, que é como o retrato volta do banco.
  def estado_atual_guardado?
    return true if instruction.blank?

    ultima = ultima_versao
    ultima.present? && ultima.instruction_hash == hash_da_instrucao &&
      ultima.metadata.to_h['agente'] == retrato_da_versao.as_json
  end

  def versao_completa?
    instruction_versions.where("metadata ? 'agente'").exists?
  end

  def atributos_da_versao(version)
    agente = version.metadata.to_h['agente']
    return { instruction: version.instruction } if agente.nil?
    return retrato_invalido(version) unless Autonomia::Agents::RetratoDaVersao.valido?(agente)

    agente.slice(*CAMPOS).merge('instruction' => version.instruction,
                                'config' => config.to_h.merge(agente['config'].slice(*CHAVES_DA_CONFIG)))
  end

  # Retrato que não passa na conferência (chave estranha, tipo errado, tipo de agente fora da lista): volta
  # só a instrução, que tem coluna própria e validada, e registra — só ids, nunca conteúdo.
  def retrato_invalido(version)
    Rails.logger.warn("[autonomia][agents] retrato invalido na volta agente=#{id} versao=#{version.id}")
    { instruction: version.instruction }
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
