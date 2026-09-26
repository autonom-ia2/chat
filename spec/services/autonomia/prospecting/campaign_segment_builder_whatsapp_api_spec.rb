require 'rails_helper'

# Campanha pela API do WhatsApp a partir da Prospecção (#732, item 11; ACAO-X09): o segmento entra na audiência de uma
# campanha da API do WhatsApp (WhatsappApiCampaign) que ainda não começou, pela mesma etiqueta da campanha de envio
# único. A regra de recusa é a mesma para os dois tipos: quem pediu para parar nunca recebe a etiqueta.
RSpec.describe Autonomia::Prospecting::CampaignSegmentBuilder do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:list) { Autonomia::Prospecting::List.create!(account: account, user: user, name: 'Selecao') }
  let(:inbox) { create_whatsapp_api_inbox(account: account) }
  let(:other_label) { account.labels.create!(title: 'clientes_antigos') }
  let(:campaign) { create_whatsapp_api_campaign(account: account, user: user, inbox: inbox, label: other_label) }

  around do |example|
    with_modified_env('WHATSAPP_API_CAMPAIGNS_ENABLED' => 'true') { example.run }
  end

  def add_lead(name:, phone:)
    lead = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "place-#{name}", name: name, phone: phone, country: 'BR',
      status: :ready_for_campaign, metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } }
    )
    list.list_leads.create!(account: account, lead: lead)
    lead
  end

  def build(campaign_id: campaign.id, campaign_type: 'whatsapp_api')
    described_class.new(list: list, user: user, campaign_id: campaign_id, campaign_type: campaign_type, segment_name: 'Selecao')
  end

  it 'põe a etiqueta do segmento na audiência da campanha da API, sem tirar o que ela já tinha' do
    add_lead(name: 'Pronto', phone: '+5531999990001')

    result = build.perform

    audience = campaign.reload.audience.map { |item| item.to_h.stringify_keys }
    expect(audience).to contain_exactly({ 'type' => 'Label', 'id' => other_label.id }, { 'type' => 'Label', 'id' => result.label.id })
    expect(result.campaign).to eq(campaign)
    expect(list.reload.metadata['campaign_segment']).to include('campaign_id' => campaign.id, 'campaign_type' => 'whatsapp_api',
                                                                'campaign_title' => campaign.title)
  end

  it 'a recusa vale igual: quem pediu para parar em outro lead com o mesmo número fica fora e sem etiqueta' do
    add_lead(name: 'Pronto', phone: '+5531999990001')
    vetoed = add_lead(name: 'Mesmo numero', phone: '+5531999990002')
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'place-recusou', name: 'Recusou',
                                         phone: '+5531999990002', status: :no_consent)

    result = build.perform

    expect(result.eligible_leads.map(&:name)).to eq(['Pronto'])
    expect(result.blocked_leads.to_h { |row| [row[:lead].name, row[:reason_code]] }).to eq('Mesmo numero' => 'opt_out')
    expect(vetoed.reload.contact).to be_nil
  end

  # A etiqueta tem nome estável e a campanha da API resolve o público por ela ao começar: quem foi etiquetado antes e
  # depois recusou perde a etiqueta quando o segmento é refeito, senão receberia a mensagem.
  it 'quem foi etiquetado e depois recusou perde a etiqueta e não entra no público da campanha' do
    add_lead(name: 'Pronto', phone: '+5531999990001')
    refused = add_lead(name: 'Depois recusou', phone: '+5531999990002')
    first = described_class.new(list: list, user: user, segment_name: 'Selecao').perform
    expect(refused.reload.contact.label_list).to include(first.label.title)

    refused.update!(status: :no_consent)
    result = build.perform
    WhatsappApiCampaigns::AudienceResolver.new(campaign.reload).perform

    expect(result.blocked_leads.to_h { |row| [row[:lead].name, row[:reason_code]] }).to eq('Depois recusou' => 'opt_out')
    expect(refused.contact.reload.label_list).not_to include(result.label.title)
    expect(campaign.whatsapp_api_campaign_recipients.map { |recipient| recipient.contact.name }).to eq(['Pronto'])
  end

  it 'o contato que outro lead elegível da lista divide não perde a etiqueta' do
    kept = add_lead(name: 'Pronto', phone: '+5531999990001')
    other = add_lead(name: 'Sem whatsapp agora', phone: '+5531999990001')
    described_class.new(list: list, user: user, segment_name: 'Selecao').perform
    other.update!(status: :discarded, discard_reason: 'Duplicado')

    result = build.perform

    expect(result.blocked_leads.map { |row| row[:reason_code] }).to eq(['discarded'])
    expect(kept.reload.contact.label_list).to include(result.label.title)
  end

  it 'a etiqueta entra no público que a campanha resolve ao começar' do
    add_lead(name: 'Pronto', phone: '+5531999990001')

    build.perform
    WhatsappApiCampaigns::AudienceResolver.new(campaign.reload).perform

    expect(campaign.whatsapp_api_campaign_recipients.map { |recipient| recipient.contact.name }).to eq(['Pronto'])
  end

  it 'campanha da API que já começou recusa, e nada fica gravado' do
    add_lead(name: 'Pronto', phone: '+5531999990001')
    campaign.update!(status: :running)

    expect { build.perform }.to raise_error(described_class::Error, 'prospecting.campaign.campaign_not_active')
    expect(campaign.reload.audience.size).to eq(1)
    expect(list.reload.metadata['campaign_segment']).to be_nil
  end

  it 'com a campanha da API desligada na instalação, recusa como campanha não suportada' do
    add_lead(name: 'Pronto', phone: '+5531999990001')

    with_modified_env('WHATSAPP_API_CAMPAIGNS_ENABLED' => 'false') do
      expect { build.perform }.to raise_error(described_class::Error, 'prospecting.campaign.unsupported_campaign')
    end
  end

  it 'tipo de campanha desconhecido recusa' do
    add_lead(name: 'Pronto', phone: '+5531999990001')

    expect { build(campaign_type: 'email').perform }.to raise_error(described_class::Error, 'prospecting.campaign.unsupported_campaign')
  end

  it 'campanha da API de outra conta não é achada' do
    add_lead(name: 'Pronto', phone: '+5531999990001')
    other_account = create(:account)
    other_user = create(:user, :administrator, account: other_account)
    foreign = create_whatsapp_api_campaign(account: other_account, user: other_user, inbox: create_whatsapp_api_inbox(account: other_account),
                                           label: other_account.labels.create!(title: 'outra'))

    expect { build(campaign_id: foreign.id).perform }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'lista que já alimenta uma campanha da API agendada conta como audiência existente' do
    add_lead(name: 'Pronto', phone: '+5531999990001')
    result = build.perform

    again = described_class.new(list: list.reload, user: user, segment_name: 'Selecao')

    expect(again.feeds_existing_campaign?).to be(true)
    expect(result.label).to be_present
  end

  it 'sem tipo, continua sendo a campanha de envio único, como antes' do
    add_lead(name: 'Pronto', phone: '+5531999990001')
    one_off = create(:campaign, account: account, inbox: create(:channel_sms, account: account).inbox, audience: [],
                                scheduled_at: 1.day.from_now)

    result = described_class.new(list: list, user: user, campaign_id: one_off.display_id, segment_name: 'Selecao').perform

    expect(result.campaign).to eq(one_off)
    expect(list.reload.metadata['campaign_segment']).to include('campaign_id' => one_off.display_id, 'campaign_type' => 'one_off')
  end
end
