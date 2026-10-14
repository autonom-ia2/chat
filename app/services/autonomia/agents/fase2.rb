# Chave por conta da Fase 2 dos Agentes (épico #1424). Primeiro uso: #1433 F1a, a escolha de quem responde pelo dono da
# conversa (Autonomia::Agents::QuemResponde). Desligada (padrão): tudo como antes da Fase 2.
#
# Marca no jsonb interno `accounts.internal_attributes` (não editável pelo usuário), como Autonomia::Insurance::Config,
# sem bit de feature_flags. Só vale com os Agentes ligados na conta (Autonomia::Agents::Config.enabled?), que é checado
# por quem chama. Piloto: contas 1, 16 e 18, ligadas pela Orquestração com OK do Rodrigo.
module Autonomia::Agents::Fase2
  BOOLEAN = ActiveModel::Type::Boolean.new
  INTERNAL_ATTR_KEY = 'autonomia_agents_fase2'.freeze

  module_function

  def ligada?(account)
    return false if account.blank?

    BOOLEAN.cast(account.internal_attributes.to_h[INTERNAL_ATTR_KEY]) || false
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
