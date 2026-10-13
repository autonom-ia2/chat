require 'rails_helper'

RSpec.describe Whatsapp::Templates::SendableFormat do
  def template(*components)
    { 'name' => 'modelo', 'components' => components }
  end

  let(:body) { { 'type' => 'BODY', 'text' => 'Olá {{1}}' } }

  def buttons(*items)
    { 'type' => 'BUTTONS', 'buttons' => items }
  end

  describe '.check' do
    it 'accepts body, footer, text or media header and quick reply, link (fixed or variable) and call buttons' do
      %w[TEXT IMAGE VIDEO DOCUMENT].each do |format|
        result = described_class.check(template({ 'type' => 'HEADER', 'format' => format }, body, { 'type' => 'FOOTER', 'text' => 'Rodapé' },
                                                buttons({ 'type' => 'QUICK_REPLY', 'text' => 'Sim' },
                                                        { 'type' => 'URL', 'url' => 'https://a.com/{{1}}' },
                                                        { 'type' => 'URL', 'url' => 'https://a.com' },
                                                        { 'type' => 'PHONE_NUMBER', 'phone_number' => '+5511' })))

        expect(result).to be_sendable
        expect(result.warnings).to eq([])
      end
    end

    it 'keeps a Flow button sendable, with the flow_without_token warning' do
      result = described_class.check(template(body, buttons({ 'type' => 'FLOW', 'text' => 'Abrir' })))

      expect(result).to be_sendable
      expect(result.warnings).to eq(['flow_without_token'])
    end

    {
      'copy_code' => [{ 'type' => 'BODY', 'text' => 'x' }, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'COPY_CODE', 'example' => 'A1' }] }],
      'verification_code' => [{ 'type' => 'BODY', 'text' => 'x' },
                              { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'OTP', 'otp_type' => 'COPY_CODE' }] }],
      'carousel' => [{ 'type' => 'BODY', 'text' => 'x' }, { 'type' => 'CAROUSEL', 'cards' => [] }],
      'limited_time_offer' => [{ 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => 'Oferta', 'has_expiration' => true } },
                               { 'type' => 'BODY', 'text' => 'x' }],
      'catalog' => [{ 'type' => 'BODY', 'text' => 'x' }, { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'MPM', 'text' => 'Ver' }] }],
      'location_header' => [{ 'type' => 'HEADER', 'format' => 'LOCATION' }, { 'type' => 'BODY', 'text' => 'x' }],
      'call_permission_request' => [{ 'type' => 'BODY', 'text' => 'x' }, { 'type' => 'CALL_PERMISSION_REQUEST' }],
      'unsupported_component' => [{ 'type' => 'BODY', 'text' => 'x' }, { 'type' => 'SOMETHING_NEW' }]
    }.each do |code, components|
      it "refuses #{code} with its reason code" do
        result = described_class.check(template(*components))

        expect(result).not_to be_sendable
        expect(result.reason_code).to eq(code)
      end
    end

    it 'keeps a button type it does not know sendable, as today, with the unknown_button warning' do
      result = described_class.check(template(body, buttons({ 'type' => 'VOICE_CALL', 'text' => 'Ligar' })))

      expect(result).to be_sendable
      expect(result.warnings).to eq(['unknown_button'])
    end

    it 'accepts a copy-code button only when the send carries its code' do
      copy = template(body, buttons({ 'type' => 'QUICK_REPLY' }, { 'type' => 'COPY_CODE' }))

      expect(described_class.check(copy, recorded: { 'buttons' => [nil, { 'type' => 'copy_code', 'parameter' => 'A1' }] })).to be_sendable
      expect(described_class.check(copy, recorded: { 'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'A1' }] }).reason_code)
        .to eq('copy_code')
    end

    # #1334: the formats the campaign learned to send, each only when the send carries what Meta asks.
    describe 'what the send carries (recorded processed_params)' do
      let(:now) { Time.zone.parse('2026-10-13 12:00') }
      let(:offer) do
        template({ 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => 'Só hoje', 'has_expiration' => true } }, body,
                 buttons({ 'type' => 'URL', 'url' => 'https://a.com' }))
      end

      def check(template, recorded)
        described_class.check(template, recorded: recorded, now: now)
      end

      it 'accepts a limited-time offer with an expiration still ahead and refuses one without or already past' do
        ahead = (now + 1.day).to_i * 1000

        expect(check(offer, { 'limited_time_offer' => { 'expiration_time_ms' => ahead } })).to be_sendable
        expect(check(offer, {}).reason_code).to eq('limited_time_offer')
        expect(check(offer, { 'limited_time_offer' => { 'expiration_time_ms' => (now - 1.minute).to_i * 1000 } }).reason_code)
          .to eq('offer_expired')
      end

      it 'accepts an offer without expiration details with nothing recorded' do
        offer['components'].first['limited_time_offer']['has_expiration'] = false

        expect(check(offer, {})).to be_sendable
      end

      it 'accepts a carousel only with one recorded card per template card, each with its media (link or the saved file)' do
        card = { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' }, { 'type' => 'BODY', 'text' => 'x' }] }
        carousel = template(body, { 'type' => 'CAROUSEL', 'cards' => [card, card] })
        linked = { 'header' => { 'media_url' => 'https://a.com/1.png', 'media_type' => 'image' } }
        saved = { 'header' => { 'media_stored' => true, 'media_type' => 'image' } }
        chosen = { 'header' => { 'media_blob' => 'assinado', 'media_type' => 'image' } }

        expect(check(carousel, { 'carousel' => { 'cards' => [linked, saved] } })).to be_sendable
        expect(check(carousel, { 'carousel' => { 'cards' => [chosen, saved] } })).to be_sendable
        expect(check(carousel, { 'carousel' => { 'cards' => [linked] } }).reason_code).to eq('carousel')
        expect(check(carousel, { 'carousel' => { 'cards' => [linked, {}] } }).reason_code).to eq('carousel')
        expect(check(carousel, {}).reason_code).to eq('carousel')
      end

      it 'accepts a catalog button when the send marks it, and keeps multi and single product refused' do
        catalog = template(body, buttons({ 'type' => 'CATALOG', 'text' => 'Ver' }))

        expect(check(catalog, { 'buttons' => [{ 'type' => 'catalog' }] })).to be_sendable
        expect(check(catalog, {}).reason_code).to eq('catalog')
        expect(check(template(body, buttons({ 'type' => 'MPM' })), { 'buttons' => [{ 'type' => 'catalog' }] }).reason_code).to eq('catalog')
      end

      it 'drops the flow_without_token warning when the send carries the token' do
        flow = template(body, buttons({ 'type' => 'FLOW', 'text' => 'Abrir' }))

        expect(check(flow, { 'buttons' => [{ 'type' => 'flow', 'flow_token' => 'chat2you_campaign_1' }] }).warnings).to eq([])
      end

      it 'refuses a coupon longer than 15 characters (the send would drop every recipient)' do
        copy = template(body, buttons({ 'type' => 'COPY_CODE' }))

        expect(check(copy, { 'buttons' => [{ 'type' => 'copy_code', 'parameter' => 'A' * 16 }] }).reason_code).to eq('copy_code')
      end

      it 'refuses a carousel whose card text or link button has a variable without its value' do
        card = { 'components' => [{ 'type' => 'HEADER', 'format' => 'IMAGE' },
                                  { 'type' => 'BUTTONS', 'buttons' => [{ 'type' => 'URL', 'url' => 'https://a.com/{{1}}' }] }] }
        carousel = template(body, { 'type' => 'CAROUSEL', 'cards' => [card, card] })
        linked = { 'header' => { 'media_url' => 'https://a.com/1.png' } }
        with_value = linked.merge('buttons' => [{ 'type' => 'url', 'parameter' => 'x' }])

        expect(check(carousel, { 'carousel' => { 'cards' => [linked, linked] } }).reason_code).to eq('carousel')
        expect(check(carousel, { 'carousel' => { 'cards' => [with_value, with_value] } })).to be_sendable

        card['components'] << { 'type' => 'BODY', 'text' => 'Tênis {{1}}' }
        expect(check(carousel, { 'carousel' => { 'cards' => [with_value, with_value] } }).reason_code).to eq('carousel')
        filled = with_value.merge('body' => { '1' => 'azul' })
        expect(check(carousel, { 'carousel' => { 'cards' => [filled, filled] } })).to be_sendable
      end

      it 'keeps verification codes out of campaigns, whatever is recorded' do
        otp = template(body, buttons({ 'type' => 'OTP', 'otp_type' => 'COPY_CODE' }))

        expect(check(otp, { 'buttons' => [{ 'type' => 'copy_code', 'parameter' => '123456' }] }).reason_code).to eq('verification_code')
      end
    end

    it 'ignores entries that are not objects instead of breaking' do
      result = described_class.check({ 'components' => [nil, body, { 'type' => 'BUTTONS', 'buttons' => [nil, { 'type' => 'URL' }] }] })

      expect(result).to be_sendable
      expect(described_class.check('texto').reason_code).to eq('no_components')
    end

    it 'refuses a template without components' do
      expect(described_class.check({ 'name' => 'x' }).reason_code).to eq('no_components')
      expect(described_class.sendable?(nil)).to be(false)
    end

    it 'reads the structure, never the text: a body that mentions a code is still sendable' do
      expect(described_class.sendable?(template({ 'type' => 'BODY', 'text' => 'Use o cupom COPY_CODE e o carrossel' }))).to be(true)
    end
  end
end
