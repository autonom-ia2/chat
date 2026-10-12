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
      'limited_time_offer' => [{ 'type' => 'LIMITED_TIME_OFFER', 'limited_time_offer' => { 'text' => 'Oferta' } },
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

      expect(described_class.check(copy, coupon_codes: [1])).to be_sendable
      expect(described_class.check(copy, coupon_codes: [0]).reason_code).to eq('copy_code')
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
