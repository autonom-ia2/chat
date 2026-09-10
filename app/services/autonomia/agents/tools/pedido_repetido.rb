# O QUE O MODELO LÊ QUANDO O PEDIDO É O MESMO DA ÚLTIMA CONSULTA (entrega 10).
#
# Tem a forma da `Native::Conferencia` (`to_s`, `motivo`, `faltando`) porque o `Bound` a devolve
# pelo mesmo caminho: texto ao modelo, nenhuma execução aberta, e o registro de recusa (entrega 6)
# com o motivo `pedido_repetido`. O texto diz ao modelo o ESTADO da consulta que já existe — em
# andamento há quanto tempo, ou concluída com quantas entregas — e o deixa responder ao cliente com
# as próprias palavras (termo 6: resposta sobre o andamento, não silêncio, não erro).
#
# NÃO diz o que o cliente quis. Se ele mudou um dado, o pedido já não é o mesmo e nem chega aqui;
# se o modelo entendeu errado, a frase final lembra que um dado novo abre uma consulta nova.
class Autonomia::Agents::Tools::PedidoRepetido
  MOTIVO = 'pedido_repetido'.freeze

  def initialize(run, agora: Time.current)
    @run = run
    @agora = agora
  end

  def motivo
    MOTIVO
  end

  def faltando
    []
  end

  def to_s
    "Este pedido tem exatamente os mesmos dados da consulta que #{estado}. Não abri outra. " \
      'Responda ao cliente sobre o andamento com as suas palavras, sem vocabulário de sistema. ' \
      'Se ele mudou algum dado, refaça a chamada com o dado novo — dado diferente abre consulta nova.'
  end

  private

  # Só o que a linha prova: `delivered_count` conta resultados que a ferramenta ENCAMINHOU para
  # publicação — pode estar adiado pela cadeia humanizada, ou ter saído como nota privada quando há
  # atendente; não é "publicado", muito menos "o cliente leu". E `failed` com entrega é encerramento
  # sem concluir, não conclusão.
  def estado
    return "já está em andamento nesta conversa (começou há #{tempo(@run.created_at)})" if @run.running?

    "já terminou nesta conversa há #{tempo(@run.encerrada_em)} (#{desfecho}), com #{resultados}"
  end

  def desfecho
    @run.status == 'done' ? 'concluída' : 'encerrada sem concluir'
  end

  def resultados
    n = @run.delivered_count.to_i
    n == 1 ? '1 resultado encaminhado para publicação' : "#{n} resultados encaminhados para publicação"
  end

  def tempo(instante)
    minutos = ((@agora - instante) / 60).floor
    return 'menos de um minuto' if minutos < 1
    return "#{minutos} #{minutos == 1 ? 'minuto' : 'minutos'}" if minutos < 120

    horas = (minutos / 60).floor
    "#{horas} horas"
  end
end
