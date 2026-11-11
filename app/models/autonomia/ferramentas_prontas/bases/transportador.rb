# Os transportadores do RNTRC (ANTT); do autônomo, nem nome nem CPF (#2858, F5).
# Só leitura pela geração que vale (`vigente`); quem grava é a importação.
class Autonomia::FerramentasProntas::Bases::Transportador < ApplicationRecord
  include Autonomia::FerramentasProntas::Bases::Vigente

  self.table_name = 'autonomia_prontas_transportadores'
  BASE = 'transportadoras'.freeze
end
