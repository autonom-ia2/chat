# A conta da campanha da vez (#2414 G55): uma linha por automação, vez e passo de campanha num gatilho recorrente de
# card ou contato. Quem mexe é Autonomia::Automacao::CampanhaDaOcorrencia, sempre sob a trava da vez.
class Autonomia::Automacao::CampanhaDaVez < ApplicationRecord
  self.table_name = 'autonomia_automacao_campanhas_da_vez'

  belongs_to :account
  belongs_to :automacao, class_name: 'Autonomia::Automacao::Definicao'

  validates :ocorrencia, :passo, presence: true

  # Quantos a vez já contou: chegaram ao passo, saíram por outro caminho ou nem abriram execução.
  def contados = chegadas + saidas + sem_execucao

  # Todos os esperados contados, e ainda aberta.
  def pronta? = fechada_em.nil? && !esperados.nil? && contados >= esperados

  # Os que a vez esperava e não contou (ainda andando, ou fechados por fora do motor).
  def faltaram = [esperados.to_i - contados, 0].max
end
