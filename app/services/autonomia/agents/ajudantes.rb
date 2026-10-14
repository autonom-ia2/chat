# Tema 14 (#1434) — o AJUDANTE: um agente interno da conta que outro agente consulta e que nunca fala com o cliente.
#
# Aprende com a Cotação e simplifica: o vínculo é o `Specialist` com `delegate_agent_id`, a consulta é o MESMO
# `Specialists::Runner` (ciclo próprio, sempre texto, teto de rodadas), e os limites são constantes — sem orçamento que
# desce em cadeia e sem configuração por conta nesta fase. Profundidade 1: ajudante não chama ajudante.
#
# - `definir!`: o ESCRITOR ÚNICO do vínculo. Troca o conjunto de principais de um ajudante, com um "quando chamar" só.
# - `disponivel?`: o vínculo entra no turno? Fase 2 ligada, ajudante ligado, interno, da mesma conta.
# - `rodadas`: o principal com ajudante disponível ganha 6 rodadas e 15 minutos (a mesma decisão da Lia); sem ajudante,
#   nil, e vale o padrão de quem chama. A Lia nunca tem ajudante, então segue com `QuoteAgent::Builder.rodadas_do_turno`.
# - `recusar_por_limite`: passou do teto de consultas ou do prazo, a consulta não roda e o modelo lê
#   "limite atingido, responda com o que tem" — o cliente sempre recebe resposta.
module Autonomia::Agents::Ajudantes
  class Recusado < StandardError; end

  RODADAS_DO_PRINCIPAL = 6
  CONSULTAS_POR_RESPOSTA = 6
  PRAZO_DA_RESPOSTA = 900
  PRAZO_DA_CONSULTA = 300
  # Espera de UMA chamada ao modelo dentro da consulta (o cliente repete até 2 vezes). Menor que os 180 s da Cotação:
  # é o que segura o pior caso de uma consulta que começa perto do fim do prazo da resposta.
  SEGUNDOS_POR_CHAMADA = 90
  LIMITE_ATINGIDO = 'Limite de consultas ao ajudante atingido nesta resposta. ' \
                    'Responda ao cliente com o que você já tem.'.freeze

  module_function

  # -> os vínculos gravados. Recusado (com a mensagem para a tela) quando a lista está vazia, o ajudante não é interno,
  # ou algum principal não serve (outra conta, a Lia, outro ajudante). Nada é gravado pela metade.
  def definir!(ajudante:, principal_ids:, quando:)
    ids = ids_de_principais(principal_ids)
    raise Recusado, I18n.t('autonomia.agents.ajudante.ajudante_interno') unless ajudante.actuation_internal?

    ActiveRecord::Base.transaction do
      ajudante.lock!
      principais = principais_da_conta(ajudante, ids)
      ajudante.vinculos_de_ajudante.where.not(autonomia_agent_id: ids).delete_all
      principais.map { |principal| gravar_vinculo!(principal, ajudante, quando) }
    end
  rescue ActiveRecord::RecordInvalid => e
    raise Recusado, e.record.errors.full_messages.to_sentence
  end

  # A conta que vale é a do PRINCIPAL (`vinculo.agent`), nunca a coluna do vínculo: uma linha gravada fora do escritor
  # único não faz um ajudante de outra conta entrar no turno.
  def disponivel?(vinculo)
    principal = vinculo.agent
    return false unless vinculo.delegado? && principal.present? && ::Autonomia::Agents::Fase2.ligada?(principal.account)
    return false if principal.actuation_internal?

    ajudante_pronto?(vinculo.delegate, principal.account_id)
  end

  # Ligado, interno, com instrução e da mesma conta do principal.
  def ajudante_pronto?(ajudante, account_id)
    ajudante.present? && ajudante.account_id == account_id && ajudante.operating? && ajudante.actuation_internal? &&
      ajudante.instruction.present?
  end

  def rodadas(agent)
    return nil if agent.blank? || !::Autonomia::Agents::Fase2.ligada?(agent.account)
    return nil unless agent.specialists.enabled.de_ajudante.includes(:delegate).any? { |vinculo| disponivel?(vinculo) }

    { max_rodadas: RODADAS_DO_PRINCIPAL, max_segundos: PRAZO_DA_RESPOSTA }
  end

  # A consulta que não roda: a recusa registrada (o portão do #1361 não a toma por dado), o evento no ajudante e o texto
  # que o modelo lê. `limite` é 'consultas' ou 'prazo'.
  def recusar_por_limite(vinculo:, limite:, delivery:)
    conversa = ::Autonomia::Agents::Tools::Recusa.conversa_de(delivery)
    ::Autonomia::Agents::Tools::Recusa.registrar('ajudante_limite_atingido', slug: vinculo.function_name, agente: vinculo.agent, conversa: conversa)
    registrar_evento(vinculo: vinculo, tipo: :consult_failed, delivery: delivery, metadata: { motivo: 'limite', limite: limite })
    LIMITE_ATINGIDO
  end

  # O evento fica no AJUDANTE, com quem o consultou. Só metadados (ids, tempo, custo, motivo), nunca texto. Telemetria
  # não derruba a consulta.
  def registrar_evento(vinculo:, tipo:, delivery:, metadata:)
    ::Autonomia::Agents::AgentEvent.create!(
      account_id: vinculo.account_id, autonomia_agent_id: vinculo.delegate_agent_id, event_type: tipo,
      conversation_id: delivery&.conversation&.id, metadata: { principal_id: vinculo.autonomia_agent_id }.merge(metadata)
    )
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][ajudante] evento falhou vinculo=#{vinculo.id} #{e.class}")
    nil
  end

  # Só inteiros (ou texto de inteiro). Objeto, texto qualquer ou lista vazia: Recusado, nunca erro do banco.
  def ids_de_principais(principal_ids)
    ids = Array(principal_ids).map { |id| Integer(id.to_s, 10, exception: false) }.uniq
    raise Recusado, I18n.t('autonomia.agents.ajudante.principal_invalido') if ids.include?(nil)
    raise Recusado, I18n.t('autonomia.agents.ajudante.sem_principal') if ids.empty?

    ids
  end

  def principais_da_conta(ajudante, ids)
    principais = ::Autonomia::Agents::Agent.kept.where(account_id: ajudante.account_id, id: ids).order(:id).lock.to_a
    raise Recusado, I18n.t('autonomia.agents.ajudante.outra_conta') if principais.size != ids.size

    principais
  end

  def gravar_vinculo!(principal, ajudante, quando)
    vinculo = principal.specialists.find_or_initialize_by(delegate_agent_id: ajudante.id)
    vinculo.assign_attributes(name: ajudante.name, description: quando.to_s.strip, enabled: true)
    vinculo.slug = slug_livre(principal, ajudante, vinculo) if vinculo.new_record?
    vinculo.save!
    vinculo
  end

  # O nome do ajudante vira a função (`consultar_<slug>`); outro especialista do principal com o mesmo nome ganha o id
  # do ajudante no fim, para as duas funções não colidirem.
  def slug_livre(principal, ajudante, vinculo)
    base = ajudante.name.to_s.parameterize(separator: '_').presence || 'ajudante'
    base = "ajudante_#{base}" unless base.first.between?('a', 'z')
    base = base[0, ::Autonomia::Agents::Specialist::MAX_SLUG_LENGTH]
    return base unless principal.specialists.where.not(id: vinculo.id).exists?(slug: base)

    sufixo = "_#{ajudante.id}"
    "#{base[0, ::Autonomia::Agents::Specialist::MAX_SLUG_LENGTH - sufixo.length]}#{sufixo}"
  end
  private_class_method :ajudante_pronto?, :ids_de_principais, :principais_da_conta, :gravar_vinculo!, :slug_livre
end
