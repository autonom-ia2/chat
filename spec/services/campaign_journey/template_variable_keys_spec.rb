require 'rails_helper'

# #993: variables of a TEXT header and of URL buttons are bound like body variables (contact,
# column or fixed text), validated when the campaign is created and sent in the right component.
RSpec.describe CampaignJourney::TemplateVariableKeys, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:template) do
    {
      'name' => 'renovacao_link', 'status' => 'APPROVED', 'category' => 'MARKETING', 'language' => 'pt_BR', 'namespace' => 'ns',
      'components' => [
        { 'type' => 'HEADER', 'format' => 'TEXT', 'text' => 'Renovação {{1}}' },
        { 'type' => 'BODY', 'text' => 'Olá {{1}}, sua apólice vence em breve.' },
        { 'type' => 'BUTTONS', 'buttons' => [
          { 'type' => 'QUICK_REPLY', 'text' => 'Não agora' },
          { 'type' => 'URL', 'text' => 'Renovar', 'url' => 'https://exemplo.com.br/r/{{1}}' }
        ] }
      ]
    }
  end
  let(:channel) do
    channel = journey_cloud_channel(account)
    channel.update!(message_templates: [template])
    channel
  end
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular,Codigo\nAna Souza,11987654321,  AB  12\n",
                   mapping: { 'name' => 0, 'phone' => 1 })
  end
  let(:template_params) do
    { 'name' => 'renovacao_link', 'namespace' => 'ns', 'category' => 'MARKETING', 'language' => 'pt_BR',
      'processed_params' => { 'body' => { '1' => '' }, 'header' => { '1' => '' },
                              'buttons' => [nil, { 'type' => 'url', 'parameter' => '', 'url' => 'https://exemplo.com.br/r/{{1}}' }] } }
  end
  let(:bindings) do
    {
      '1' => { 'source' => 'contact', 'value' => 'first_name' },
      'header.1' => { 'source' => 'fixed', 'value' => 'auto' },
      'button.1' => { 'source' => 'column', 'value' => 'Codigo' }
    }
  end

  def create_campaign(variable_bindings)
    CampaignJourney::WhatsappCampaignCreator.new(
      account: account, campaign_import: audience, channel: 'whatsapp_cloud',
      attributes: { title: 'Renovação com link', inbox_id: channel.inbox.id, template_params: template_params,
                    variable_bindings: variable_bindings, variable_defaults: {} }
    ).perform
  end

  it 'reads the keys of body, TEXT header and URL buttons in template order' do
    expect(described_class.keys(template)).to eq(['1', 'header.1', 'button.1'])
  end

  it 'refuses a campaign that leaves the button variable unbound' do
    expect { create_campaign(bindings.except('button.1')) }
      .to raise_error(CampaignJourney::WhatsappCampaignCreator::Error) { |error| expect(error.code).to eq('invalid_variable_bindings') }
  end

  it 'sends {{1}} of the body and {{1}} of the button in their own components, squished' do
    sent = stub_graph_messages
    campaign = create_campaign(bindings)

    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

    components = sent.sole.dig('template', 'components')
    by_type = components.index_by { |component| component['type'] }
    expect(by_type['header']['parameters']).to eq([{ 'type' => 'text', 'text' => 'auto' }])
    expect(by_type['body']['parameters']).to eq([{ 'type' => 'text', 'text' => 'Ana' }])
    expect(by_type['button']).to include('sub_type' => 'url', 'index' => 1,
                                         'parameters' => [{ 'type' => 'text', 'text' => 'AB 12' }])
    expect(CampaignRecipient.find_by(campaign: campaign)).to be_sent
  end
end
