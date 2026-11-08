# O MAPA E O CARTÃO DE CONTATO DO TURNO SAEM AQUI (#1479 F3), depois que a mensagem âncora saiu para o canal
# (`Operate::CartoesDoTurno`: o que a âncora grava e quem enfileira). Fora do lock do texto: erro num cartão nunca
# desfaz nem atrasa a resposta.
#
# Por cartão ainda não postado, na ordem gravada, conferindo a mensagem que ele espera (a âncora, ou o cartão anterior,
# para dois cartões não trocarem de ordem no canal) pela regra de `Operate::SaidaDaMensagem`:
#   - falhou: o cartão NÃO sai (um mapa sem o texto confunde). Registro `cartao_nao_enviado` motivo=anterior_falhou;
#   - pendente: reagenda a si mesmo em ESPERA, até TETO contado do `created_at` dela. Passado o teto, desiste com
#     `cartao_nao_enviado` motivo=anterior_pendente. Nunca reenfileira para sempre;
#   - saiu: posta (idempotente pelo token) e segue para o próximo. Sob o lock, nada sai se uma pessoa da equipe escreveu
#     depois da âncora (motivo=pessoa_respondeu) ou se a conta foi desligada (motivo=desligado);
#   - a anterior sumiu da conversa: para, sem postar.
# Dois jobs da mesma âncora (o do Responder e o do retry "já respondido") não duplicam: o token é conferido sob lock.
# Erro ao postar: o log leva só os ids e a classe, o erro vai ao tracker, `cartao_nao_enviado` motivo=erro_ao_postar, e o
# job para sem relançar (o texto já saiu).
# TODA DESISTÊNCIA FICA GRAVADA NA ÂNCORA (`CartoesDoTurno#encerrar!`), e a âncora encerrada é pulada: um retry tardio
# nunca manda o cartão horas depois.
class Autonomia::Agents::Operate::EnviarCartoesJob < ApplicationJob
  ESPERA = 3.seconds
  TETO = 60.seconds

  # MEDIUM, junto do `ChunkedDeliveryJob` e do `ReplyJob`: é a mesma resposta ao cliente.
  queue_as :medium

  def perform(ancora_id)
    ancora = Message.find_by(id: ancora_id)
    return if ancora.nil?

    @ancora = ancora
    @cartoes = ::Autonomia::Agents::Operate::CartoesDoTurno.new(ancora)
    return if @cartoes.cartoes.empty? || @cartoes.encerrado?

    @cartoes.cartoes.each do |cartao|
      next if @cartoes.postado?(cartao)
      break unless postar?(cartao)
    end
  end

  private

  # -> true quando o cartão saiu e o próximo pode seguir; senão registra, encerra ou reagenda e devolve false.
  def postar?(cartao)
    anterior = @cartoes.anterior_de(cartao)
    return false if anterior.nil?

    case ::Autonomia::Agents::Operate::SaidaDaMensagem.estado(anterior)
    when :saiu then postado_sem_erro?(cartao)
    when :falhou then nao_enviado('anterior_falhou')
    else esperar(anterior)
    end
  end

  def esperar(anterior)
    return nao_enviado('anterior_pendente') if anterior.created_at <= TETO.ago

    self.class.set(wait: ESPERA).perform_later(@ancora.id)
    false
  end

  # Registra e grava a desistência na âncora. -> false.
  def nao_enviado(motivo)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:cartao_nao_enviado, conversation_id: @ancora.conversation_id,
                                                                                   msg: @ancora.id, motivo: motivo)
    @cartoes.encerrar!(motivo)
    false
  end

  def postado_sem_erro?(cartao)
    motivo = @cartoes.postar!(cartao)
    motivo ? nao_enviado(motivo) : true
  rescue StandardError => e
    Rails.logger.warn("[autonomia][operate] cartao_falhou conv=#{@ancora.conversation_id} msg=#{@ancora.id} erro=#{e.class.name}")
    ChatwootExceptionTracker.new(e, account: @ancora.account).capture_exception
    nao_enviado('erro_ao_postar')
  end
end
