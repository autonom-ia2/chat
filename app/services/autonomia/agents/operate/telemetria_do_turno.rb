# "Um turno, uma ordem" (#1606, ponto 5): a linha de log de cada decisão sobre quem responde o turno. No formato do
# `registrar_silencio` do Responder: só ids, rótulos de lista fechada e milissegundos. Nunca texto do cliente nem do
# modelo — por isso o evento precisa estar em EVENTOS e cada valor tem de ser número, símbolo ou rótulo curto sem espaço.
module Autonomia::Agents::Operate::TelemetriaDoTurno
  EVENTOS = %w[assunto_esperou assunto_atrasou turno_reenfileirado reenfileiramento_barrado turno_em_curso claim_barrado
               devolucao passagem passagem_recusada turno_da_passagem sinal_na_passagem
               turno_da_passagem_descartado turno_da_passagem_rodou link_recusado opcao_tocada
               localizacao_recebida cartao_nao_enviado cartao_descartado interacao_nao_enviada].freeze

  module_function

  def registrar(evento, conversation_id:, **campos)
    raise ArgumentError, "evento fora da lista: #{evento}" unless EVENTOS.include?(evento.to_s)

    pares = campos.compact.map { |chave, valor| "#{chave}=#{valor_seguro(valor)}" }
    Rails.logger.info(['[autonomia][turno]', evento, "conv=#{conversation_id}", *pares].join(' '))
  end

  # Número passa como está; o resto vira rótulo e só passa se for curto e sem espaço (um id, um símbolo da lista).
  def valor_seguro(valor)
    return valor if valor.is_a?(Numeric)

    rotulo = valor.to_s
    rotulo.length <= 40 && rotulo.exclude?(' ') && rotulo.exclude?("\n") ? rotulo : 'descartado'
  end
  private_class_method :valor_seguro
end
