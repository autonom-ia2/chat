# O MAPA E O CARTÃO DE CONTATO DO TURNO SAEM AQUI (#1479 F3), depois que a mensagem âncora saiu para o canal
# (`Operate::CartoesDoTurno`: o que a âncora grava e quem enfileira). Fora do lock do texto: erro num cartão nunca
# desfaz nem atrasa a resposta. Na voz, ANTES dos cartões sai a interação gravada no áudio
# (`Operate::InteracaoDepoisDoAudio`), com as mesmas regras e o registro `interacao_nao_enviada`; o primeiro cartão
# espera ela sair, e a desistência dela encerra a âncora (nenhum cartão sai sem a pergunta antes).
#
# Por mensagem ainda não postada, na ordem (a interação, depois os cartões na ordem gravada), conferindo a mensagem que
# ela espera (a âncora, a interação, ou o cartão anterior, para nada trocar de ordem no canal) pela regra de
# `Operate::SaidaDaMensagem`:
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
    @ancora = Message.find_by(id: ancora_id)
    return if @ancora.nil?

    @cartoes = ::Autonomia::Agents::Operate::CartoesDoTurno.new(@ancora)
    @interacao = ::Autonomia::Agents::Operate::InteracaoDepoisDoAudio.new(@ancora)
    return if nada_a_enviar? || !interacao_postada?

    @cartoes.cartoes.each do |cartao|
      next if @cartoes.postado?(cartao)
      break unless postar?(cartao)
    end
  end

  private

  def nada_a_enviar?
    (@cartoes.cartoes.empty? && !@interacao.pendente?) || @cartoes.encerrado?
  end

  # -> true quando não há interação pendente ou ela já saiu (agora ou antes); senão registra, encerra ou reagenda e
  # devolve false.
  def interacao_postada?
    return true if !@interacao.pendente? || @interacao.postada

    @etapa = :interacao
    depois_de(@ancora) { postada_sem_erro?(@interacao.method(:postar!)) }
  ensure
    @etapa = nil
  end

  # -> true quando o cartão saiu e o próximo pode seguir; senão registra, encerra ou reagenda e devolve false.
  def postar?(cartao)
    anterior = anterior_de(cartao)
    return false if anterior.nil?

    depois_de(anterior) { postada_sem_erro?(-> { @cartoes.postar!(cartao) }) }
  end

  # O primeiro cartão espera a interação, quando o áudio a gravou; os outros, o de sempre (`CartoesDoTurno#anterior_de`).
  def anterior_de(cartao)
    anterior = @cartoes.anterior_de(cartao)
    anterior.equal?(@ancora) && @interacao.pendente? ? @interacao.postada : anterior
  end

  def depois_de(anterior)
    case ::Autonomia::Agents::Operate::SaidaDaMensagem.estado(anterior)
    when :saiu then yield
    when :falhou then nao_enviado('anterior_falhou')
    else esperar(anterior)
    end
  end

  def esperar(anterior)
    return nao_enviado('anterior_pendente') if anterior.created_at <= TETO.ago

    self.class.set(wait: ESPERA).perform_later(@ancora.id)
    false
  end

  # Registra e grava a desistência na âncora. -> false. Na etapa da interação, os cartões que viriam depois dela também
  # ficam registrados como não enviados.
  def nao_enviado(motivo)
    telemetria(:interacao_nao_enviada, motivo) if @etapa == :interacao
    telemetria(:cartao_nao_enviado, motivo) if @cartoes.cartoes.any?
    @cartoes.encerrar!(motivo)
    false
  end

  def telemetria(evento, motivo)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(evento, conversation_id: @ancora.conversation_id, msg: @ancora.id,
                                                                      motivo: motivo)
  end

  # `postar`: devolve nil quando postou, senão o motivo de não postar.
  def postada_sem_erro?(postar)
    motivo = postar.call
    motivo ? nao_enviado(motivo) : true
  rescue StandardError => e
    rotulo = @etapa == :interacao ? 'interacao_falhou' : 'cartao_falhou'
    Rails.logger.warn("[autonomia][operate] #{rotulo} conv=#{@ancora.conversation_id} msg=#{@ancora.id} erro=#{e.class.name}")
    ChatwootExceptionTracker.new(e, account: @ancora.account).capture_exception
    nao_enviado('erro_ao_postar')
  end
end
