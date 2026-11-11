# As aeronaves do Registro Aeronáutico Brasileiro (ANAC); `dados` já vem enxuto, sem pessoa física (#2858, F5).
# Só leitura pela geração que vale (`vigente`); quem grava é a importação.
class Autonomia::FerramentasProntas::Bases::Aeronave < ApplicationRecord
  include Autonomia::FerramentasProntas::Bases::Vigente

  self.table_name = 'autonomia_prontas_aeronaves'
  BASE = 'aeronaves'.freeze
end
