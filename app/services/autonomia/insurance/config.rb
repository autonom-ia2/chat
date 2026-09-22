# frozen_string_literal: true

# Gate em duas camadas do módulo Cotação (PRD Insurance §6), ISOLADO do sistema de features
# do Chatwoot (não toca featurable/feature_flags):
#   1) ENV master INSURANCE_QUOTING_ENABLED = kill-switch GLOBAL. OFF -> módulo indisponível
#      em TODAS as contas, mesmo as marcadas como habilitadas.
#   2) marca POR CONTA no jsonb interno `accounts.internal_attributes` (não editável pelo
#      usuário). Só libera nas contas marcadas explicitamente pelo SuperAdmin.
#
# Mesmo desenho de Autonomia::Agents::Config, SEM o auto-on global: Cotação nasce OFF e liga
# conta a conta (regra de rollout §59). Um único ponto de decisão para backend (controllers,
# jobs) e frontend (payload da conta + globalConfig).
module Autonomia::Insurance::Config
  BOOLEAN = ActiveModel::Type::Boolean.new
  ENV_KEY = 'INSURANCE_QUOTING_ENABLED'
  INTERNAL_ATTR_KEY = 'autonomia_insurance_enabled'

  def self.master_enabled?
    BOOLEAN.cast(ENV.fetch(ENV_KEY, false)) || false
  end

  # Boolean estrito (true/false, nunca nil): o payload da conta (_account.json.jbuilder) e os
  # gates do FE comparam com `=== true`.
  def self.enabled?(account)
    return false if account.blank?

    master_enabled? && account_enabled?(account)
  end

  # Marca da conta, independente da ENV — é o que o SuperAdmin exibe e alterna.
  def self.account_enabled?(account)
    BOOLEAN.cast(account.internal_attributes.to_h[INTERNAL_ATTR_KEY]) || false
  end

  def self.enable_for!(account)
    update_internal_attribute!(account, true)
    account
  end

  def self.disable_for!(account)
    update_internal_attribute!(account, false)
    account
  end

  # OS RAMOS ALÉM DE AUTO, LIGADOS CONTA A CONTA (chat#323, decisão do CEO em 22/09/2026). O especialista de um ramo
  # novo existe em todo agente de cotação, e só atende onde o SuperAdmin liberou o ramo nesta lista (e a conexão da
  # conta o tem habilitado, `QuoteAgent::Builder.atende?`). É o que permite ligar residencial primeiro na conta de
  # teste, conversar com a Lia de verdade, e só depois nas corretoras. Auto não passa por aqui.
  RAMOS_KEY = 'autonomia_insurance_ramos_liberados'

  def self.ramo_liberado?(account, ramo)
    return false if account.blank?

    Array(account.internal_attributes.to_h[RAMOS_KEY]).include?(ramo.to_s)
  end

  def self.liberar_ramo!(account, ramo)
    atualizar_ramos!(account, ramos_liberados(account) | [ramo.to_s])
  end

  def self.bloquear_ramo!(account, ramo)
    atualizar_ramos!(account, ramos_liberados(account) - [ramo.to_s])
  end

  def self.ramos_liberados(account)
    Array(account.internal_attributes.to_h[RAMOS_KEY]).map(&:to_s)
  end

  def self.atualizar_ramos!(account, ramos)
    account.internal_attributes = account.internal_attributes.to_h.merge(RAMOS_KEY => ramos)
    account.save!
    account
  end
  private_class_method :atualizar_ramos!

  def self.update_internal_attribute!(account, enabled)
    account.internal_attributes = account.internal_attributes.to_h.merge(INTERNAL_ATTR_KEY => enabled)
    account.save!
  end
  private_class_method :update_internal_attribute!
end
