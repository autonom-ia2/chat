# Memória das IAs do Chat2You (#1601): os fatos do pedido e do cliente com procedência, que a IA lê pelo
# Crm::Memoria::Leitor. Tudo atrás da flag por conta `memoria_ia`; este é o ÚNICO ponto de leitura dela (o Agentes IA
# também lê por aqui).
module Crm::Memoria
  FLAG = 'memoria_ia'.freeze

  module_function

  def ligada?(account)
    account.present? && ::Crm::Config.enabled? && account.feature_enabled?(FLAG)
  end

  # A conversa entra na memória: a flag ligada na conta dela.
  def ativa?(conversation)
    conversation.present? && ligada?(conversation.account)
  end
end
