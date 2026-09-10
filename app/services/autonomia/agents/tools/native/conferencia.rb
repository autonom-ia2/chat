# O QUE UMA CONFERÊNCIA RECUSADA DEVOLVE: o texto para o modelo E a lista do que faltou.
#
# `Native::Base#precheck` devolvia só o texto, e o registro de recusa (entrega 6) não tinha como
# dizer O QUE faltava — que é metade do que se quer saber quando uma cotação não abre. O texto
# continua sendo o que o modelo lê (`to_s`); `faltando` são NOMES de campo, nunca valores, e vão
# para o registro; `motivo` é o código do catálogo `Tools::Recusa::MOTIVOS`.
#
# Uma ferramenta que só tem a frase pode continuar devolvendo String: o `Bound` aceita as duas.
class Autonomia::Agents::Tools::Native::Conferencia
  attr_reader :texto, :faltando, :motivo

  def initialize(texto:, faltando: [], motivo: 'conferencia_recusou')
    @texto = texto.to_s
    @faltando = Array(faltando).map(&:to_s)
    @motivo = motivo.to_s
  end

  def to_s
    texto
  end
end
