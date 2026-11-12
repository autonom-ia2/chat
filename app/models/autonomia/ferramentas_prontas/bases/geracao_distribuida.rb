# A geração distribuída da ANEEL, somada por CEP, município, tipo e classe (nenhum titular) (#2858, F5).
# Só leitura pela geração que vale (`vigente`); quem grava é a importação.
class Autonomia::FerramentasProntas::Bases::GeracaoDistribuida < ApplicationRecord
  include Autonomia::FerramentasProntas::Bases::Vigente

  self.table_name = 'autonomia_prontas_geracao_distribuida'
  BASE = 'geracao_solar'.freeze
end
