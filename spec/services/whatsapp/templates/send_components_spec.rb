require 'rails_helper'

# #1334: the send carries what Meta asks for the new formats (offer expiration, carousel cards, Flow token, catalog
# button). Fonte oficial, lida em 13/10/2026: developers.facebook.com/documentation/business-messaging/whatsapp/
# templates/marketing-templates/{limited-time-offer-templates,media-card-carousel-templates,coupon-templates} e
# catalogs/catalog-template-messages; Flow: developers.facebook.com/docs/whatsapp/flows/guides/sendingaflow.
RSpec.describe Whatsapp::Templates::SendComponents do
  subject(:components) { Whatsapp::TemplateProcessorService.new(channel: channel, template_params: params).call.last }

  let(:channel) { instance_double(Channel::Whatsapp, message_templates: [template]) }
  let(:params) { { 'name' => template['name'], 'language' => 'pt_BR', 'processed_params' => processed } }

  def approved(name, *components)
    { 'name' => name, 'language' => 'pt_BR', 'status' => 'APPROVED', 'parameter_format' => 'POSITIONAL', 'components' => components }
  end

  it 'is prepended into the Chatwoot template processor by the initializer' do
    expect(Whatsapp::TemplateProcessorService.ancestors.first(3)).to include(described_class)
  end

  describe 'a send without the new keys (conversation, legacy dialog, journey today)' do
    let(:template) do
      approved('rico', { 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'Oi {{1}}' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://a.com/{{1}}' },
                                                    { 'type' => 'COPY_CODE', 'example' => 'ABC' },
                                                    { 'type' => 'FLOW', 'text' => 'Abrir' }] })
    end
    let(:processed) do
      { 'header' => { 'media_url' => 'https://a.com/f.png', 'media_type' => 'image' }, 'body' => { '1' => 'Ana' },
        'buttons' => [{ 'type' => 'url', 'parameter' => 'x1' }, { 'type' => 'copy_code', 'parameter' => 'ABC' }] }
    end

    it 'builds exactly the payload it built before #1334' do
      expect(components).to eq(
        [{ type: 'header', parameters: [{ type: 'image', image: { link: 'https://a.com/f.png' } }] },
         { type: 'body', parameters: [{ type: 'text', text: 'Ana' }] },
         { type: 'button', sub_type: 'url', index: 0, parameters: [{ type: 'text', text: 'x1' }] },
         { type: 'button', sub_type: 'copy_code', index: 1, parameters: [{ type: 'coupon_code', coupon_code: 'ABC' }] }]
      )
    end
  end

  describe 'limited-time offer' do
    let(:template) do
      approved('oferta', { 'type' => 'HEADER', 'format' => 'IMAGE' },
               { 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => 'Só hoje', 'has_expiration' => true } },
               { 'type' => 'BODY', 'text' => 'Oi {{1}}' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'example' => 'CUPOM10' },
                                                    { 'type' => 'URL', 'url' => 'https://a.com' }] })
    end
    let(:processed) do
      { 'header' => { 'media_url' => 'https://a.com/f.png', 'media_type' => 'image' }, 'body' => { '1' => 'Ana' },
        'limited_time_offer' => { 'expiration_time_ms' => 1_798_761_600_000 },
        'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'CUPOM10' }] }
    end

    it 'sends the expiration (Unix time in milliseconds) after the body, in the order of Meta example' do
      expect(components.pluck(:type)).to eq(%w[header body limited_time_offer button])
      expect(components[2]).to eq(
        type: 'limited_time_offer',
        parameters: [{ type: 'limited_time_offer', limited_time_offer: { expiration_time_ms: 1_798_761_600_000 } }]
      )
      expect(components[3]).to eq(type: 'button', sub_type: 'copy_code', index: 0,
                                  parameters: [{ type: 'coupon_code', coupon_code: 'CUPOM10' }])
    end

    it 'sends no offer component when the campaign recorded no expiration (template without has_expiration)' do
      processed.delete('limited_time_offer')

      expect(components.pluck(:type)).to eq(%w[header body button])
    end
  end

  describe 'media card carousel' do
    let(:card) do
      lambda do |text|
        { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => text },
                           { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Quero' },
                                                                { 'type' => 'URL', 'url' => 'https://a.com/{{1}}' }] }] }
      end
    end
    let(:template) do
      approved('vitrine', { 'type' => 'BODY', 'text' => 'Oi {{1}}, veja:' },
               { 'type' => 'CAROUSEL', 'cards' => [card.call('Tênis {{1}}'), card.call('Bolsa')] })
    end
    let(:processed) do
      { 'body' => { '1' => 'Ana' },
        'carousel' => { 'cards' => [
          { 'header' => { 'media_url' => 'https://a.com/1.png', 'media_type' => 'image' }, 'body' => { '1' => 'azul' },
            'buttons' => [{ 'type' => 'quick_reply', 'payload' => 'tenis' }, { 'type' => 'url', 'parameter' => 'tenis' }] },
          { 'header' => { 'media_url' => 'https://a.com/2.png', 'media_type' => 'image' },
            'buttons' => [nil, { 'type' => 'url', 'parameter' => 'bolsa' }] }
        ] } }
    end

    it 'sends one card per template card, with its index, media, variables and button parameters' do
      expect(components.pluck(:type)).to eq(%w[body carousel])
      expect(components.last).to eq(
        type: 'carousel',
        cards: [
          { card_index: 0, components: [
            { type: 'header', parameters: [{ type: 'image', image: { link: 'https://a.com/1.png' } }] },
            { type: 'body', parameters: [{ type: 'text', text: 'azul' }] },
            { type: 'button', sub_type: 'quick_reply', index: 0, parameters: [{ type: 'payload', payload: 'tenis' }] },
            { type: 'button', sub_type: 'url', index: 1, parameters: [{ type: 'text', text: 'tenis' }] }
          ] },
          { card_index: 1, components: [
            { type: 'header', parameters: [{ type: 'image', image: { link: 'https://a.com/2.png' } }] },
            { type: 'button', sub_type: 'url', index: 1, parameters: [{ type: 'text', text: 'bolsa' }] }
          ] }
        ]
      )
    end

    it 'reads a processed_params with only the carousel as the parts format, not as legacy body values' do
      processed.delete('body')

      expect(components.pluck(:type)).to eq(%w[carousel])
    end
  end

  describe 'keys the template does not have' do
    let(:template) do
      approved('comum', { 'type' => 'BODY', 'text' => 'Oi {{1}}' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'QUICK_REPLY', 'text' => 'Sim' }] })
    end
    let(:processed) do
      { 'body' => { '1' => 'Ana' }, 'limited_time_offer' => { 'expiration_time_ms' => 1 }, 'carousel' => { 'cards' => [{}] },
        'buttons' => [{ 'type' => 'flow', 'flow_token' => 't' }] }
    end

    it 'never reach Meta: offer, carousel and Flow go only where the template has them' do
      expect(components).to eq([{ type: 'body', parameters: [{ type: 'text', text: 'Ana' }] }])
    end
  end

  # #1473: o botão de resposta rápida no topo leva um payload estável; a Meta devolve o payload, não o texto do botão.
  # Fonte oficial, lida em 14/10/2026: .../templates/marketing-templates/media-card-carousel-templates (botão
  # sub_type quick_reply, parameters [{ type: 'payload', payload }], devolvido em messages.button.payload no webhook).
  describe 'quick reply button with payload' do
    let(:template) do
      approved('aviso', { 'type' => 'BODY', 'text' => 'Oi {{1}}' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://a.com/{{1}}' },
                                                    { 'type' => 'QUICK_REPLY', 'text' => 'Não quero mais avisos' }] })
    end
    let(:processed) do
      { 'body' => { '1' => 'Ana' },
        'buttons' => [{ 'type' => 'url', 'parameter' => 'abc123' }, { 'type' => 'quick_reply', 'payload' => 'stop_notices' }] }
    end

    it 'sends the URL parameter once and the payload on the quick reply button' do
      expect(components).to eq(
        [{ type: 'body', parameters: [{ type: 'text', text: 'Ana' }] },
         { type: 'button', sub_type: 'url', index: 0, parameters: [{ type: 'text', text: 'abc123' }] },
         { type: 'button', sub_type: 'quick_reply', index: 1, parameters: [{ type: 'payload', payload: 'stop_notices' }] }]
      )
    end

    it 'sends a lone quick reply, with nil in the positions that carry nothing' do
      processed['buttons'] = [nil, { 'type' => 'quick_reply', 'payload' => 'stop_notices' }]

      expect(components).to eq(
        [{ type: 'body', parameters: [{ type: 'text', text: 'Ana' }] },
         { type: 'button', sub_type: 'quick_reply', index: 1, parameters: [{ type: 'payload', payload: 'stop_notices' }] }]
      )
    end

    it 'sends a lone quick reply with only buttons in processed_params' do
      processed.replace('buttons' => [{ 'type' => 'static' }, { 'type' => 'quick_reply', 'payload' => 'stop_notices' }])

      expect(components).to eq(
        [{ type: 'button', sub_type: 'quick_reply', index: 1, parameters: [{ type: 'payload', payload: 'stop_notices' }] }]
      )
    end

    it 'sends no quick reply component when the payload is empty' do
      processed['buttons'][1] = { 'type' => 'quick_reply', 'payload' => ' ' }

      expect(components.pluck(:sub_type).compact).to eq(%w[url])
    end

    it 'sends no quick reply component where the template has no QUICK_REPLY button' do
      processed['buttons'] = [{ 'type' => 'quick_reply', 'payload' => 'stop_notices' }]

      expect(components).to eq([{ type: 'body', parameters: [{ type: 'text', text: 'Ana' }] }])
    end

    it 'leaves a quick reply with parameter to the Chatwoot send, without a second component' do
      processed['buttons'][1] = { 'type' => 'quick_reply', 'parameter' => 'p', 'payload' => 'stop_notices' }

      expect(components.select { |component| component[:sub_type] == 'quick_reply' }).to eq(
        [{ type: 'button', sub_type: 'quick_reply', index: 1, parameters: [{ type: 'text', text: 'p' }] }]
      )
    end
  end

  describe 'a campaign send without the new keys (static placeholder on the QUICK_REPLY button)' do
    let(:template) do
      approved('campanha', { 'type' => 'BODY', 'text' => 'Oi {{1}}' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://a.com/{{1}}' },
                                                    { 'type' => 'QUICK_REPLY', 'text' => 'Sair' }] })
    end
    let(:processed) do
      { 'body' => { '1' => 'Ana' }, 'buttons' => [{ 'type' => 'url', 'parameter' => 'x1' }, { 'type' => 'static' }] }
    end

    it 'builds exactly the payload it built before #1473' do
      expect(components).to eq(
        [{ type: 'body', parameters: [{ type: 'text', text: 'Ana' }] },
         { type: 'button', sub_type: 'url', index: 0, parameters: [{ type: 'text', text: 'x1' }] }]
      )
    end
  end

  describe 'Flow and catalog buttons' do
    let(:template) do
      approved('form', { 'type' => 'BODY', 'text' => 'Responda' },
               { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'FLOW', 'text' => 'Abrir', 'flow_id' => '1' }] })
    end
    let(:processed) { { 'buttons' => [{ 'type' => 'flow', 'flow_token' => 'chat2you_campaign_7' }] } }

    it 'sends the flow_token of the campaign on the Flow button' do
      expect(components.last).to eq(type: 'button', sub_type: 'flow', index: 0,
                                    parameters: [{ type: 'action', action: { flow_token: 'chat2you_campaign_7' } }])
    end

    context 'with a catalog button' do
      let(:template) do
        approved('loja', { 'type' => 'BODY', 'text' => 'Veja a loja' },
                 { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'CATALOG', 'text' => 'Ver catálogo' }] })
      end
      let(:processed) { { 'buttons' => [{ 'type' => 'catalog' }] } }

      it 'sends the catalog button without parameters (Meta shows the first item of the catalog)' do
        expect(components.last).to eq(type: 'button', sub_type: 'catalog', index: 0)
      end

      it 'sends the chosen thumbnail item when the campaign has one' do
        processed['buttons'] = [{ 'type' => 'catalog', 'thumbnail_product_retailer_id' => 'sku-9' }]

        expect(components.last).to eq(type: 'button', sub_type: 'catalog', index: 0,
                                      parameters: [{ type: 'action', action: { thumbnail_product_retailer_id: 'sku-9' } }])
      end
    end
  end
end
