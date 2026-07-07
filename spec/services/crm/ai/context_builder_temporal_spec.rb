require 'rails_helper'

# Regression (H2-callback): the temporal anchor the classifier uses to resolve
# "terça 9h" must be expressed in the OPERATIONAL timezone, not UTC. now_local
# and default_hour together tell the LLM to emit a naive local datetime; if the
# anchor silently sits in UTC the whole callback lands 3h off in BR.
RSpec.describe Crm::Ai::ContextBuilder do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }
  let(:stage) { pipeline.stages.first }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact) }
  let(:card) do
    account.crm_cards.create!(
      pipeline: pipeline, stage: stage, title: 'Lead',
      contact: contact, primary_conversation: conversation, currency: 'BRL'
    )
  end

  describe '#perform temporal' do
    it 'anchors now_local in the resolved operational tz (SP), not UTC' do
      # 2026-07-01 12:00 UTC == 09:00 America/Sao_Paulo.
      travel_to(Time.utc(2026, 7, 1, 12, 0, 0)) do
        temporal = with_modified_env DEFAULT_OPERATIONAL_TIMEZONE: nil do
          described_class.new(card: card).perform[:temporal]
        end

        expect(temporal[:timezone]).to eq('America/Sao_Paulo')
        expect(temporal[:now_local]).to eq('2026-07-01T09:00')
        expect(temporal[:default_hour]).to eq(Crm::Ai::Config::CALLBACK_DEFAULT_HOUR)
      end
    end
  end
end
