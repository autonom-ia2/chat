# Os focos de queimada do INPE dos últimos dias (#2858, F5).
# Só leitura pela geração que vale (`vigente`); quem grava é a importação.
class Autonomia::FerramentasProntas::Bases::FocoDeQueimada < ApplicationRecord
  include Autonomia::FerramentasProntas::Bases::Vigente

  self.table_name = 'autonomia_prontas_focos_queimada'
  BASE = 'queimadas'.freeze
end
