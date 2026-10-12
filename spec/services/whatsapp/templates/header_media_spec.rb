require 'rails_helper'

# #1382 (auditoria M5): topo com mídia na campanha usa por padrão o arquivo guardado no perfil do modelo; link digitado
# é conferido no servidor. Antes, link vazio passava na criação e cada envio saía com o topo sem arquivo.
RSpec.describe Whatsapp::Templates::HeaderMedia, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:inbox) { channel.inbox }
  let(:template) do
    { 'name' => 'oferta', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'MARKETING',
      'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Chegou a oferta do mês.' }] }
  end
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\nBia Lima,21987654321\n")
  end

  before { channel.update_columns(message_templates: [template]) } # rubocop:disable Rails/SkipsModelValidations

  def params(header)
    { 'name' => 'oferta', 'language' => 'pt_BR', 'category' => 'MARKETING', 'processed_params' => { 'header' => header } }
  end

  def save_profile_file
    profile = WhatsappTemplateProfile.create!(account: account, inbox: inbox, waba_id: channel.waba_id, name: 'oferta', language: 'pt_BR')
    profile.header_file.attach(io: StringIO.new('png'), filename: 'oferta.png', content_type: 'image/png')
    profile
  end

  def create_campaign(header)
    CampaignJourney::WhatsappCampaignCreator.new(
      account: account, campaign_import: audience, channel: 'whatsapp_cloud',
      attributes: { title: 'Oferta', inbox_id: inbox.id, template_params: params(header), variable_bindings: {} }
    ).perform
  end

  def refusal_code(header)
    create_campaign(header)
    nil
  rescue CampaignJourney::WhatsappCampaignCreator::Error => e
    e.code
  end

  describe 'criação da campanha' do
    it 'sem link, com arquivo no perfil: cria e guarda o tipo, sem guardar link (ele é gerado no disparo)' do
      save_profile_file

      campaign = create_campaign({ 'media_url' => '' })

      expect(campaign.template_params.dig('processed_params', 'header')).to eq('media_url' => '', 'media_type' => 'image')
    end

    it 'sem link e sem arquivo no perfil: recusa header_media_required' do
      expect(refusal_code({ 'media_url' => '', 'media_type' => 'image' })).to eq('header_media_required')
      expect(account.campaigns.count).to eq(0)
    end

    it 'link que não é http(s), sem endereço ou malformado: recusa header_media_url_invalid' do
      ['ftp://arquivos.exemplo.com/a.png', 'https://', 'javascript:alert(1)', 'nao é link', "https://exemplo.com/#{'a' * 2000}"].each do |url|
        expect(refusal_code({ 'media_url' => url, 'media_type' => 'image' })).to eq('header_media_url_invalid')
      end
    end

    it 'topo que não é objeto (texto solto no pedido): recusa header_media_url_invalid, sem erro 500' do
      expect(refusal_code('https://exemplo.com/a.png')).to eq('header_media_url_invalid')
    end

    it 'link de tipo diferente do topo do modelo: recusa header_media_type_mismatch' do
      expect(refusal_code({ 'media_url' => 'https://exemplo.com/v.mp4', 'media_type' => 'video' })).to eq('header_media_type_mismatch')
    end

    it 'link https do mesmo tipo: cria com o link digitado' do
      campaign = create_campaign({ 'media_url' => ' https://exemplo.com/oferta.png ' })

      expect(campaign.template_params.dig('processed_params', 'header'))
        .to eq('media_url' => 'https://exemplo.com/oferta.png', 'media_type' => 'image')
    end
  end

  describe 'disparo' do
    let(:campaign) do
      campaign = create(:campaign, account: account, inbox: inbox, audience: [], message: 'Chegou a oferta do mês.',
                                   template_params: params({ 'media_url' => '', 'media_type' => 'image' }))
      CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, variable_bindings: {}, variable_defaults: {})
      campaign
    end

    def header_links(sent)
      sent.map do |body|
        header = Array(body.dig('template', 'components')).find { |component| component['type'] == 'header' }
        header&.dig('parameters', 0, 'image', 'link')
      end
    end

    it 'sem link na campanha: cada envio leva o arquivo do perfil do modelo' do
      save_profile_file
      sent = stub_graph_messages

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      links = header_links(sent)
      expect(links.size).to eq(2)
      expect(links).to all(start_with('http').and(include('oferta.png')))
      expect(campaign.reload).to be_completed
      expect(campaign.template_params.dig('processed_params', 'header', 'media_url')).to eq('')
    end

    it 'sem link e o arquivo sumiu do perfil: pausa com template_media_missing e não envia' do
      sent = stub_graph_messages

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(sent).to be_empty
      expect(CampaignPause.open_for(campaign)).to have_attributes(source: 'template', reason_code: 'template_media_missing')
    end

    it 'com link digitado: usa o link, sem olhar o perfil' do
      campaign.update!(template_params: params({ 'media_url' => 'https://exemplo.com/oferta.png', 'media_type' => 'image' }))
      sent = stub_graph_messages

      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform

      expect(header_links(sent)).to eq(['https://exemplo.com/oferta.png'] * 2)
    end
  end
end
