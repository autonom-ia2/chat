# O QUE FALTA num pedido a uma ferramenta pronta (#2858, regra "QI 70" do Rodrigo, 11/11/2026): o parâmetro que não
# serve (`campo`), as opções que a plataforma achou quando o dado é ambíguo (`candidatos`: as UFs de uma cidade com nome
# repetido, os modelos que começam com "Gol") e, quando a regra da consulta sabe mais que o parâmetro, a orientação dela.
# Sem orientação aqui, vale a do parâmetro (`Parametro#orientacao`); sem nenhuma, o texto genérico (`Resposta`).
Autonomia::FerramentasProntas::Falta = Data.define(:campo, :candidatos, :orientacao) do
  def initialize(campo:, candidatos: nil, orientacao: nil)
    super
  end

  # A regra da consulta devolve o nome do campo (o caso comum) ou uma Falta pronta.
  def self.de(valor)
    valor.is_a?(self) ? valor : new(campo: valor.to_s)
  end

  def to_s
    campo
  end
end
