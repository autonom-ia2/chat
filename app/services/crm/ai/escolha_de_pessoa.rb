# #1920: o que conta como "uma pessoa escolheu a etapa" para a evidência e o raio-x das frases, e quais cards cada um lê.
#
# Escolha direta: movimento de card gravado como de usuário SEM origem de automação no payload. A automação de etapa e o
# "Aconteceu" do agendamento também gravam o movimento em nome de uma pessoa, mas o Crm::Cards::Mover põe neles
# `source`/`automation_depth`. Movimento gravado antes disso não tem a marca e entra (limitação conhecida).
#
# Separação ensinar × provar: os cards de id par só ensinam (evidência do "Melhorar com IA"); os de id ímpar só provam
# (raio-x). Assim o raio-x nunca mede acerto num card cuja resposta a IA que escreve a frase já leu.
module Crm::Ai::EscolhaDePessoa
  def self.movimentos(account_id, desde:)
    Crm::Activity.where(account_id: account_id, event_type: 'move', actor_type: 'user', created_at: desde..)
                 .where("crm_activities.payload->>'source' IS NULL AND crm_activities.payload->>'automation_depth' IS NULL")
  end

  def self.ensinam(scope, coluna = :card_id)
    scope.where("#{scope.klass.table_name}.#{coluna} % 2 = 0")
  end

  def self.provam(scope, coluna = :card_id)
    scope.where("#{scope.klass.table_name}.#{coluna} % 2 = 1")
  end
end
