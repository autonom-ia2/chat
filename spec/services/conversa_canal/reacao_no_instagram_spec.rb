require 'rails_helper'

# #2113 — reação do atendente no Instagram: sender_action react/unreact na API do Instagram, gravada só depois do aceite.
describe ConversaCanal::ReacaoNoInstagram do
  let(:account) { create(:account) }
  let(:agente) { create(:user, account: account, role: :agent) }
  let(:canal) { create(:channel_instagram, account: account, instagram_id: 'ig-business-1') }
  let(:caixa) { canal.inbox }
  let(:contato) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, inbox: caixa, contact: contato, source_id: 'ig-customer-1') }
  let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato, contact_inbox: contact_inbox) }
  let!(:recebida) do
    create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming, source_id: 'mid.DOCLIENTE')
  end
  let(:url) { 'https://graph.instagram.com/v22.0/ig-business-1/messages' }

  def reagir(mensagem, emoji)
    ConversaCanal::ReacaoDoAtendente.new(message: mensagem, user: agente, emoji: emoji).perform
  end

  def resposta(status: 200, body: { recipient_id: 'ig-customer-1' })
    stub_request(:post, url).with(query: { access_token: canal[:access_token] })
                            .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  it 'manda react com o emoji no formato da doc e grava com o atendente' do
    pedido = resposta.with(body: { recipient: { id: 'ig-customer-1' }, sender_action: 'react',
                                   payload: { message_id: 'mid.DOCLIENTE', reaction: '❤️' } }.to_json)

    reagir(recebida, '❤️')

    expect(pedido).to have_been_requested
    expect(recebida.reload.content_attributes['reactions'])
      .to contain_exactly(include('emoji' => '❤️', 'sender_type' => 'User', 'sender_id' => agente.id))
  end

  it 'emoji vazio manda unreact só com o message_id e tira a reação' do
    recebida.update!(content_attributes: { 'reactions' => [{ 'emoji' => '❤️', 'sender_type' => 'User', 'sender_id' => agente.id }] })
    pedido = resposta.with(body: { recipient: { id: 'ig-customer-1' }, sender_action: 'unreact',
                                   payload: { message_id: 'mid.DOCLIENTE' } }.to_json)

    reagir(recebida, '')

    expect(pedido).to have_been_requested
    expect(recebida.reload.content_attributes).not_to have_key('reactions')
  end

  it 'Meta recusa: frase do Instagram e nada gravado' do
    resposta(status: 400, body: { error: { message: 'Invalid message', code: 100 } })

    expect { reagir(recebida, '❤️') }
      .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa,
                      I18n.t('conversa_canal.reacoes.instagram.provedor_recusou', motivo: 'Invalid message'))
    expect(recebida.reload.content_attributes).not_to have_key('reactions')
  end

  it 'token inválido (190): marca a caixa para reconectar' do
    resposta(status: 400, body: { error: { message: 'Expired', code: 190 } })

    expect { reagir(recebida, '❤️') }.to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa)
    expect(canal.reauthorization_required?).to be(true)
  end

  it 'Meta fora do ar: recusa legível, nada gravado' do
    stub_request(:post, url).with(query: hash_including({})).to_timeout

    expect { reagir(recebida, '❤️') }
      .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t('conversa_canal.reacoes.instagram.provedor_fora'))
    expect(recebida.reload.content_attributes).not_to have_key('reactions')
  end

  it 'recusa mensagem enviada pela empresa, sem pedir à Meta' do
    enviada = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, source_id: 'mid.NOSSA')

    expect { reagir(enviada, '❤️') }
      .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t('conversa_canal.reacoes.instagram.so_recebida'))
    expect(a_request(:post, url).with(query: hash_including({}))).not_to have_been_made
  end

  it 'recusa mensagem sem mid, com a frase do Instagram' do
    recebida.update!(source_id: nil)

    expect { reagir(recebida, '❤️') }
      .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t('conversa_canal.reacoes.instagram.sem_identificacao'))
  end

  it 'recusa fora da janela de conversa, sem pedir à Meta' do
    recebida.update!(created_at: 3.days.ago)

    expect { reagir(recebida, '❤️') }
      .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t('conversa_canal.reacoes.instagram.fora_da_janela'))
    expect(a_request(:post, url).with(query: hash_including({}))).not_to have_been_made
  end

  it 'com a janela de 7 dias do HUMAN_AGENT ligada, a reação fica nas 24 h (o pedido vai sem a tag)' do
    recebida.update!(created_at: 30.hours.ago)

    with_modified_env ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT: 'true' do
      expect(Conversations::MessageWindowService.new(conversa).can_reply?).to be(true)
      expect { reagir(recebida, '❤️') }
        .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t('conversa_canal.reacoes.instagram.fora_da_janela'))
    end
    expect(a_request(:post, url).with(query: hash_including({}))).not_to have_been_made
  end

  it 'recusa a linha que o agente da Autonomia criou para a reação do cliente, sem pedir à Meta' do
    sintetica = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :incoming,
                                 source_id: 'ig_reaction:mid.NOSSA:1792000000000',
                                 content_attributes: { autonomia_reaction: { emoji: '❤️', reacted_source_id: 'mid.NOSSA' } })

    expect { reagir(sintetica, '👍') }
      .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t('conversa_canal.reacoes.mensagem_invalida'))
    expect(a_request(:post, url).with(query: hash_including({}))).not_to have_been_made
  end

  it 'conexão derrubada pela Meta: recusa legível, nada gravado' do
    stub_request(:post, url).with(query: hash_including({})).to_raise(Errno::ECONNRESET)

    expect { reagir(recebida, '❤️') }
      .to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa, I18n.t('conversa_canal.reacoes.instagram.provedor_fora'))
    expect(recebida.reload.content_attributes).not_to have_key('reactions')
  end

  it 'recusa emoji inválido e nota privada (as regras de sempre)' do
    nota = create(:message, account: account, inbox: caixa, conversation: conversa, message_type: :outgoing, private: true,
                            source_id: 'mid.NOTA')

    expect { reagir(recebida, 'A') }.to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa)
    expect { reagir(nota, '❤️') }.to raise_error(ConversaCanal::ReacaoDoAtendente::Recusa)
    expect(a_request(:post, url).with(query: hash_including({}))).not_to have_been_made
  end
end
