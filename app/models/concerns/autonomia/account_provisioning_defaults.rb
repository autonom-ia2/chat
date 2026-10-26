# frozen_string_literal: true

module Autonomia::AccountProvisioningDefaults
  extend ActiveSupport::Concern

  DEFAULT_FEATURE_FLAGS = 8_950_126_033_336_532_983
  DEFAULT_ACCOUNT_USER_ID = 1
  CHATWOOT_INTERNAL_FEATURES = Featurable::FEATURE_LIST.select { |feature| feature['chatwoot_internal'] }.pluck('name').freeze

  included do
    before_create :apply_autonomia_default_feature_flags, if: :autonomia_account_defaults_enabled?
    before_create :apply_autonomia_default_internal_attributes, if: :autonomia_account_defaults_enabled?
    after_create_commit :ensure_autonomia_default_account_user, if: :autonomia_account_defaults_enabled?
  end

  private

  # O número fixo é a base da coluna `feature_flags` (#49). Os padrões por nome do ACCOUNT_LEVEL_FEATURE_DEFAULTS, que
  # o Featurable ligou antes, valem por cima dele: sem isso, uma flag desta coluna ligada para contas novas (companies,
  # #1175) era apagada aqui. As internas do Chatwoot (`chatwoot_internal` no features.yml) nunca nascem ligadas.
  def apply_autonomia_default_feature_flags
    self.feature_flags = autonomia_default_feature_flags
    enable_features(*(autonomia_named_default_features - CHATWOOT_INTERNAL_FEATURES))
  end

  # #2228: conta nova nasce com a Fase 2 dos Agentes e o "Agente de IA" por caixa. As chaves que já vêm na criação
  # (billing_provider, signup_source, ou a própria chave dada por quem cria) valem por cima do padrão.
  def apply_autonomia_default_internal_attributes
    self.internal_attributes = {
      Autonomia::Agents::Fase2::INTERNAL_ATTR_KEY => true,
      Autonomia::Agents::AgenteIaPorCaixa::INTERNAL_ATTR_KEY => true
    }.merge(internal_attributes.to_h.stringify_keys)
  end

  def autonomia_named_default_features
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return [] if config.blank?

    config.value.select { |feature| feature[:enabled] }.pluck(:name)
  end

  def ensure_autonomia_default_account_user
    user = User.find_by(id: autonomia_default_account_user_id)
    return if user.blank?

    AccountUser.find_or_create_by!(account: self, user: user) do |account_user|
      account_user.role = 'administrator'
    end
  end

  def autonomia_default_feature_flags
    ENV.fetch('AUTONOMIA_DEFAULT_ACCOUNT_FEATURE_FLAGS', DEFAULT_FEATURE_FLAGS).to_i
  end

  def autonomia_default_account_user_id
    ENV.fetch('AUTONOMIA_DEFAULT_ACCOUNT_USER_ID', DEFAULT_ACCOUNT_USER_ID).to_i
  end

  def autonomia_account_defaults_enabled?
    value = ENV.fetch('AUTONOMIA_ACCOUNT_DEFAULTS_ENABLED', nil)
    return ActiveModel::Type::Boolean.new.cast(value) unless value.nil?

    !Rails.env.test?
  end
end
