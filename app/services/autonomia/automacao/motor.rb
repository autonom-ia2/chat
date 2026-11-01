# O motor da Automação livre (#2414 F3, #2459). Uma automação ligada começa (Partida), anda passo a passo
# (Executor) e espera no banco; a varredura de minuto em minuto acorda quem espera (VarreduraJob).
#
# Só roda com as duas flags: a do motor e a da fundação (F1). Sem a fundação não há a cadeia comum, e uma automação
# poderia disparar outra sem fim.
module Autonomia::Automacao::Motor
  FLAG = 'automacao_motor'.freeze

  def self.ligado?(account)
    ::Autonomia::Automacao.fundacao?(account) && account.feature_enabled?(FLAG)
  end

  # A origem da automação na cadeia comum (D6), ao lado de "regra:<id>" e "etapa:<id>".
  def self.origem(definicao)
    "automacao:#{definicao.id}"
  end
end
