require 'rails_helper'

# #1335: a mensagem escrita entra junto com a campanha do WhatsApp oficial, conferida, e só com a flag da conta.
RSpec.describe CampaignJourney::WhatsappCampaignCreator, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:channel) { journey_cloud_channel(account) }
  let(:audience) do
    saved_audience(account: account, user: account_and_user.last, content: "Nome,Celular,Link da oferta\nAna,11987654321,https://x.com/1\n")
  end

  before { account.enable_features!(:campaign_open_window_text) }

  def criar(free_text)
    described_class.new(
      account: account, campaign_import: audience, channel: 'whatsapp_cloud',
      attributes: { title: 'Coleção nova', inbox_id: channel.inbox.id, template_params: journey_template_params, free_text: free_text,
                    variable_bindings: { '1' => { source: 'contact', value: 'first_name' },
                                         '2' => { source: 'column', value: 'Link da oferta' },
                                         '3' => { source: 'fixed', value: 'Equipe' } } }
    ).perform
  end

  it 'grava a mensagem escrita da campanha' do
    campaign = criar('Oi, {{cliente.primeiro_nome}}! As peças estão aqui: {{publico.Link_da_oferta}}. Quer ver?')

    expect(CampaignFreeText.find_by(campaign: campaign)).to have_attributes(
      account_id: account.id, content: 'Oi, {{cliente.primeiro_nome}}! As peças estão aqui: {{publico.Link_da_oferta}}. Quer ver?'
    )
  end

  it 'sem mensagem escrita, a campanha é só do modelo' do
    campaign = criar('')

    expect(campaign).to be_persisted
    expect(CampaignFreeText.count).to eq(0)
  end

  it 'recusa link digitado, com o motivo, e não cria nada' do
    expect { criar('Veja em www.loja.com.br') }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq('free_text_invalid')
      expect(error.details).to eq(reason: 'link_digitado')
    }
    expect(account.campaigns.count).to eq(0)
  end

  it 'recusa campo que o público não tem' do
    expect { criar('Oi {{publico.Vencimento}}') }.to raise_error(described_class::Error) { |error|
      expect(error.details).to eq(reason: 'chave_fora_da_lista')
    }
  end

  it 'modelo de código de acesso nunca leva mensagem escrita' do
    channel.update!(message_templates: [CampaignJourneyHelpers::JOURNEY_TEMPLATE.merge('category' => 'AUTHENTICATION')])

    expect { criar('Oi, {{cliente.primeiro_nome}}!') }.to raise_error(described_class::Error) { |error|
      expect(error.details).to eq(reason: 'authentication_template')
    }
  end

  it 'com a flag da conta desligada, recusa a mensagem escrita' do
    account.disable_features!(:campaign_open_window_text)

    expect { criar('Oi, {{cliente.primeiro_nome}}!') }.to raise_error(described_class::Error) { |error|
      expect(error.code).to eq('free_text_disabled')
    }
  end
end
