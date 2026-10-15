require 'rails_helper'

# chat#1489: uma tentativa de recuperar a bolha "não suportada" pelo motor. Só preenche com certeza; qualquer condição
# do casamento que falte deixa o aviso. A IA é chamada uma vez se a recuperação chegar em até 2 minutos.
describe WhatsappHybrid::UnsupportedRecovery do
  include_context 'with a pending unsupported hybrid message'

  let(:reply_job) { Autonomia::Agents::Operate::ReplyJob }

  def attempt!
    described_class.new(message).attempt!
  end

  def attributes
    message.reload.content_attributes
  end

  describe 'recuperada' do
    it 'põe o texto do modelo na própria mensagem, tira o aviso e chama a IA uma vez' do
      stub_engine

      expect { expect(attempt!).to eq(:done) }.to have_enqueued_job(reply_job).with(conversation.id, message.id).exactly(:once)

      expect(message.reload.content).to eq("#{template_body}\n\n1. Já paguei")
      expect(attributes).not_to have_key('is_unsupported')
      expect(attributes).to include('hybrid_recovery' => 'recovered', 'recovered_via' => 'web', 'whatsapp_web_id' => web_id,
                                    'unsupported_error_code' => 131_060)
    end

    it 'modelo com imagem no cabeçalho: o texto vai ao content e a marca da imagem vai aos atributos (a bolha avisa)' do
      template = { 'Format' => nil, 'hydratedTemplate' => {
        'Title' => { 'ImageMessage' => { 'mimetype' => 'image/jpeg' } }, 'hydratedContentText' => template_body
      } }
      stub_engine(engine_message('_data' => { 'Message' => { 'templateMessage' => template } }))

      attempt!

      expect(message.reload.content).to eq(template_body)
      expect(attributes).to include('hybrid_recovery' => 'recovered', 'hybrid_recovery_header' => 'image')
    end

    it 'sem arquivo no cabeçalho, não grava a marca' do
      stub_engine

      attempt!

      expect(attributes).not_to have_key('hybrid_recovery_header')
    end

    it 'a mesma mensagem devolvida por dois chats do contato conta uma vez' do
      contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '551137016094@c.us' })
      stub_engine
      stub_request(:get, "https://waha.test/api/hybrid-test/chats/551137016094@c.us/messages/#{web_id}?downloadMedia=false")
        .to_return(status: 200, body: engine_message.to_json, headers: { 'Content-Type' => 'application/json' })

      attempt!

      expect(attributes['hybrid_recovery']).to eq('recovered')
    end

    it 'mantém a posição e o horário da mensagem' do
      created_at = message.created_at
      stub_engine

      expect { attempt! }.not_to(change { conversation.messages.count })
      expect(message.reload.created_at).to eq(created_at)
    end

    it 'avisa a tela pelo message_updated normal' do
      stub_engine
      allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

      attempt!

      expect(Rails.configuration.dispatcher).to have_received(:dispatch).with('message.updated', anything, hash_including(message: message))
    end

    it 'é idempotente: a segunda tentativa não muda nada nem chama a IA de novo' do
      stub_engine
      attempt!
      message.reload

      expect { expect(attempt!).to eq(:done) }.not_to have_enqueued_job(reply_job)
      expect(message.reload.content).to eq("#{template_body}\n\n1. Já paguei")
    end

    it 'depois de 2 minutos recupera, mas não chama a IA' do
      stub_engine

      travel_to(message.created_at + 2.minutes + 1.second) do
        expect { attempt! }.not_to have_enqueued_job(reply_job)
      end
      expect(attributes['hybrid_recovery']).to eq('recovered')
    end

    it 'grava sobre o registro relido sob trava: não apaga chave escrita por outro processo' do
      stale = Message.find(message.id)
      written = message.content_attributes.to_h.merge('translations' => { 'en' => 'x' })
      message.update_columns(content_attributes: written) # rubocop:disable Rails/SkipsModelValidations
      stub_engine

      described_class.new(stale).attempt!

      expect(attributes).to include('translations' => { 'en' => 'x' }, 'hybrid_recovery' => 'recovered')
    end
  end

  describe 'ainda não dá (tenta de novo)' do
    it 'motor sem a mensagem (404)' do
      stub_engine({ message: 'not found' }, status: 404)

      expect(attempt!).to eq(:retry)
      expect(attributes['hybrid_recovery']).to eq('pending')
    end

    it 'motor com erro ou sem resposta' do
      stub_engine({ error: 'x' }, status: 500)
      expect(attempt!).to eq(:retry)

      stub_request(:get, engine_url).to_timeout
      expect(attempt!).to eq(:retry)
      expect(attributes['hybrid_recovery']).to eq('pending')
    end

    it 'conexão desconectada agora: nem pergunta ao motor' do
      connection.update!(status: 'disconnected')

      expect(attempt!).to eq(:retry)
      expect(a_request(:get, engine_url)).not_to have_been_made
    end
  end

  describe 'casamento que falha mantém o aviso' do
    shared_examples 'keeps the notice' do |reason|
      it "falha com #{reason} e não chama a IA" do
        expect { expect(attempt!).to eq(:done) }.not_to have_enqueued_job(reply_job)

        expect(message.reload.content).to eq(placeholder)
        expect(attributes).to include('is_unsupported' => true, 'hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => reason)
      end
    end

    context 'when the id differs' do
      before { stub_engine(engine_message('id' => 'false_5511937016094@c.us_OUTRO')) }

      it_behaves_like 'keeps the notice', 'mismatch'
    end

    context 'when the message is fromMe' do
      before { stub_engine(engine_message('fromMe' => true)) }

      it_behaves_like 'keeps the notice', 'mismatch'
    end

    context 'when fromMe is missing' do
      before { stub_engine(engine_message.except('fromMe')) }

      it_behaves_like 'keeps the notice', 'mismatch'
    end

    context 'when the sender is not the contact' do
      before { stub_engine(engine_message('from' => '5511999990000@c.us')) }

      it_behaves_like 'keeps the notice', 'mismatch'
    end

    context 'when the sender is a group' do
      before { stub_engine(engine_message('from' => '120363000000000000@g.us')) }

      it_behaves_like 'keeps the notice', 'mismatch'
    end

    context 'when two different messages match' do
      before do
        contact.update!(custom_attributes: { 'waha_whatsapp_lid' => '123456789@lid' })
        stub_engine([engine_message, engine_message('id' => "false_123456789@lid_#{web_id}", 'from' => '123456789@lid')])
      end

      it_behaves_like 'keeps the notice', 'ambiguous'
    end
  end

  it 'a mesma mensagem repetida na resposta conta uma vez' do
    stub_engine([engine_message, engine_message])

    attempt!

    expect(attributes['hybrid_recovery']).to eq('recovered')
  end

  describe 'resposta 200 sem mensagem utilizável: tenta de novo até o prazo' do
    it 'corpo que não é objeto' do
      [[], 'ok', nil, [1, 'x']].each do |body|
        stub_engine(body)

        expect(attempt!).to eq(:retry)
      end
      expect(attributes['hybrid_recovery']).to eq('pending')
    end

    it 'conteúdo que ainda não chegou ao motor (_data.Message vazio ou ausente)' do
      [{ 'Message' => {} }, { 'Info' => {} }].each do |data|
        stub_engine(engine_message('_data' => data))

        expect(attempt!).to eq(:retry)
      end
      expect(message.reload.content).to eq(placeholder)
      expect(attributes['hybrid_recovery']).to eq('pending')
    end
  end

  it 'tipo que não lemos (protocolo, reação…): falha na hora com unreadable e mantém o aviso' do
    stub_engine(engine_message('_data' => { 'Message' => { 'protocolMessage' => { 'type' => 0 } } }))

    expect(attempt!).to eq(:done)
    expect(message.reload.content).to eq(placeholder)
    expect(attributes).to include('is_unsupported' => true, 'hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => 'unreadable')
  end

  it 'a mesma mensagem com id composto diferente (outro chat) e o mesmo remetente conta uma vez' do
    stub_engine([engine_message, engine_message('id' => "false_5511937016094@s.whatsapp.net_#{web_id}",
                                                'from' => '5511937016094@s.whatsapp.net')])

    attempt!

    expect(attributes['hybrid_recovery']).to eq('recovered')
  end

  it 'aceita o remetente em @s.whatsapp.net (mesmo número)' do
    stub_engine(engine_message('from' => '5511937016094@s.whatsapp.net'))

    attempt!

    expect(attributes['hybrid_recovery']).to eq('recovered')
  end

  it 'aceita o remetente @lid que o motor guardou no contato' do
    contact.update!(custom_attributes: { 'waha_whatsapp_lid' => '123456789@lid' })
    stub_engine(engine_message('from' => '123456789@lid'))

    expect(attempt!).to eq(:done)
    expect(attributes['hybrid_recovery']).to eq('recovered')
  end

  it 'sessão de outra caixa: nunca pergunta ao motor por ela (isolamento entre caixas)' do
    other_inbox = create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
    connection.update!(inbox: other_inbox, account: other_inbox.account)

    expect(attempt!).to eq(:retry)
    expect(a_request(:get, engine_url)).not_to have_been_made
  end

  it 'contato sem número: falha com chat_unknown sem perguntar ao motor' do
    contact.update!(phone_number: nil, custom_attributes: { 'waha_whatsapp_lid' => '123456789@lid' })

    expect(attempt!).to eq(:done)
    expect(attributes).to include('hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => 'chat_unknown')
  end

  it 'só põe na URL do motor id e chat id sem caracteres de caminho' do
    expect(described_class.safe_web_id?(web_id)).to be(true)
    expect(described_class.safe_web_id?('3EB0/../sessions')).to be(false)
    expect(described_class.safe_web_id?('')).to be(false)

    contact.update!(custom_attributes: { 'waha_whatsapp_chat_id' => '55/../x@c.us' })
    stub_engine

    attempt!

    expect(a_request(:get, engine_url)).to have_been_made.once
  end

  it 'id gravado inválido: falha sem perguntar ao motor' do
    message.update!(content_attributes: message.content_attributes.merge('whatsapp_web_id' => 'a/b'))

    expect(attempt!).to eq(:done)
    expect(attributes).to include('hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => 'invalid_id')
  end

  it 'fail! que não muda nada (já resolvida) não registra falha no log' do
    message.update!(content_attributes: message.content_attributes.merge('hybrid_recovery' => 'recovered'))
    allow(Rails.logger).to receive(:info)

    described_class.new(message).fail!('timeout')

    expect(Rails.logger).not_to have_received(:info).with(a_string_including('recovery failed'))
    expect(attributes['hybrid_recovery']).to eq('recovered')
  end

  it 'flag desligada no meio: falha com disabled' do
    account.disable_features!(described_class::FEATURE)

    expect(attempt!).to eq(:done)
    expect(attributes).to include('hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => 'disabled')
  end

  describe 'mídia (fica para a PR 3)' do
    it 'com legenda: guarda a legenda, falha com media e chama a IA pela legenda' do
      stub_engine(engine_message('hasMedia' => true,
                                 '_data' => { 'Message' => { 'imageMessage' => { 'caption' => 'Foto do produto' } } }))

      expect { attempt! }.to have_enqueued_job(reply_job).with(conversation.id, message.id).exactly(:once)

      expect(message.reload.content).to eq('Foto do produto')
      expect(attributes).not_to have_key('is_unsupported')
      expect(attributes).to include('hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => 'media')
    end

    it 'sem legenda: o aviso fica' do
      stub_engine(engine_message('hasMedia' => true, '_data' => { 'Message' => { 'audioMessage' => { 'seconds' => 4 } } }))

      expect { attempt! }.not_to have_enqueued_job(reply_job)

      expect(message.reload.content).to eq(placeholder)
      expect(attributes).to include('is_unsupported' => true, 'hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => 'media')
    end

    it 'visualização única: não abre, fica com o aviso (falha com media)' do
      stub_engine(engine_message('_data' => { 'Message' => { 'viewOnceMessageV2' => {
                                   'message' => { 'imageMessage' => { 'caption' => 'só uma vez' } }
                                 } } }))

      attempt!

      expect(message.reload.content).to eq(placeholder)
      expect(attributes).to include('is_unsupported' => true, 'hybrid_recovery_reason' => 'media')
    end
  end

  it 'a resposta do humano depois do aviso: recupera, mas não chama a IA (regra no RecoveryAiWake)' do
    stub_engine
    message
    create(:message, message_type: :outgoing, conversation: conversation, account: account, inbox: inbox,
                     sender: create(:user, account: account), content: 'Oi!')

    expect { attempt! }.not_to have_enqueued_job(reply_job)
    expect(attributes['hybrid_recovery']).to eq('recovered')
  end
end
