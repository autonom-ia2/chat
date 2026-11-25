# As chaves da PARIDADE DA CONVERSA (#3211): quatro opções por agente, em `agent.config` (jsonb, chaves string), que dão
# ao agente nativo o ritmo de conversa do fluxo externo. Decisão do Rodrigo (25/11): valem para TODO agente nativo. Sem a
# chave, a opção está LIGADA; a Lia (`insurance_quote`) é a exceção, e nela a chave ausente é DESLIGADA (regra da casa:
# o comportamento da Lia não muda). Nada é gravado no banco: o padrão mora aqui.
#
# - `conversa_espera_a_fala` (P1): a espera da rajada é o fim previsto da fala anterior, não a janela fixa do debounce.
# - `conversa_em_fila` (P2): o turno novo espera o turno em curso (IA ou pedaços) em vez de falar por cima.
# - `conversa_entrega_inteira` (P3): mensagem nova não corta os pedaços que faltam. Só vale com a fila (P2): sem ela, o
#   turno novo falaria por cima do que ainda está saindo. Por isso `entrega_inteira?` exige as duas efetivas.
# - `conversa_ritmo_do_canal` (P5): pausas e "digitando" por canal.
#
# Valor explícito manda, em qualquer agente (inclusive na Lia), lido com ActiveModel::Type::Boolean: `false`, 'false' e
# '0' desligam; `true` e 'true' ligam; valor que não converte (ex.: '') desliga. Só a chave ausente ou nula segue o padrão
# do tipo. Agente de verdade com `config` nil ou que não é Hash também segue o padrão do tipo. O que não é
# Autonomia::Agents::Agent (nil, vínculo sem agente, dublê de teste) fica DESLIGADO: não há agente para ligar.
#
# KILL-SWITCH da instalação: ENV `AI_AGENT_CONVERSA_PADRAO_LIGADO` (ausente ou `true` = o padrão acima). Com `false`, a
# chave ausente passa a ser DESLIGADA em todo agente (o comportamento do #3213), no próximo turno, sem deploy e sem
# gravar no banco. Valor gravado no agente continua mandando; a Lia segue desligada sem a chave.
module Autonomia::Agents::ParidadeDaConversa
  BOOLEAN = ActiveModel::Type::Boolean.new
  ESPERA_A_FALA = 'conversa_espera_a_fala'.freeze
  EM_FILA = 'conversa_em_fila'.freeze
  ENTREGA_INTEIRA = 'conversa_entrega_inteira'.freeze
  RITMO_DO_CANAL = 'conversa_ritmo_do_canal'.freeze
  CHAVES = [ESPERA_A_FALA, EM_FILA, ENTREGA_INTEIRA, RITMO_DO_CANAL].freeze
  # A Lia: sem a chave, desligada.
  TIPO_DESLIGADO_POR_PADRAO = 'insurance_quote'.freeze

  module_function

  def espera_a_fala?(agent) = ligada?(agent, ESPERA_A_FALA)

  def em_fila?(agent) = ligada?(agent, EM_FILA)

  def entrega_inteira?(agent) = ligada?(agent, ENTREGA_INTEIRA) && em_fila?(agent)

  def ritmo_do_canal?(agent) = ligada?(agent, RITMO_DO_CANAL)

  def ligada?(agent, chave)
    return false unless agent.is_a?(::Autonomia::Agents::Agent)

    valor = agent.config.is_a?(Hash) ? agent.config[chave] : nil
    return padrao(agent) if valor.nil?

    BOOLEAN.cast(valor) || false
  end
  private_class_method :ligada?

  def padrao(agent) = padrao_ligado? && agent.agent_type != TIPO_DESLIGADO_POR_PADRAO
  private_class_method :padrao

  def padrao_ligado?
    BOOLEAN.cast(ENV.fetch('AI_AGENT_CONVERSA_PADRAO_LIGADO', true))
  end
end
