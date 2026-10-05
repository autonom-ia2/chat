require 'rails_helper'

# Atribuição de cliques de página (modo site do link, #1011).
RSpec.describe Ctwa::TrackedLinkAttributor do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, phone_number: '+15551234567', provider: 'whatsapp_cloud', validate_provider_config: false,
                              sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:tracked_link) do
    Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'LP Seguro Viagem', code: 'ABC234', usage: 'website',
                              allowed_origins: ['https://placement.com.br'])
  end
  let(:lead_fields) do
    [{ 'key' => 'destination', 'label' => 'Destino', 'value' => 'América do Norte - EUA' },
     { 'key' => 'ages', 'label' => 'Idades', 'value' => '72' }]
  end
  let(:campaign_params) do
    { 'utm_source' => 'meta', 'utm_medium' => 'paid', 'utm_campaign' => 'Viagem EUA', 'utm_term' => 'Conjunto 60+',
      'utm_content' => 'Video 2', 'utm_id' => '120211' }
  end

  def website_click(token:, params: campaign_params, lead_data: { 'fields' => lead_fields })
    create(:ctwa_tracked_link_click, account: account, tracked_link: tracked_link, token: token, params: params,
                                     campaign_key: Ctwa::TrackedLinkClick.campaign_key_for(params),
                                     page_url: 'https://placement.com.br/seguro-viagem', lead_data: lead_data)
  end

  def quote_message(token)
    "Quero cotar seguro viagem para EUA\nCódigo da cotação: ##{token}"
  end

  it 'liga a conversa ao clique com toque estável por campanha, campanha da Meta e formulário' do
    click = website_click(token: 'K7P2M9QX')

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))

    attrs = conversation.reload.additional_attributes
    expect(attrs['campaign']).to include(
      'source' => 'meta_paid',
      'source_id' => 'site:ABC234:120211',
      'source_type' => 'bridge',
      'headline' => 'LP Seguro Viagem · Viagem EUA',
      'source_url' => 'https://placement.com.br/seguro-viagem',
      'utm_campaign' => 'Viagem EUA',
      'utm_term' => 'Conjunto 60+',
      'utm_content' => 'Video 2',
      'utm_id' => '120211'
    )
    expect(attrs['campaign_touches'].sole).to include('source_id' => 'site:ABC234:120211', 'utm_id' => '120211', 'utm_term' => 'Conjunto 60+')
    expect(attrs['campaign_source_ids']).to eq(['site:ABC234:120211'])
    expect(attrs['lead_form']).to eq(
      'link_code' => 'ABC234',
      'fields' => lead_fields,
      'captured_at' => click.created_at.utc.iso8601
    )
    expect(click.reload.conversation_id).to eq(conversation.id)
    expect(tracked_link.reload.conversations_count).to eq(1)
  end

  it 'anúncio só com fbclid vira Meta pago com o nome da origem (CA-1.3)' do
    website_click(token: 'K7P2M9QX', params: { 'fbclid' => 'IwAR123' })

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))

    expect(conversation.reload.additional_attributes['campaign']).to include(
      'source' => 'meta_paid', 'source_id' => 'site:ABC234:none', 'headline' => 'LP Seguro Viagem'
    )
  end

  it 'acesso direto à página mostra só o nome da origem (CA-1.4)' do
    website_click(token: 'K7P2M9QX', params: {})

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))

    expect(conversation.reload.additional_attributes['campaign']).to include(
      'source' => 'tracked_link', 'source_id' => 'site:ABC234:none', 'headline' => 'LP Seguro Viagem'
    )
  end

  it 'dois cliques da mesma campanha na mesma conversa não duplicam toque nem contador (CA-1.10)' do
    website_click(token: 'K7P2M9QX')
    second = website_click(token: 'W3XY4Z5A')

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))
    described_class.attribute!(conversation, quote_message('W3XY4Z5A'))
    described_class.attribute!(conversation, quote_message('K7P2M9QX'))

    attrs = conversation.reload.additional_attributes
    expect(attrs['campaign_touches'].size).to eq(1)
    expect(second.reload.conversation_id).to eq(conversation.id)
    expect(tracked_link.reload.conversations_count).to eq(1)
  end

  it 'clique de outra campanha na mesma conversa vira outro toque, mas a conversa conta uma vez' do
    website_click(token: 'K7P2M9QX')
    website_click(token: 'W3XY4Z5A', params: { 'utm_campaign' => 'Europa' })

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))
    described_class.attribute!(conversation, quote_message('W3XY4Z5A'))

    touches = conversation.reload.additional_attributes['campaign_touches']
    expect(touches.pluck('source_id')).to eq(['site:ABC234:120211', "site:ABC234:c:#{Digest::SHA1.hexdigest('Europa')[0, 10]}"])
    expect(touches.last['headline']).to eq('LP Seguro Viagem · Europa')
    expect(tracked_link.reload.conversations_count).to eq(1)
  end

  it 'grava o formulário sem apagar as outras chaves da conversa' do
    conversation.update!(additional_attributes: { 'browser' => 'Safari', 'referer' => 'https://placement.com.br' })
    website_click(token: 'K7P2M9QX')

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))

    attrs = conversation.reload.additional_attributes
    expect(attrs).to include('browser' => 'Safari', 'referer' => 'https://placement.com.br')
    expect(attrs['lead_form']['fields']).to eq(lead_fields)
    expect(attrs['campaign']['source_id']).to eq('site:ABC234:120211')
  end

  it 'não grava lead_form quando o clique não tem formulário' do
    website_click(token: 'K7P2M9QX', lead_data: {})

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))

    attrs = conversation.reload.additional_attributes
    expect(attrs).not_to have_key('lead_form')
    expect(attrs['campaign']['source_id']).to eq('site:ABC234:120211')
  end

  it 'o formulário do clique mais recente substitui o anterior' do
    website_click(token: 'K7P2M9QX')
    new_fields = [{ 'key' => 'destination', 'label' => 'Destino', 'value' => 'Europa' }]
    website_click(token: 'W3XY4Z5A', lead_data: { 'fields' => new_fields })

    described_class.attribute!(conversation, quote_message('K7P2M9QX'))
    described_class.attribute!(conversation, quote_message('W3XY4Z5A'))

    expect(conversation.reload.additional_attributes['lead_form']['fields']).to eq(new_fields)
  end

  describe 'cliente apagou o código (CA-1.5)' do
    it 'infere quando há exatamente um clique da caixa nos últimos 10 minutos' do
      click = website_click(token: 'K7P2M9QX')

      described_class.attribute!(conversation, 'Quero cotar seguro viagem')

      attrs = conversation.reload.additional_attributes
      expect(attrs['campaign']).to include('source_id' => 'site:ABC234:120211', 'inferred' => true, 'source' => 'meta_paid')
      expect(click.reload.conversation_id).to eq(conversation.id)
    end

    # Quem clicou pode não ser quem escreveu: o formulário e os sinais da Meta do clique não
    # vão para o card nem para o CAPI (seriam de outra pessoa).
    it 'não grava o formulário e apaga os dados pessoais do clique inferido' do
      click = website_click(token: 'K7P2M9QX')
      click.update!(meta_signals: { 'fbc' => 'fb.1.1759650000000.IwAR123', 'client_ip_address' => '200.1.2.3' }, user_agent: 'iPhone')

      described_class.attribute!(conversation, 'Oi')

      expect(conversation.reload.additional_attributes).not_to have_key('lead_form')
      expect(click.reload).to have_attributes(conversation_id: conversation.id, lead_data: {}, meta_signals: {}, user_agent: nil)
      card = Struct.new(:id, :account_id, :conversation_id).new(0, account.id, conversation.id)
      expect(Crm::MetaCapi::WebsiteSignalResolver.resolve(card)).to eq({})
    end

    it 'não infere com dois cliques na janela' do
      website_click(token: 'K7P2M9QX')
      website_click(token: 'W3XY4Z5A')

      described_class.attribute!(conversation, 'Quero cotar seguro viagem')

      expect(conversation.reload.additional_attributes).to be_blank
      expect(Ctwa::TrackedLinkClick.where(conversation_id: conversation.id)).to be_empty
    end

    it 'não infere com clique de mais de 10 minutos' do
      travel_to(11.minutes.ago) { website_click(token: 'K7P2M9QX') }

      described_class.attribute!(conversation, 'Quero cotar seguro viagem')

      expect(conversation.reload.additional_attributes).to be_blank
    end
  end

  describe 'aviso que chega depois da mensagem' do
    def incoming(content, target = conversation)
      create(:message, account: account, inbox: target.inbox, conversation: target, message_type: :incoming, content: content)
    end

    it 'liga a conversa da mensagem que já trazia o #TOKEN, com formulário (Ctwa::LateClickReconcileJob)' do
      incoming(quote_message('K7P2M9QX'))
      click = website_click(token: 'K7P2M9QX')

      Ctwa::LateClickReconcileJob.perform_now(click.id)

      attrs = conversation.reload.additional_attributes
      expect(click.reload.conversation_id).to eq(conversation.id)
      expect(attrs['campaign']).to include('source_id' => 'site:ABC234:120211')
      expect(attrs['campaign']).not_to have_key('inferred')
      expect(attrs['lead_form']['fields']).to eq(lead_fields)
      expect(tracked_link.reload.conversations_count).to eq(1)
    end

    it 'não liga mensagem de outra caixa, mensagem enviada, nem token diferente' do
      other_inbox = create(:inbox, account: account)
      incoming(quote_message('K7P2M9QX'), create(:conversation, account: account, inbox: other_inbox))
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: quote_message('K7P2M9QX'))
      incoming(quote_message('W3XY4Z5A'))
      click = website_click(token: 'K7P2M9QX')

      Ctwa::LateClickReconcileJob.perform_now(click.id)

      expect(click.reload.conversation_id).to be_nil
      expect(conversation.reload.additional_attributes).not_to have_key('campaign')
    end

    it 'não faz nada quando a mensagem é mais antiga que a janela' do
      travel_to(11.minutes.ago) { incoming(quote_message('K7P2M9QX')) }
      click = website_click(token: 'K7P2M9QX')

      Ctwa::LateClickReconcileJob.perform_now(click.id)

      expect(click.reload.conversation_id).to be_nil
    end

    it 'não faz nada quando a mensagem é posterior à janela depois do clique' do
      click = website_click(token: 'K7P2M9QX')
      travel_to(click.created_at + 11.minutes) { incoming(quote_message('K7P2M9QX')) }

      Ctwa::LateClickReconcileJob.perform_now(click.id)

      expect(click.reload.conversation_id).to be_nil
    end

    it 'com duas conversas trazendo o token, liga a da primeira mensagem (a de quem clicou)' do
      forwarded = create(:conversation, account: account, inbox: inbox)
      travel_to(2.minutes.ago) { incoming(quote_message('K7P2M9QX')) }
      travel_to(1.minute.ago) { incoming(quote_message('K7P2M9QX'), forwarded) }
      click = website_click(token: 'K7P2M9QX')

      Ctwa::LateClickReconcileJob.perform_now(click.id)

      expect(click.reload.conversation_id).to eq(conversation.id)
    end

    # A busca por texto (LIKE) só pode rodar dentro da caixa, da janela e com LIMIT 1.
    it 'busca a mensagem só na caixa, só recebidas, numa janela fechada e com LIMIT 1' do
      click = website_click(token: 'K7P2M9QX')
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('LIKE') }

      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        Ctwa::LateClickReconcileJob.perform_now(click.id)
      end

      sql = queries.sole
      expect(sql).to include('FROM "messages"', '"messages"."inbox_id" = $', '"messages"."message_type" = $',
                             '"messages"."account_id" = $', '"messages"."created_at" BETWEEN $', 'LIMIT $')
      expect(sql).to end_with('ORDER BY "messages"."created_at" ASC LIMIT $7')
    end

    it 'não mexe em clique já atribuído' do
      click = website_click(token: 'K7P2M9QX')
      described_class.attribute!(conversation, quote_message('K7P2M9QX'))
      other = create(:conversation, account: account, inbox: inbox)
      incoming(quote_message('K7P2M9QX'), other)

      Ctwa::LateClickReconcileJob.perform_now(click.id)

      expect(click.reload.conversation_id).to eq(conversation.id)
    end
  end

  it 'link de QR (modo direto) continua com um toque por clique e sem formulário (CA-T.1)' do
    qr = Ctwa::TrackedLink.create!(account: account, inbox: inbox, name: 'QR Loja', code: 'XYZ789')
    create(:ctwa_tracked_link_click, account: account, tracked_link: qr, token: 'K7P2M9QX', params: { 'gclid' => 'g1' },
                                     lead_data: { 'fields' => lead_fields })

    described_class.attribute!(conversation, 'Oi #K7P2M9QX')

    attrs = conversation.reload.additional_attributes
    expect(attrs['campaign']).to include('source_id' => 'click:K7P2M9QX', 'headline' => 'QR Loja', 'source' => 'google_ads')
    expect(attrs['campaign']).not_to have_key('source_url')
    expect(attrs).not_to have_key('lead_form')
  end
end
