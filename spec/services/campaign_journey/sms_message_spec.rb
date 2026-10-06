require 'rails_helper'

# #1004: SMS tokens with the #999 grammar ({{contact.*}}, {{publico.<key>}}), filled in one pass.
RSpec.describe CampaignJourney::SmsMessage, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:audience) do
    saved_audience(account: account, user: account_and_user.last,
                   content: "Nome,Celular,Data de Vencimento,Plano\nAna Souza,11987654321,10/2026,\n")
  end
  let(:contact) { audience.campaign_import_rows.first.contact }

  def sms(text, defaults = {})
    described_class.new(text, campaign_import: audience, defaults: defaults)
  end

  it 'renders contact and audience tokens per person, never reading inserted values again' do
    contact.update!(name: 'Ana {{contact.name}}', additional_attributes: { 'company_name' => 'Alfa' })
    text = '{{contact.first_name}} / {{contact.company}} / {{publico.data_de_vencimento}} / {{ publico.plano }}'

    expect(sms(text, 'publico.plano' => 'básico').render_for(contact)).to eq(['Ana / Alfa / 10/2026 / básico', []])
    expect(sms('Oi {{contact.name}}').render_for(contact)).to eq(['Oi Ana {{contact.name}}', []])
  end

  it 'lists what is missing as "empresa" and the column key' do
    expect(sms('{{contact.company}} {{publico.plano}}').render_for(contact)).to eq([nil, %w[empresa plano]])
    expect(described_class.missing_reason(%w[empresa plano])).to eq('falta empresa, plano')
  end

  it 'validates tokens, audience columns, defaults and length' do
    expect { sms('{{contact.email}}').validate! }.to raise_error(described_class::Error) { |error|
      expect([error.message, error.details]).to eq(['unsupported_variables', { unknown: ['contact.email'] }])
    }
    expect { sms('{{publico.vencimento}}').validate! }.to raise_error(described_class::Error, 'unknown_audience_column')
    expect { sms('Oi', 'contact.company' => 'x').validate! }.to raise_error(described_class::Error, 'invalid_variable_defaults')
    too_long = { 'contact.company' => 'x' * 1025 }
    expect { sms('{{contact.company}}', too_long).validate! }.to raise_error(described_class::Error, 'invalid_variable_defaults')
    expect { sms('a' * 1601).validate! }.to raise_error(described_class::Error, 'message_too_long')
    expect { sms('{{contact.name}} {{publico.data_de_vencimento}} {{publico.plano}}').validate! }.not_to raise_error
  end
end
