# O motor da Automação livre (#2414 F3, #2459). Uma automação ligada começa (Partida), anda passo a passo
# (Executor) e espera no banco; a varredura de minuto em minuto acorda quem espera (VarreduraJob).
#
# Só roda com as duas flags: a do motor e a da fundação (F1). Sem a fundação não há a cadeia comum, e uma automação
# poderia disparar outra sem fim.
module Autonomia::Automacao::Motor
  FLAG = 'automacao_motor'.freeze

  # F4: mensagem ao cliente e aviso à equipe, só com o motor ligado.
  FLAG_MENSAGENS = 'automacao_mensagens'.freeze

  def self.ligado?(account)
    ::Autonomia::Automacao.fundacao?(account) && account.feature_enabled?(FLAG)
  end

  def self.mensagens?(account)
    ligado?(account) && account.feature_enabled?(FLAG_MENSAGENS)
  end

  # F7: os passos de IA (decidir, extrair, escrever, resumir), só com o motor ligado.
  FLAG_IA = 'automacao_ia'.freeze

  def self.ia?(account)
    ligado?(account) && account.feature_enabled?(FLAG_IA)
  end

  # F6 (#2499): os gatilhos de card do funil, só com o motor ligado e o CRM da instalação.
  FLAG_GATILHOS = 'automacao_gatilhos'.freeze

  def self.gatilhos?(account)
    gatilhos_sem_crm?(account) && ::Crm::Config.enabled?
  end

  # O gatilho de tempo do contato (#2499, PR3) vem com a mesma flag, mas não depende do CRM.
  def self.gatilhos_sem_crm?(account)
    ligado?(account) && account.feature_enabled?(FLAG_GATILHOS)
  end

  # A origem da automação na cadeia comum (D6), ao lado de "regra:<id>" e "etapa:<id>".
  def self.origem(definicao)
    "automacao:#{definicao.id}"
  end
end
