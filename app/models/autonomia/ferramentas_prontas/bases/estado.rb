# O ESTADO DE CADA BASE BAIXADA (#2858, F5): uma linha por base (`planos_de_saude`, `aeronaves`...). `geracao_ativa` é a
# geração que a busca lê; `atualizado_em` é quando ela entrou (o "atualizado em…" do cartão); `linhas`, quantas linhas
# ela tem (a importação seguinte que vier muito menor é recusada). A falha fica em `falhou_em` e `motivo_da_falha`
# (um motivo curto do código), sem apagar a geração que vale.
class Autonomia::FerramentasProntas::Bases::Estado < ApplicationRecord
  self.table_name = 'autonomia_prontas_bases'

  validates :base, presence: true, uniqueness: true

  def self.de(base)
    find_or_create_by!(base: base.to_s)
  rescue ActiveRecord::RecordNotUnique
    find_by!(base: base.to_s)
  end

  # base => atualizado_em, das bases que já têm dado.
  def self.atualizacoes
    where.not(geracao_ativa: nil).pluck(:base, :atualizado_em).to_h
  end
end
