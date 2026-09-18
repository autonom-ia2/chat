require_relative '../../lib/email_campaigns/reputation_schema_guards'

class ProtectEmailReputationHistory < ActiveRecord::Migration[7.1]
  def up
    EmailCampaigns::ReputationSchemaGuards.new(connection).install!
  end

  def down
    EmailCampaigns::ReputationSchemaGuards.new(connection).uninstall!
  end
end
