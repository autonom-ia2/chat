require 'rails_helper'

# #1702 — reação do atendente: provedor primeiro, gravação só depois do aceite.
describe ConversaCanal::ReacaoDoAtendente do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:colega) { create(:user, account: account, role: :agent) }

  def reagir(mensagem, emoji, user: agente)
    described_class.new(message: mensagem, user: user, emoji: emoji).perform
  end

  context 'with WhatsApp oficial (Cloud API)' do
    let(:canal) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).tap do |c|
        c.provider_config = { 'api_key' => 'chave', 'phone_number_id' => '123', 'business_account_id' => '777' }
        c.save!(validate: false)
      end
    end
    let(:caixa) { canal.inbox }
    let(:contato) { create(:contact, account: account, phone_number: '+5511937016094') }
    let(:contact_inbox) { create(:contact_inbox, inbox: caixa, contact: contato, source_id: '5511937016094') }
    let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato, contact_inbox: contact_inbox) }
    let!(:recebida) do
      create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, source_id: 'wamid.A')
    end

    before do
      stub_request(:post, 'https://graph.facebook.com/v24.0/123/messages')
        .to_return(status: 200, body: { messages: [{ id: 'wamid.R' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
    end

    it 'a reação de um atendente substitui a de outro (o número tem uma reação só)' do
      reagir(recebida, '👍', user: colega)
      reagir(recebida, '❤️')

      expect(recebida.reload.content_attributes['reactions']).to contain_exactly(include('emoji' => '❤️', 'sender_id' => agente.id))
    end

    it 'mantém a reação do cliente ao lado da do atendente' do
      recebida.update!(content_attributes: { 'reactions' => [{ 'emoji' => '🙏', 'sender_type' => 'Contact', 'sender_id' => contato.id }] })

      reagir(recebida, '👍')

      expect(recebida.reload.content_attributes['reactions'].pluck('emoji')).to eq(%w[🙏 👍])
    end

    it 'aceita emoji com modificador (um desenho só)' do
      expect { reagir(recebida, '👍🏽') }.not_to raise_error
    end

    it 'recusa letra, número, grafema inflado e emoji que não é texto, sem pedir à Meta' do
      ['A', '1', "a#{"\u0301" * 5000}", ['👍'], { 'e' => '👍' }, nil].each do |invalido|
        expect { reagir(recebida, invalido) }.to raise_error(described_class::Recusa)
      end
      expect(a_request(:post, 'https://graph.facebook.com/v24.0/123/messages')).not_to have_been_made
    end

    it 'recusa mensagem enviada pela empresa (a Meta só reage à do cliente)' do
      enviada = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, source_id: 'wamid.B')

      expect { reagir(enviada, '👍') }.to raise_error(described_class::Recusa)
    end

    it 'recusa mensagem sem wamid (ainda com o id físico do WhatsApp API)' do
      recebida.update!(source_id: '3EB0FISICO')

      expect { reagir(recebida, '👍') }.to raise_error(described_class::Recusa)
      expect(a_request(:post, 'https://graph.facebook.com/v24.0/123/messages')).not_to have_been_made
    end

    it 'recusa nota privada' do
      nota = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, private: true,
                              source_id: 'wamid.C')

      expect { reagir(nota, '👍') }.to raise_error(described_class::Recusa)
    end

    it 'recusa mensagem apagada pelo cliente, sem pedir à Meta' do
      recebida.update!(content_attributes: { 'deleted_by_contact_at' => Time.current.iso8601 })

      expect { reagir(recebida, '👍') }.to raise_error(described_class::Recusa)
      expect(a_request(:post, 'https://graph.facebook.com/v24.0/123/messages')).not_to have_been_made
    end

    it 'Meta responde sem JSON: recusa legível' do
      stub_request(:post, 'https://graph.facebook.com/v24.0/123/messages')
        .to_return(status: 502, body: '<html>Bad Gateway</html>', headers: { 'Content-Type' => 'application/json' })

      expect { reagir(recebida, '👍') }.to raise_error(described_class::Recusa)
      expect(recebida.reload.content_attributes).not_to have_key('reactions')
    end

    it 'Meta fora do ar: recusa legível, nada gravado' do
      stub_request(:post, 'https://graph.facebook.com/v24.0/123/messages').to_timeout

      expect { reagir(recebida, '👍') }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.reacoes.provedor_fora'))
      expect(recebida.reload.content_attributes).not_to have_key('reactions')
    end
  end

  context 'with caixa WhatsApp API (WAHA)' do
    let(:caixa) do
      create(:channel_api, account: account, additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-1' }).inbox
    end
    let(:contato) do
      create(:contact, account: account, phone_number: '+5511937016094',
                       custom_attributes: { 'waha_whatsapp_chat_id' => '5511937016094@c.us' })
    end
    let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato) }
    let(:client) { instance_double(Waha::Client, set_reaction: {}) }

    before { allow(Waha::Client).to receive(:new).and_return(client) }

    it 'monta o messageId do WAHA com o chat id e o lado da mensagem' do
      enviada = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, source_id: '3EB0AAAA')

      reagir(enviada, '😂')

      expect(client).to have_received(:set_reaction)
        .with(session: 'sessao-1', message_id: 'true_5511937016094@c.us_3EB0AAAA', reaction: '😂')
      expect(enviada.reload.content_attributes['reactions'].pluck('emoji')).to eq(['😂'])
    end

    it 'usa o source_id quando ele já está no formato do WAHA' do
      recebida = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming,
                                  source_id: 'false_5511937016094@c.us_3EB0BBBB')

      reagir(recebida, '')

      expect(client).to have_received(:set_reaction)
        .with(session: 'sessao-1', message_id: 'false_5511937016094@c.us_3EB0BBBB', reaction: '')
    end

    it 'recusa do WAHA: nada gravado' do
      allow(client).to receive(:set_reaction).and_raise(Waha::Client::Error.new('falhou', status: 500))
      recebida = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming,
                                  source_id: 'false_5511937016094@c.us_3EB0CCCC')

      expect { reagir(recebida, '👍') }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.reacoes.waha_recusou'))
      expect(recebida.reload.content_attributes).not_to have_key('reactions')
    end
  end

  # #1709: caixa WAHA comum com a flag e motor que declara a reação: vai pelo conector (MessageActions.react!), sem
  # PUT /api/reaction e sem o gravar do #1702; recusa do conector vira Recusa.
  context 'with caixa WAHA cujo motor declara a reação (whatsapp_rich_native)' do
    let(:engine) { 'https://waha.example' }
    let(:caixa) do
      create(:channel_api, account: account, webhook_url: "#{engine}/webhooks/chatwoot/abc",
                           additional_attributes: { 'provider' => 'waha', 'session' => 'sessao-1' }).inbox
    end
    let(:conversa) { create(:conversation, account: account, inbox: caixa) }
    let(:client) { instance_double(Waha::Client, set_reaction: {}) }
    let(:recebida) { create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, content: 'oi') }

    around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: "#{engine}/") { example.run } }

    before do
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(Waha::EngineCapabilities).to receive(:actions) { |url| url == "#{engine}/" ? %w[react edit] : [] }
      allow(Waha::RichNative::MessageActionDeliveryJob).to receive(:request!)
      account.enable_features!(Waha::RichNative::FLAG)
    end

    it 'grava a reação da empresa e pede o envio ao conector, sem source_id e sem o PUT /api/reaction' do
      resultado = reagir(recebida, '👍')

      expect(resultado.content_attributes['reactions']).to contain_exactly(include('emoji' => '👍', 'sender_type' => 'User'))
      expect(Waha::RichNative::MessageActionDeliveryJob).to have_received(:request!).with(recebida, 'c2y_message_reaction')
      expect(client).not_to have_received(:set_reaction)
    end

    it 'recusa do conector vira Recusa: mensagem que não se reage' do
      nota = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, private: true, content: 'n')

      expect { reagir(nota, '👍') }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.reacoes.mensagem_invalida'))
      expect(client).not_to have_received(:set_reaction)
    end

    it 'recusa emoji fora do formato antes do conector' do
      expect { reagir(recebida, 'A') }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.reacoes.emoji_invalido'))
      expect(Waha::RichNative::MessageActionDeliveryJob).not_to have_received(:request!)
    end

    it 'sem a flag: o caminho do #1702 (PUT /api/reaction no motor da caixa)' do
      account.disable_features!(Waha::RichNative::FLAG)
      contato = conversa.contact
      contato.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '5511937016094@c.us' })
      recebida.update!(source_id: 'false_5511937016094@c.us_3EB0DDDD')

      reagir(recebida, '👍')

      expect(client).to have_received(:set_reaction)
        .with(session: 'sessao-1', message_id: 'false_5511937016094@c.us_3EB0DDDD', reaction: '👍')
      expect(Waha::Client).to have_received(:new).with(config: have_attributes(api_url: engine))
    end
  end

  it 'recusa caixa que não é de WhatsApp' do
    caixa = create(:inbox, account: account)
    conversa = create(:conversation, account: account, inbox: caixa)
    mensagem = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, source_id: 'x')

    expect { reagir(mensagem, '👍') }.to raise_error(described_class::Recusa, I18n.t('conversa_canal.reacoes.caixa_sem_reacao'))
  end
end
