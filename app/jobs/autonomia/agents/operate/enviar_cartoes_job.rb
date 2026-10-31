# O MAPA E O CARTÃO DE CONTATO DO TURNO SAEM AQUI (#1479 F3), depois que a mensagem âncora saiu para o canal
# (`Operate::CartoesDoTurno`: o que a âncora grava e quem enfileira). Fora do lock do texto: erro num cartão nunca
# desfaz nem atrasa a resposta.
#
# Por cartão ainda não postado, na ordem gravada, conferindo a mensagem que ele espera (a âncora, ou o cartão anterior,
# para dois cartões não trocarem de ordem no canal) pela regra de `Operate::SaidaDaMensagem`:
#   - falhou: o cartão NÃO sai (um mapa sem o texto confunde). Registro `cartao_nao_enviado` motivo=anterior_falhou;
#   - pendente: reagenda a si mesmo em ESPERA, até TETO contado do `created_at` dela. Passado o teto, desiste com
#     `cartao_nao_enviado` motivo=anterior_pendente. Nunca reenfileira para sempre;
#   - saiu: posta (idempotente pelo token) e segue para o próximo.
# Dois jobs da mesma âncora (o do Responder e o do retry "já respondido") não duplicam: o token é conferido sob lock.
# Erro ao postar: o log leva só os ids e a classe, e o job para sem relançar (o texto já saiu).
class Autonomia::Agents::Operate::EnviarCartoesJob < ApplicationJob
  ESPERA = 3.seconds
  TETO = 60.seconds

  # MEDIUM, junto do `ChunkedDeliveryJob` e do `ReplyJob`: é a mesma resposta ao cliente.
  queue_as :medium

  def perform(ancora_id)
    ancora = Message.find_by(id: ancora_id)
    return if ancora.nil?

    cartoes = ::Autonomia::Agents::Operate::CartoesDoTurno.new(ancora)
    cartoes.cartoes.each do |cartao|
      next if cartoes.postado?(cartao)
      break unless postar?(ancora, cartoes.anterior_de(cartao))
      break unless postado_sem_erro?(ancora, cartoes, cartao)
    end
  end

  private

  # -> true quando a mensagem anterior saiu; senão registra ou reagenda e devolve false.
  def postar?(ancora, anterior)
    case ::Autonomia::Agents::Operate::SaidaDaMensagem.estado(anterior)
    when :saiu then true
    when :falhou then nao_enviado(ancora, 'anterior_falhou')
    else esperar(ancora, anterior)
    end
  end

  def esperar(ancora, anterior)
    return nao_enviado(ancora, 'anterior_pendente') if anterior.created_at <= TETO.ago

    self.class.set(wait: ESPERA).perform_later(ancora.id)
    false
  end

  def nao_enviado(ancora, motivo)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:cartao_nao_enviado, conversation_id: ancora.conversation_id,
                                                                                   msg: ancora.id, motivo: motivo)
    false
  end

  def postado_sem_erro?(ancora, cartoes, cartao)
    cartoes.postar!(cartao)
    true
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] cartao_falhou conv=#{ancora.conversation_id} msg=#{ancora.id} erro=#{e.class.name}")
    false
  end
end
