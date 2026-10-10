# O classificador pediu passar a conversa para uma pessoa? Lê a intenção estruturada que ele devolveu ("transferir",
# "continuar", "consultar") e, sem ela, o should_handoff. É a saída do modelo, não o texto do cliente.
class Crm::Ai::HandoffIntent
  def self.requested?(handoff)
    return false if handoff.blank?

    data = handoff.respond_to?(:with_indifferent_access) ? handoff.with_indifferent_access : handoff.to_h
    intent = data[:intent].to_s
    return true if intent == 'transferir'
    return false if %w[continuar consultar].include?(intent)

    ActiveModel::Type::Boolean.new.cast(data[:should_handoff])
  end
end
