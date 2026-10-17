# #1428 — A VERSÃO GUARDA O AGENTE INTEIRO. Até aqui a versão guardava só a instrução, e o Construtor não
# gravava versão nenhuma: em 13/10 (conta 16) uma pergunta virou aplicação e regravou o agente sem rastro
# nem caminho de volta. Agora toda versão leva, em `metadata['agente']`, os campos que o Construtor e a
# edição mudam; voltar a ela devolve todos. A instrução continua na coluna própria da versão.
#
# `reason` diz a origem: builder_create / builder_adjust (Construtor), base (o estado de antes da primeira
# aplicação com versão completa), antes_de_voltar (o estado de antes de uma volta, quando não estava em
# versão nenhuma), manual_edit, kb_refresh e rollback (nomes que já estão no banco).
#
# O que é oculto não sai pela API: o jbuilder da versão não lê o retrato, e o texto da instrução só sai quando
# foi escrito pelo dono (`InstructionVersion#instrucao_visivel?`, #1484). Isso vale para todas as contas.
#
# SÓ NO PILOTO (Fase 2 dos Agentes, contas 1/16/18): a versão do agente inteiro, a volta que devolve todos os
# campos e a versão a cada aplicação do Construtor. Fora dele, como antes: a volta devolve só a instrução e o
# Construtor não grava versão.
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
      gravar_versao!('antes_de_voltar', created_by&.id) if versao_completa? && !estado_atual_guardado?
      atributos = atributos_da_versao(version)
      sem_andaime = atributos.delete('sem_andaime')
      update_columns(atributos.merge(updated_at: Time.current)) # rubocop:disable Rails/SkipsModelValidations
      gravar_versao!('rollback', created_by&.id, extra: { 'voltou_para' => version.id, 'sem_andaime' => sem_andaime }.compact)
    end
    true
  end

  # Os hashes das instruções que o dono escreveu à mão (as `manual_edit`): a prova de que um texto é dele.
  def hashes_escritos_pelo_dono
    instruction_versions.where(reason: 'manual_edit').distinct.pluck(:instruction_hash).to_set
  end

  # Envolve a escrita do Construtor (`apply_builder_config!`, dentro da trava do agente). Antes: se o agente
  # já tem instrução e o estado atual não está na última versão da lista (agente de antes das versões
  # completas, ou saudação editada à mão, que não gera versão), guarda-o como 'base' — o ajuste nunca
  # sobrescreve trabalho sem rastro. Depois, se a escrita venceu, grava 1 versão da aplicação — mesmo sem
  # mudança, porque é o rastro da aplicação.
  def versionar_aplicacao_do_construtor(autor_id)
    return yield unless versao_completa?

    antes = estado_versionado
    criacao = instruction.blank?
    gravar_versao!('base', nil) unless criacao || estado_atual_guardado?
    venceu = yield
    # Sem instrução não há versão (a coluna é obrigatória); a escrita do Construtor não cai por isso.
    gravar_versao_da_aplicacao!(criacao, antes, autor_id) if venceu && instruction.present?
    venceu
  end

  private

  def gravar_versao_da_aplicacao!(criacao, antes, autor_id)
    extra = estado_versionado == antes ? { 'sem_mudanca' => true } : {}
    gravar_versao!(criacao ? 'builder_create' : 'builder_adjust', autor_id, extra: extra)
  end

  # A versão do agente inteiro vale só no piloto (Fase 2 dos Agentes).
  def versao_completa?
    ::Autonomia::Agents::Fase2.ligada?(account)
  end

  def estado_versionado
    { 'instruction' => instruction.to_s, 'agente' => retrato_da_versao }
  end

  def retrato_da_versao
    atual = config.to_h
    (CAMPOS + SO_PARA_COMPARAR).index_with { |campo| self[campo] }
                               .merge('config' => CHAVES_DA_CONFIG.index_with { |chave| atual[chave] })
  end

  def ultima_versao(escopo = instruction_versions)
    escopo.order(created_at: :desc, id: :desc).first
  end

  # O estado atual já está na última versão DA LISTA? A linha `sem_mudanca` fica fora da lista: contá-la
  # deixaria uma edição à mão sem versão visível. Compara pelo JSON, que é como o retrato volta do banco.
  def estado_atual_guardado?
    return true if instruction.blank?

    ultima = ultima_versao(instruction_versions.na_lista)
    ultima.present? && ultima.instruction_hash == hash_da_instrucao &&
      ultima.metadata.to_h['agente'] == retrato_da_versao.as_json
  end

  # #1484 — instrução que não é do dono (versão guiada, antiga sem retrato, ou com retrato inválido) nunca
  # fica num agente manual, onde a API a mostraria: o agente volta guiado, e a versão 'rollback' gravada
  # depois também fica guiada, portanto oculta.
  def atributos_da_versao(version)
    atributos = atributos_guardados(version)
    return atributos if version.instrucao_visivel?(hashes_escritos_pelo_dono)

    andaime = andaime_do_construtor(version)
    return atributos.merge('mode' => 'guided', 'scaffold' => andaime) if andaime

    # Sem andaime guardado: volta assim mesmo (sem regressão) e a versão da volta registra o fato.
    Rails.logger.warn("[autonomia][agents] volta sem andaime agente=#{id} versao=#{version.id}") if manual?
    atributos.merge('mode' => 'guided', 'sem_andaime' => (manual? || nil))
  end

  # A volta que deixa o agente guiado devolve junto o andaime do Construtor guardado na versão (retrato guiado):
  # num agente manual o andaime é o genérico do modo manual (revisão adversarial do #1492). Versão sem esse
  # andaime (antiga, ou gravada em modo manual) volta assim mesmo, sem regressão para quem já voltava, e o fato fica
  # registrado: `sem_andaime` na versão da volta e um aviso no log (só ids).
  def andaime_do_construtor(version)
    agente = version.metadata.to_h['agente']
    return unless agente.is_a?(Hash) && agente['mode'] == 'guided' && Autonomia::Agents::RetratoDaVersao.valido?(agente)

    agente['scaffold'].presence
  end

  # Fora do piloto, só a instrução (como antes das versões completas).
  def atributos_guardados(version)
    return { 'instruction' => version.instruction } unless versao_completa?

    agente = version.metadata.to_h['agente']
    return { 'instruction' => version.instruction } if agente.nil?
    return retrato_invalido(version) unless Autonomia::Agents::RetratoDaVersao.valido?(agente)

    agente.slice(*CAMPOS).merge('instruction' => version.instruction,
                                'config' => config.to_h.merge(agente['config'].slice(*CHAVES_DA_CONFIG)))
  end

  # Retrato que não passa na conferência (chave estranha, tipo errado, tipo de agente fora da lista): volta
  # só a instrução, que tem coluna própria e validada, e registra — só ids, nunca conteúdo.
  def retrato_invalido(version)
    Rails.logger.warn("[autonomia][agents] retrato invalido na volta agente=#{id} versao=#{version.id}")
    { 'instruction' => version.instruction }
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
