# Chave por conta da aba "Agente de IA" por caixa (#1648). Piloto: contas 1, 16 e 18 da stack hub2you, ligadas pela
# Orquestração com OK do Rodrigo (flag nova nasce ligada no piloto). Desligada (padrão): a conta fica como a main.
#
# Ligada:
# - a aba da caixa é "Agente de IA" (QuemAtendeController, AbaAgenteDeIa.vue) e a de pessoas se chama "Usuários";
# - a lista de robôs não mostra os espelhos dos agentes da plataforma e responde 404 a eles (RobosSemEspelho, #1626);
# - o set_agent_bot cru recusa agente de outro sistema em caixa com porta nossa (CaixaSemAgenteExterno);
# - a lista de Agentes mostra os agentes de outro sistema, com página própria e "Conectar";
# - a área convive com agente de outro sistema atendendo primeiro (opção B, Areas.caixa_aceita_area?). Área só existe
#   com a Fase 2; as duas flags andam juntas no piloto.
#
# Marca no jsonb interno `accounts.internal_attributes` (não editável pelo usuário), como Autonomia::Agents::Fase2, sem
# bit de feature_flags.
module Autonomia::Agents::AgenteIaPorCaixa
  BOOLEAN = ActiveModel::Type::Boolean.new
  INTERNAL_ATTR_KEY = 'autonomia_agente_ia_por_caixa'.freeze

  module_function

  def ligada?(account)
    return false if account.blank?

    BOOLEAN.cast(account.internal_attributes.to_h[INTERNAL_ATTR_KEY]) || false
  end

  # Pelo id, lendo do banco: para quem só tem a caixa (Areas, AgentInbox) e não deve carregar `inbox.account` no meio
  # de uma regra (a associação carregada ficaria velha para quem a usar depois).
  def ligada_na_conta?(account_id)
    return false if account_id.blank?

    BOOLEAN.cast(Account.where(id: account_id).pick(Arel.sql("internal_attributes->>'#{INTERNAL_ATTR_KEY}'"))) || false
  end

  def ligar!(account)
    gravar!(account, true)
  end

  def desligar!(account)
    gravar!(account, false)
  end

  def gravar!(account, ligada)
    account.internal_attributes = account.internal_attributes.to_h.merge(INTERNAL_ATTR_KEY => ligada)
    account.save!
    account
  end
  private_class_method :gravar!
end
