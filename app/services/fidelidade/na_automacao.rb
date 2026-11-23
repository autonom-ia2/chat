# Os dados do cartão fidelidade que a Automação livre lê do contato (#3100), no "Pôr um dado" e no "se": quantos ele
# tem, quantos faltam para o prêmio e qual é o prêmio. Entram em Autonomia::Automacao::Valores::CAMPOS, na base
# `contato`, então valem em todo gatilho que chega ao contato (conversa, card, contato).
#
# Sem cartão na conta, os três ficam vazios: o passo que os usa pula, como com qualquer valor vazio. Quem não tem
# carimbo nenhum tem 0 (não vazio): o aviso de saldo diz "0".
module Fidelidade::NaAutomacao
  VALORES = {
    'contato.fidelidade_saldo' => ->(contato) { Fidelidade::NaAutomacao.saldo(contato) },
    'contato.fidelidade_faltam' => ->(contato) { Fidelidade::NaAutomacao.faltam(contato) },
    'contato.fidelidade_premio' => ->(contato) { Fidelidade::Programa.da_conta(contato.account)&.premio }
  }.freeze

  module_function

  def saldo(contato)
    programa = Fidelidade::Programa.da_conta(contato.account)
    programa && saldo_no(programa, contato)
  end

  # Quantos faltam para completar o cartão; 0 quando já completou (o que passa da meta fica para o próximo).
  def faltam(contato)
    programa = Fidelidade::Programa.da_conta(contato.account)
    programa && [programa.meta - saldo_no(programa, contato), 0].max
  end

  def saldo_no(programa, contato) = Fidelidade::Saldo.find_by(programa_id: programa.id, contact_id: contato.id)&.saldo || 0
end
