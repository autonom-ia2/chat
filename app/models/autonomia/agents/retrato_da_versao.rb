# #1428 — confere o retrato do agente guardado numa versão antes de voltar a ele. A volta grava com
# update_columns (sem validação do model), então o retrato precisa ter só chaves conhecidas, com o tipo
# certo, e um tipo de agente válido. O de cotação fica fora: o tipo dele é fixo e ninguém entra nele.
module Autonomia::Agents::RetratoDaVersao
  VERSIONING = Autonomia::Agents::AgentVersioning
  TEXTOS = %w[scaffold tone handoff_rule greeting fallback_message human_card].freeze
  CONHECIDAS = (VERSIONING::CAMPOS + VERSIONING::SO_PARA_COMPARAR + %w[config]).freeze
  OBRIGATORIAS = (VERSIONING::CAMPOS + %w[config]).freeze
  WITH_KNOWLEDGE = [nil, true, false, 'true', 'false'].freeze
  BASE = %w[segmento versao texto].freeze
  # Teto do texto do bloco guardado na marca (bytes). O bloco é orientação curta do ramo; 8 KB sobra.
  TEXTO_DA_BASE_MAX = 8.kilobytes

  module_function

  def valido?(agente)
    agente.is_a?(Hash) && chaves_validas?(agente) && campos_validos?(agente) && config_valida?(agente['config'])
  end

  def chaves_validas?(agente)
    (agente.keys - CONHECIDAS).empty? && (OBRIGATORIAS - agente.keys).empty?
  end

  def campos_validos?(agente)
    agente['name'].is_a?(String) && agente['name'].present? &&
      tipo_valido?(agente['agent_type']) &&
      Autonomia::Agents::Agent.modes.key?(agente['mode']) &&
      lista_de_textos?(agente['starter_questions']) &&
      TEXTOS.all? { |campo| texto_ou_nada?(agente[campo]) }
  end

  def tipo_valido?(tipo)
    Autonomia::Agents::Agent::AGENT_TYPES.include?(tipo) && tipo != 'insurance_quote'
  end

  def config_valida?(config)
    config.is_a?(Hash) && (config.keys - VERSIONING::CHAVES_DA_CONFIG).empty? &&
      (config['guardrails'].nil? || lista_de_textos?(config['guardrails'])) &&
      texto_ou_nada?(config['voice']) && WITH_KNOWLEDGE.include?(config['with_knowledge']) && base_valida?(config['base'])
  end

  # A marca de base (#1429): ausente (versões de antes dela) ou { segmento, versao, texto }, cada um texto ou nil; o texto
  # até TEXTO_DA_BASE_MAX.
  def base_valida?(base)
    return true if base.nil?

    base.is_a?(Hash) && (base.keys - BASE).empty? && BASE.all? { |chave| texto_ou_nada?(base[chave]) } &&
      base['texto'].to_s.bytesize <= TEXTO_DA_BASE_MAX
  end

  def lista_de_textos?(valor)
    valor.is_a?(Array) && valor.all?(String)
  end

  def texto_ou_nada?(valor)
    valor.nil? || valor.is_a?(String)
  end
end
