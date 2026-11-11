# Relógio virtual do teste de estresse: o tempo só anda para a frente, de segundo em segundo, para que as esperas do
# sistema (15 s do assunto, 15 s da avaliação, dias entre mensagens) aconteçam sem esperar de verdade. As chamadas de IA
# continuam reais; só o Time.current é deslocado.
require 'active_support/testing/time_helpers'

class Stress::Relogio
  include ActiveSupport::Testing::TimeHelpers

  attr_reader :agora

  def initialize(inicio)
    @agora = inicio.change(usec: 0)
    travel_to(@agora)
  end

  def avancar(segundos)
    ir_para(@agora + segundos.to_i.seconds)
  end

  def ir_para(momento)
    alvo = Time.zone.at(momento.to_f.ceil)
    return @agora if alvo <= @agora

    @agora = alvo
    travel_to(@agora)
    @agora
  end

  def soltar
    travel_back
  end
end
