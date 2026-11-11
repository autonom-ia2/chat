# As operadoras de plano de saúde da ANS, ativas e canceladas (#2858, F5).
# Só leitura pela geração que vale (`vigente`); quem grava é a importação.
class Autonomia::FerramentasProntas::Bases::Operadora < ApplicationRecord
  include Autonomia::FerramentasProntas::Bases::Vigente

  self.table_name = 'autonomia_prontas_operadoras_ans'
  BASE = 'planos_de_saude'.freeze
end
