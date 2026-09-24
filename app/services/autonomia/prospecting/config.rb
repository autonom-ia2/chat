module Autonomia::Prospecting::Config
  BOOLEAN = ActiveModel::Type::Boolean.new
  INTERNAL_ATTR_KEY = 'autonomia_prospecting_enabled'.freeze
  # Pesquisa de empresa e decisor (enriquecimento por site hoje, pesquisa da E3 depois). Só o superadmin liga (#683).
  RESEARCH_ATTR_KEY = 'autonomia_prospecting_research_enabled'.freeze

  def self.enabled?(account)
    flag?(account, INTERNAL_ATTR_KEY)
  end

  def self.enable_for!(account)
    update_internal_attribute!(account, INTERNAL_ATTR_KEY, true)
  end

  def self.disable_for!(account)
    update_internal_attribute!(account, INTERNAL_ATTR_KEY, false)
  end

  def self.research_enabled?(account)
    flag?(account, RESEARCH_ATTR_KEY)
  end

  def self.enable_research_for!(account)
    update_internal_attribute!(account, RESEARCH_ATTR_KEY, true)
  end

  def self.disable_research_for!(account)
    update_internal_attribute!(account, RESEARCH_ATTR_KEY, false)
  end

  def self.flag?(account, key)
    BOOLEAN.cast(account&.internal_attributes&.[](key)) || false
  end

  def self.update_internal_attribute!(account, key, enabled)
    account.internal_attributes = account.internal_attributes.to_h.merge(key => enabled)
    account.save!
    account
  end
end
