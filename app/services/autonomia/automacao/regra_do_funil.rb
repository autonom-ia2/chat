# Regra que mexe no funil do CRM (#2414 F1.3, D4 do ADR-001). Montar automação de etapa pede as chaves das regras e de
# configurar funis; o espelho vale para a regra automática: a que cria, move, ganha, perde ou atribui card, ou que
# depende do funil nas condições, também pede a chave de funis. `crm_admin` vale por todas as crm_*, como no
# CrmPermissions. Só com a flag `automacao_fundacao`: sem ela, a regra segue só com automation_manage, como antes.
module Autonomia::Automacao::RegraDoFunil
  ACOES = %w[crm_create_card crm_move_card_stage crm_mark_card_won crm_mark_card_lost crm_assign_card_owner].freeze
  CHAVES = %w[crm_manage_pipelines crm_admin].freeze

  # As ações e condições vêm do registro (array) ou do pedido (array em JSON, ou hash indexado em formulário).
  def self.mexe?(actions, conditions)
    nomes(actions, :action_name).intersect?(ACOES) ||
      nomes(conditions, :attribute_key).intersect?(AutomationRules::CrmConditions::OPERATORS.keys)
  end

  def self.pode?(account_user)
    return true unless Autonomia::Automacao.fundacao?(account_user&.account)

    CHAVES.any? { |chave| account_user.permission_granted?(chave) }
  end

  def self.nomes(lista, campo)
    lista = lista.to_unsafe_h.values if lista.respond_to?(:to_unsafe_h)
    lista = lista.values if lista.is_a?(Hash)
    Array(lista).filter_map { |item| hash_de(item).with_indifferent_access[campo]&.to_s }
  end

  # Item do pedido chega como ActionController::Parameters não permitido: aqui só se lê o nome.
  def self.hash_de(item)
    item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : item.to_h
  end
end
