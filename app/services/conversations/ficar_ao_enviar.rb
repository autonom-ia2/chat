# #2067: "ficar com a conversa ao enviar", o ícone ao lado do Enviar no painel (caixa de resposta e gaveta "Enviar
# mensagem"). Decisões do Rodrigo (21 e 22/10):
# - "Ao enviar" é ao clicar em Enviar: a mensagem gravada. Se o provedor recusar depois, a conversa continua com quem
#   tentou (Message#claim_conversation_for_person roda depois de gravar, não depois do provedor aceitar).
# - Liga e desliga por conta (flag `ficar_com_a_conversa_ao_enviar`). Desligada, o pedido do envio é ignorado e vale a
#   regra de antes (#1499).
# - O envio leva o dono que a tela viu (`ficar_com_a_conversa_de`). Sob a trava da conversa, o servidor só atribui se
#   o dono ainda é esse: com a tela desatualizada (um colega pegou a conversa enquanto a pessoa escrevia), quem envia não
#   toma a conversa do colega sem querer. "Sem ninguém" e "com a IA" valem como a mesma situação (o ícone vem ligado nas
#   duas): a IA que passou a conversa a ninguém, ou outro robô que pegou, não muda a vontade de quem envia.
#
#   Conversations::FicarAoEnviar.pedido(account, params) -> Pedido | nil (nil: o pedido não disse, ou a flag desligada)
#   Conversations::FicarAoEnviar.dono(conversation)       -> { tipo: 'ninguem' | 'ia' | 'pessoa', id: }
module Conversations::FicarAoEnviar
  FLAG = 'ficar_com_a_conversa_ao_enviar'.freeze
  TIPOS = %w[ninguem ia pessoa].freeze
  # Ninguém e IA são a mesma situação para quem envia: o ícone vem ligado nas duas.
  LIVRES = %w[ninguem ia].freeze
  # Só estes valores dizem o ícone (JSON ou formulário); qualquer outro é como se o pedido não dissesse.
  BOOLEANOS = { true => true, false => false, 'true' => true, 'false' => false, '1' => true, '0' => false }.freeze

  # fica: o ícone ligado (true) ou desligado (false). visto: o dono que a tela viu ({ tipo:, id: }), ou nil se o pedido
  # não disse (cliente antigo da API): aí só fica se a conversa estiver sem ninguém ou com a IA.
  Pedido = Struct.new(:fica, :visto, keyword_init: true) do
    def fica? = fica
  end

  module_function

  def ligado?(account)
    account.present? && account.feature_enabled?(FLAG)
  end

  def pedido(account, params)
    return unless ligado?(account)

    fica = BOOLEANOS[params[:ficar_com_a_conversa]]
    return if fica.nil?

    Pedido.new(fica: fica, visto: visto(params[:ficar_com_a_conversa_de]))
  end

  # O dono que a tela viu, do formulário ou do JSON. Só um objeto ({ tipo:, id: }); texto, número, lista ou tipo fora da
  # lista: como se não tivesse dito (a mensagem sai do mesmo jeito, nunca 422 por isso).
  def visto(dado)
    return unless dado.is_a?(Hash) || dado.is_a?(ActionController::Parameters)

    tipo = dado[:tipo].to_s
    return unless TIPOS.include?(tipo)

    { tipo: tipo, id: tipo == 'pessoa' ? dado[:id].to_s.to_i : nil }
  end

  # O dono como a tela o mostra (Conversation#assignee_type): a IA primeiro, depois a pessoa.
  def dono(conversation)
    return { tipo: 'ia', id: nil } if conversation.ai_assignee_type.present?
    return { tipo: 'pessoa', id: conversation.assignee_id } if conversation.assignee_id.present?

    { tipo: 'ninguem', id: nil }
  end

  # Na linha travada: o dono de agora ainda é o que a tela viu. Sem o que a tela viu, só sem ninguém ou com a IA.
  def mesmo_dono?(visto, conversation)
    atual = dono(conversation)
    return LIVRES.include?(atual[:tipo]) if visto.nil? || LIVRES.include?(visto[:tipo])

    atual == visto
  end
end
