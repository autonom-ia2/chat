# As chaves da PARIDADE DA CONVERSA (#3211): quatro opções por agente, em `agent.config` (jsonb, chaves string), que dão
# ao agente nativo o ritmo de conversa do fluxo externo. TODAS nascem desligadas: sem a chave, o comportamento é o de
# hoje, byte a byte. Quem liga é o `Contratar` (PR seguinte); aqui só se lê.
#
# - `conversa_espera_a_fala` (P1): a espera da rajada é o fim previsto da fala anterior, não a janela fixa do debounce.
# - `conversa_em_fila` (P2): o turno novo espera o turno em curso (IA ou pedaços) em vez de falar por cima.
# - `conversa_entrega_inteira` (P3): mensagem nova não corta os pedaços que faltam. Só vale com a fila (P2): sem ela, o
#   turno novo falaria por cima do que ainda está saindo. Por isso `entrega_inteira?` exige as duas chaves.
# - `conversa_ritmo_do_canal` (P5): pausas e "digitando" por canal.
#
# Valor lido com ActiveModel::Type::Boolean: 'false' e '0' são desligado. Agente nil, sem `config` ou com `config` que
# não é Hash: desligado.
module Autonomia::Agents::ParidadeDaConversa
  BOOLEAN = ActiveModel::Type::Boolean.new
  ESPERA_A_FALA = 'conversa_espera_a_fala'.freeze
  EM_FILA = 'conversa_em_fila'.freeze
  ENTREGA_INTEIRA = 'conversa_entrega_inteira'.freeze
  RITMO_DO_CANAL = 'conversa_ritmo_do_canal'.freeze
  CHAVES = [ESPERA_A_FALA, EM_FILA, ENTREGA_INTEIRA, RITMO_DO_CANAL].freeze

  module_function

  def espera_a_fala?(agent) = ligada?(agent, ESPERA_A_FALA)

  def em_fila?(agent) = ligada?(agent, EM_FILA)

  def entrega_inteira?(agent) = ligada?(agent, ENTREGA_INTEIRA) && em_fila?(agent)

  def ritmo_do_canal?(agent) = ligada?(agent, RITMO_DO_CANAL)

  def ligada?(agent, chave)
    return false unless agent.respond_to?(:config)

    config = agent.config
    return false unless config.is_a?(Hash)

    BOOLEAN.cast(config[chave]) || false
  end
  private_class_method :ligada?
end
