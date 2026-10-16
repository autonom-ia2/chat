require 'rails_helper'

RSpec.describe Messages::EnvioAutomatico do
  let(:message) do
    instance_double(Message, sender_type: sender_type, content_attributes: content_attributes,
                             additional_attributes: additional_attributes)
  end
  let(:sender_type) { 'User' }
  let(:content_attributes) { {} }
  let(:additional_attributes) { {} }

  it 'is not automatic for a person typing in the panel' do
    expect(described_class.automatico?(message)).to be(false)
  end

  context 'with a robot or assistant sender' do
    %w[AgentBot Captain::Assistant].each do |tipo|
      it "is automatic for #{tipo}" do
        allow(message).to receive(:sender_type).and_return(tipo)
        expect(described_class.automatico?(message)).to be(true)
      end
    end
  end

  context 'with a mark of an automatic send recorded as a person' do
    %w[automation_rule_id crm_follow_up_id crm_booking_invite_id crm_booking_notice].each do |marca|
      it "is automatic with #{marca}" do
        allow(message).to receive(:content_attributes).and_return({ marca => 1 })
        expect(described_class.automatico?(message)).to be(true)
      end
    end

    %w[campaign_id whatsapp_api_campaign_id].each do |marca|
      it "is automatic with #{marca} in additional_attributes" do
        allow(message).to receive(:additional_attributes).and_return({ marca => 1 })
        expect(described_class.automatico?(message)).to be(true)
      end
    end
  end
end
