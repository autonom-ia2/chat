class Autonomia::Agents::RedesignGate
  ATTR_KEY = 'autonomia_agents_redesign'.freeze
  BOOLEAN = ActiveModel::Type::Boolean.new

  def self.redesign_enabled?(account)
    BOOLEAN.cast(ENV.fetch('AUTONOMIA_AGENTS_REDESIGN', false)) && redesign_enabled_for?(account)
  end

  def self.redesign_enabled_for?(account)
    BOOLEAN.cast(account.internal_attributes[ATTR_KEY]) || false
  end

  def self.enable_redesign_for!(account)
    set_enabled!(account, true)
  end

  def self.disable_redesign_for!(account)
    set_enabled!(account, false)
  end

  def self.set_enabled!(account, enabled)
    account.with_lock do
      account.update!(internal_attributes: account.internal_attributes.merge(ATTR_KEY => enabled))
    end
    account
  end
  private_class_method :set_enabled!
end
