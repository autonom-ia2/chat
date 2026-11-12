# Os campos de um seguro que a tela corrige (E4, #2897) e a coluna de cada um na apólice. Os nomes da tela são os que a
# história (`mudancas`) e `corrigido_a_mao` guardam; os valores ficam na forma do banco, sem depender de formato de
# tela: o valor em centavos e a data como AAAA-MM-DD. Quem desfaz repõe a coluna com o que está guardado.
module Carteira::Campos
  COLUNAS = {
    'tipo' => :tipo, 'seguradora' => :seguradora, 'numero' => :numero, 'comeca' => :inicio_vigencia,
    'termina' => :fim_vigencia, 'valor' => :valor_centavos, 'bem' => :bem
  }.freeze
  VALOR = 'valor'.freeze
  CENTAVOS_POR_REAL = 100

  module_function

  # O valor de uma coluna como a história guarda.
  def guardado(valor)
    valor.is_a?(Date) ? valor.iso8601 : valor
  end

  def em_reais(centavos)
    centavos && (centavos.to_f / CENTAVOS_POR_REAL)
  end
end
