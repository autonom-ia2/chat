require 'rails_helper'

# Configuração do resumo no WhatsApp (#1100, F4b): número validado pela gem, origem só dentre os números conectados
# da conta, modelo aprovado no Oficial e desligar sempre funciona.
RSpec.describe Crm::MetaAds::WhatsappReport::Settings do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:waha) { instance_double(Waha::Client) }
  let(:waha_inbox) { create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'vendas' }).inbox }
  let(:approved) do
    [{ 'name' => 'chat2you_resumo_anuncios', 'language' => 'pt_BR', 'status' => 'APPROVED', 'namespace' => 'ns' },
     { 'name' => 'chat2you_alerta_anuncio', 'language' => 'pt_BR', 'status' => 'PENDING', 'namespace' => 'ns' }]
  end

  def cloud_inbox(templates: approved, owner: account)
    create(:channel_whatsapp, account: owner, provider: 'whatsapp_cloud', phone_number: "+55119888#{rand(10_000..99_999)}",
                              message_templates: templates, sync_templates: false, validate_provider_config: false).inbox
  end

  def settings
    described_class.new(connection.reload)
  end

  before do
    allow(Waha::Config).to receive(:enabled?).and_return(true)
    allow(Waha::Client).to receive(:new).and_return(waha)
    allow(waha).to receive(:get_session).with('vendas').and_return({ 'status' => 'WORKING', 'me' => { 'id' => '5511999990000@c.us' } })
  end

  it 'vem desligado, sem origem nem número' do
    payload = settings.payload

    expect(payload).to include(enabled: false, alert_enabled: false, inbox_id: nil, phone: nil, last_error: nil)
    expect(payload[:schedule]).to eq(summary_local_time: '08:00', alert_local_time: '16:30', time_zone: 'America/Sao_Paulo')
    expect(payload[:template_texts]['summary']).to include(name: 'chat2you_resumo_anuncios')
    expect(payload[:template_texts]['summary'][:body]).to include('{{4}}')
  end

  it 'grava o número em E.164 pela gem de telefone e liga o resumo numa origem WAHA conectada' do
    settings.update!('phone' => '(11) 98765-4321', 'inbox_id' => waha_inbox.id, 'enabled' => true)

    connection.reload
    expect(connection.whatsapp_report_phone).to eq('+5511987654321')
    expect(connection.whatsapp_report_settings).to include('enabled' => true, 'alert_enabled' => false, 'inbox_id' => waha_inbox.id)
    expect(settings.payload[:origins]).to contain_exactly(
      { inbox_id: waha_inbox.id, name: waha_inbox.name, phone_number: '+5511999990000', kind: 'waha', templates: nil }
    )
  end

  it 'recusa número que não é telefone' do
    expect { settings.update!('phone' => 'liga pra mim') }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('invalid_phone') }
  end

  it 'recusa origem que não está conectada, de outra conta ou que não é WhatsApp' do
    allow(waha).to receive(:get_session).with('vendas').and_return({ 'status' => 'SCAN_QR_CODE' })
    other = cloud_inbox(owner: create(:account))
    email = create(:inbox, account: account)

    [waha_inbox.id, other.id, email.id].each do |inbox_id|
      expect { settings.update!('inbox_id' => inbox_id) }
        .to raise_error(described_class::Error) { |error| expect(error.code).to eq('inbox_not_connected') }
    end
  end

  it 'Oficial com reautorização pendente não é origem' do
    inbox = cloud_inbox
    inbox.channel.prompt_reauthorization!

    expect(settings.origins.list.map { |origin| origin.inbox.id }).not_to include(inbox.id)
  ensure
    inbox&.channel&.reauthorized!
  end

  it 'ligar exige origem e número; desligar sempre funciona' do
    expect { settings.update!('enabled' => true) }.to raise_error(described_class::Error) { |error| expect(error.code).to eq('origin_required') }
    expect { settings.update!('alert_enabled' => true, 'inbox_id' => waha_inbox.id) }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('phone_required') }

    settings.update!('enabled' => false, 'alert_enabled' => false, 'inbox_id' => nil)

    expect(connection.reload.whatsapp_report_settings).to include('enabled' => false, 'alert_enabled' => false, 'inbox_id' => nil)
  end

  it 'desligar um dos dois passa mesmo com a origem desconectada' do
    settings.update!('phone' => '+5511987654321', 'inbox_id' => waha_inbox.id, 'enabled' => true, 'alert_enabled' => true)
    allow(waha).to receive(:get_session).with('vendas').and_return({ 'status' => 'STOPPED' })

    settings.update!('enabled' => false)

    expect(connection.reload.whatsapp_report_settings).to include('enabled' => false, 'alert_enabled' => true, 'inbox_id' => waha_inbox.id)
    expect { settings.update!('enabled' => true) }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('inbox_not_connected') }
  end

  it 'o envio grava só o status, sem desfazer o que a pessoa mudou enquanto ele rodava' do
    settings.update!('phone' => '+5511987654321', 'inbox_id' => waha_inbox.id, 'enabled' => true)
    sending = settings # o envio carregou a conexão com o resumo ligado
    described_class.new(Crm::MetaAdsConnection.find(connection.id)).update!('enabled' => false)

    travel_to(Time.zone.parse('2026-10-07T11:00:08Z')) { sending.record_sent!('summary') }

    expect(connection.reload.whatsapp_report_settings)
      .to include('enabled' => false, 'inbox_id' => waha_inbox.id, 'last_summary_at' => '2026-10-07T11:00:08Z')
  end

  it 'no Oficial liga só o tipo com o modelo aprovado e mostra o status dos dois' do
    inbox = cloud_inbox
    settings.update!('phone' => '+5511987654321', 'inbox_id' => inbox.id, 'enabled' => true)

    expect { settings.update!('alert_enabled' => true) }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('template_not_approved') }
    expect(connection.reload.whatsapp_report_settings['alert_enabled']).to be(false)
    origin = settings.payload[:origins].find { |row| row[:inbox_id] == inbox.id }
    expect(origin).to include(kind: 'whatsapp_cloud', templates: { 'summary' => 'approved', 'alert' => 'pending' })
  end

  it 'modelo com outro nome ou outro idioma conta como ausente' do
    inbox = cloud_inbox(templates: [{ 'name' => 'chat2you_resumo_anuncios', 'language' => 'en', 'status' => 'APPROVED' }])

    expect { settings.update!('phone' => '+5511987654321', 'inbox_id' => inbox.id, 'enabled' => true) }
      .to raise_error(described_class::Error) { |error| expect(error.code).to eq('template_not_approved') }
    expect(Crm::MetaAds::WhatsappReport::TemplateStatus.for(inbox.channel)).to eq('summary' => 'missing', 'alert' => 'missing')
  end

  it 'motor do WAHA fora do ar: o número não aparece como origem' do
    allow(waha).to receive(:get_session).with('vendas').and_raise(Waha::Client::Error, 'WAHA GET /api/sessions/vendas falhou')
    waha_inbox

    expect(settings.origins.list).to be_empty
  end

  it 'registra envio e erro no jsonb' do
    travel_to(Time.zone.parse('2026-10-07T11:00:00Z')) do
      settings.record_error!('send_failed')
      expect(connection.reload.whatsapp_report_settings).to include('last_error' => 'send_failed', 'last_error_at' => '2026-10-07T11:00:00Z')

      settings.record_sent!('summary')
      expect(connection.reload.whatsapp_report_settings).to include('last_summary_at' => '2026-10-07T11:00:00Z', 'last_error' => nil)
    end
  end
end
