# Memória das IAs do Chat2You (#1601). Tudo atrás da flag por conta `memoria_ia`; este é o ÚNICO ponto de leitura dela
# (o Agentes IA também lê por aqui).
#
# - Crm::Memoria::Origem: quem escreveu cada mensagem e se chegou ao cliente (crm_mensagem_origens).
# - Crm::Memoria::Mescla: a mescla de contatos leva a memória do absorvido para o que fica, antes do destroy.
module Crm::Memoria
  FLAG = 'memoria_ia'.freeze

  module_function

  def ligada?(account)
    account.present? && ::Crm::Config.enabled? && account.feature_enabled?(FLAG)
  end

  # A conversa gera memória: flag ligada na conta e a caixa não foi tirada da memória pelo administrador.
  def ativa?(conversation)
    return false if conversation.blank? || !ligada?(conversation.account)

    !config(conversation.account).caixa_excluida?(conversation.inbox_id)
  end

  # A configuração da conta; sem linha gravada, a padrão (sem robôs declarados, nenhuma caixa fora). Nunca grava.
  def config(account)
    Crm::MemoriaConfig.find_by(account_id: account.id) || Crm::MemoriaConfig.new(account_id: account.id)
  end
end
