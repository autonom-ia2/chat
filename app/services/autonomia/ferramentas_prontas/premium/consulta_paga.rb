# UMA CONSULTA DE UM CARD PREMIUM (#2858, F7): uma consulta do catálogo que é um dataset da BigDataCorp. Uma fonte só,
# sem reserva (`BigDataCorp`), e o prazo do dataset. A validade de 1 dia é só a marca de que passa pelo cache: o
# `Premium::Cache` guarda até o fim do dia da conta.
class Autonomia::FerramentasProntas::Premium::ConsultaPaga < Autonomia::FerramentasProntas::Consulta
  FOLGA = 2

  attr_reader :dataset

  def initialize(nome:, descricao:, dataset:, obrigatorios:)
    @dataset = dataset
    super(nome: nome, descricao: descricao, obrigatorios: obrigatorios, provedores: [Autonomia::FerramentasProntas::Premium::BigDataCorp],
          validade: 1.day, prazo_por_fonte: dataset.prazo, prazo_total: dataset.prazo + FOLGA)
  end

  def paga?
    true
  end
end
