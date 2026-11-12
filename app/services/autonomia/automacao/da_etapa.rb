# "Automações desta etapa" (#2499 F6.5): as automações do motor novo cujo gatilho é nesta etapa. Os gatilhos com o
# parâmetro `etapa_id` (entrou, saiu, parado: Gatilhos::LISTA) e a etapa escolhida nele, na versão ativa. Ligadas e
# desligadas: a tela mostra o interruptor de cada uma. As regras antigas da etapa (Crm::StageAutomation) vêm da API
# delas, com o selo "Jeito antigo".
module Autonomia::Automacao::DaEtapa
  RECEITA = 'autonomia_automacao_versoes.receita'.freeze

  module_function

  def tipos = ::Autonomia::Automacao::Gatilhos::LISTA.values.select { |entrada| entrada.parametros.include?('etapa_id') }.map(&:tipo)

  def de(etapa)
    ::Autonomia::Automacao::Definicao.where(account_id: etapa.account_id)
                                     .joins(:versao_ativa).includes(:versao_ativa)
                                     .where("#{RECEITA} -> 'gatilho' ->> 'tipo' IN (?)", tipos)
                                     .where("#{RECEITA} -> 'gatilho' ->> 'etapa_id' = ?", etapa.id.to_s)
                                     .order(:id)
  end
end
