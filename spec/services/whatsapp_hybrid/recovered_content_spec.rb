require 'rails_helper'

# chat#1489: o texto da mensagem que o motor devolve. O formato é o do protobuf do WhatsApp em JSON (GOWS), com os
# `oneof` embrulhados em campos Go em maiúscula; o protojson (sem invólucro) também é lido.
describe WhatsappHybrid::RecoveredContent do
  def read(message, extra = {})
    described_class.from_payload({ 'id' => 'false_5511937016094@c.us_ABC', '_data' => { 'Message' => message } }.merge(extra))
  end

  let(:hydrated) do
    {
      'hydratedTitleText' => 'Oferta',
      'hydratedContentText' => 'Seu boleto vence amanhã.',
      'hydratedFooterText' => 'Banco Exemplo',
      'hydratedButtons' => [
        { 'index' => 0, 'HydratedButton' => { 'QuickReplyButton' => { 'displayText' => 'Já paguei', 'ID' => 'pago' } } },
        { 'index' => 1, 'HydratedButton' => { 'URLButton' => { 'displayText' => 'Ver boleto', 'URL' => 'https://exemplo.test/b' } } },
        { 'index' => 2, 'HydratedButton' => { 'CallButton' => { 'displayText' => 'Ligar', 'phoneNumber' => '+551130000000' } } }
      ]
    }
  end

  let(:expected_template) do
    "Oferta\n\nSeu boleto vence amanhã.\n\nBanco Exemplo\n\n" \
      "1. Já paguei\n2. Ver boleto: https://exemplo.test/b\n3. Ligar: +551130000000"
  end

  # Estrutura real de produção (15/10/2026, 2 mensagens do spike, só as chaves); valores inventados.
  describe 'formato real do motor' do
    def engine_payload(template_message)
      {
        'id' => 'false_5511937016094@c.us_3A0000000000000000', 'timestamp' => 1_760_000_000, 'from' => '5511937016094@c.us',
        'fromMe' => false, 'source' => 'app', 'body' => '', 'to' => '551142155355@c.us', 'participant' => nil,
        'hasMedia' => false, 'media' => nil, 'ack' => 1, 'location' => nil, 'vCards' => [], 'ackName' => 'SERVER',
        'replyTo' => nil,
        '_data' => { 'Info' => { 'Chat' => '5511937016094@s.whatsapp.net', 'IsFromMe' => false }, 'IsEdit' => false,
                     'RawMessage' => { 'templateMessage' => {} },
                     'Message' => { 'templateMessage' => template_message } }
      }
    end

    let(:image) { { 'ImageMessage' => { 'URL' => 'https://mmg.example/x', 'mimetype' => 'image/jpeg', 'JPEGThumbnail' => 'AAAA' } } }
    let(:context_info) { { 'quotedMessage' => { 'conversation' => 'não é desta mensagem' } } }

    it 'caso A: hydratedTemplate com imagem no Title e botões em HydratedButton (PascalCase)' do
      template = {
        'Format' => nil, 'contextInfo' => context_info, 'templateID' => '111',
        'hydratedTemplate' => {
          'Title' => image,
          'hydratedContentText' => 'Sua fatura de outubro está disponível.',
          'hydratedFooterText' => 'Empresa Exemplo S.A.',
          'hydratedButtons' => [
            { 'HydratedButton' => { 'CallButton' => { 'displayText' => 'Falar com a central', 'phoneNumber' => '+551140000000' } },
              'index' => 0 },
            { 'HydratedButton' => { 'QuickReplyButton' => { 'displayText' => 'Já paguei', 'ID' => 'pago' } }, 'index' => 1 },
            { 'HydratedButton' => { 'UrlButton' => { 'displayText' => 'Ver fatura', 'URL' => 'https://exemplo.test/f' } },
              'index' => 2 }
          ],
          'templateID' => '111'
        }
      }

      result = described_class.from_payload(engine_payload(template))

      expect(result.to_a).to eq([:text, "Sua fatura de outubro está disponível.\n\nEmpresa Exemplo S.A.\n\n" \
                                        "1. Falar com a central: +551140000000\n2. Já paguei\n3. Ver fatura: https://exemplo.test/f",
                                 :image])
    end

    it 'caso B: Format.InteractiveMessageTemplate com NativeFlowMessage e imagem no header.Media' do
      params = { display_text: 'Acessar oferta', url: 'https://exemplo.test/o', merchant_url: 'https://exemplo.test',
                 webview_presentation: nil }
      template = {
        'Format' => { 'InteractiveMessageTemplate' => {
          'InteractiveMessage' => { 'NativeFlowMessage' => {
            'buttons' => [{ 'name' => 'cta_url', 'buttonParamsJSON' => params.to_json },
                          { 'name' => 'cta_call', 'buttonParamsJSON' => { display_text: 'Ligar', phone_number: '+5511' }.to_json },
                          { 'name' => 'quebrado', 'buttonParamsJSON' => '{"display_text":' }],
            'messageParamsJSON' => '{}'
          } },
          'header' => { 'Media' => image, 'hasMediaAttachment' => true },
          'body' => { 'text' => 'Oferta especial para você neste mês.' },
          'footer' => { 'Media' => nil, 'text' => 'Loja Exemplo' }
        } },
        'contextInfo' => context_info, 'templateID' => '222'
      }

      result = described_class.from_payload(engine_payload(template))

      expect(result.to_a).to eq([:text, "Oferta especial para você neste mês.\n\nLoja Exemplo\n\n" \
                                        "1. Acessar oferta: https://exemplo.test/o\n2. Ligar: +5511",
                                 :image])
    end

    it 'modelo sem arquivo no cabeçalho não pede para olhar o celular' do
      template = { 'Format' => nil, 'hydratedTemplate' => { 'hydratedContentText' => 'Só texto' } }

      expect(described_class.from_payload(engine_payload(template)).header_media).to be_nil
    end
  end

  it 'lê o modelo hydratedTemplate: título, corpo, rodapé e botões numerados' do
    result = read('templateMessage' => { 'hydratedTemplate' => hydrated })

    expect(result.kind).to eq(:text)
    expect(result.text).to eq(expected_template)
  end

  it 'lê o hydratedFourRowTemplate dentro do invólucro de oneof do Go (Format)' do
    result = read('templateMessage' => { 'Format' => { 'HydratedFourRowTemplate' => hydrated } })

    expect(result.text).to eq(expected_template)
  end

  it 'lê o título que vem no oneof Title' do
    template = hydrated.except('hydratedTitleText').merge('Title' => { 'HydratedTitleText' => 'Oferta' })

    expect(read('templateMessage' => { 'hydratedTemplate' => template }).text).to eq(expected_template)
  end

  it 'lê o hydratedFourRowTemplate no formato protojson (sem invólucro)' do
    result = read('templateMessage' => { 'hydratedFourRowTemplate' => { 'hydratedContentText' => 'Olá' } })

    expect(result.text).to eq('Olá')
  end

  it 'lê o interactiveMessageTemplate com botões nativeFlow' do
    interactive = {
      'header' => { 'title' => 'Pedido 123' },
      'body' => { 'text' => 'Seu pedido saiu para entrega.' },
      'footer' => { 'text' => 'Loja Exemplo' },
      'InteractiveMessage' => {
        'NativeFlowMessage' => {
          'buttons' => [
            { 'name' => 'quick_reply', 'buttonParamsJSON' => { display_text: 'Ok', id: 'ok' }.to_json },
            { 'name' => 'cta_url', 'buttonParamsJSON' => { display_text: 'Rastrear', url: 'https://exemplo.test/r' }.to_json },
            { 'name' => 'quebrado', 'buttonParamsJSON' => '{nao e json' }
          ]
        }
      }
    }

    result = read('templateMessage' => { 'Format' => { 'InteractiveMessageTemplate' => interactive } })

    expect(result.text).to eq("Pedido 123\n\nSeu pedido saiu para entrega.\n\nLoja Exemplo\n\n1. Ok\n2. Rastrear: https://exemplo.test/r")
  end

  it 'não lê o texto citado (contextInfo) como se fosse da mensagem' do
    template = { 'hydratedTemplate' => { 'hydratedContentText' => 'Corpo' },
                 'contextInfo' => { 'quotedMessage' => { 'conversation' => 'texto citado' } } }

    expect(read('templateMessage' => template).text).to eq('Corpo')
  end

  it 'lê texto simples e texto estendido' do
    expect(read('conversation' => ' Oi, tudo bem? ').text).to eq('Oi, tudo bem?')
    expect(read('extendedTextMessage' => { 'text' => 'Veja https://exemplo.test' }).text).to eq('Veja https://exemplo.test')
  end

  it 'abre os invólucros (mensagem temporária, documento com legenda)' do
    expect(read('ephemeralMessage' => { 'message' => { 'conversation' => 'some em 24h' } }).text).to eq('some em 24h')

    result = read('documentWithCaptionMessage' => { 'message' => { 'documentMessage' => { 'caption' => 'Contrato' } } })
    expect([result.kind, result.text]).to eq([:media, 'Contrato'])
  end

  it 'marca mídia e guarda só a legenda' do
    expect(read('imageMessage' => { 'caption' => 'Foto do produto', 'mimetype' => 'image/jpeg' }).to_a).to eq([:media, 'Foto do produto', nil])
    expect(read('audioMessage' => { 'seconds' => 3 }).to_a).to eq([:media, nil, nil])
  end

  it 'devolve :empty quando não há nada legível' do
    expect(read('templateMessage' => { 'hydratedTemplate' => { 'hydratedButtons' => [] } }).kind).to eq(:empty)
    expect(read('protocolMessage' => { 'type' => 0 }).kind).to eq(:empty)
  end

  it 'sem _data, usa o body e o hasMedia do motor' do
    expect(described_class.from_payload('body' => 'Olá').to_a).to eq([:text, 'Olá', nil])
    expect(described_class.from_payload('body' => 'legenda', 'hasMedia' => true).to_a).to eq([:media, 'legenda', nil])
    expect(described_class.from_payload(nil).kind).to eq(:empty)
  end
end
