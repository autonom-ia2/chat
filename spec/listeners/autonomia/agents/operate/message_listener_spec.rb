require 'rails_helper'

# chat#1489: no WhatsApp, a nossa IA não responde ao aviso de "mensagem não suportada" (pendente, falhou ou sem
# recuperação). Instagram e TikTok também marcam `is_unsupported` (em mídia): lá a IA segue como antes.
describe Autonomia::Agents::Operate::MessageListener do
  let(:listener) { described_class.instance }
  let(:whatsapp_inbox) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:reply_job) { Autonomia::Agents::Operate::ReplyJob }

  before { allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true) }

  def created(attributes, inbox: whatsapp_inbox)
    conversation = create(:conversation, account: inbox.account, inbox: inbox)
    message = create(:message, message_type: :incoming, account: inbox.account, inbox: inbox, conversation: conversation,
                               content: 'texto', content_attributes: attributes)
    Events::Base.new('message.created', Time.zone.now, message: message)
  end

  it 'chama a IA para mensagem comum do contato' do
    expect { listener.message_created(created({})) }.to have_enqueued_job(reply_job)
  end

  it 'não chama a IA para o aviso pendente de recuperação' do
    event = created({ 'is_unsupported' => true, 'hybrid_recovery' => 'pending' })

    expect { listener.message_created(event) }.not_to have_enqueued_job(reply_job)
  end

  it 'não chama a IA para o aviso sem recuperação nem para o que falhou' do
    expect { listener.message_created(created({ 'is_unsupported' => true })) }.not_to have_enqueued_job(reply_job)

    failed = created({ 'is_unsupported' => true, 'hybrid_recovery' => 'failed' })
    expect { listener.message_created(failed) }.not_to have_enqueued_job(reply_job)
  end

  it 'lê a marca com chave em símbolo (mensagem ainda em memória, recém-criada)' do
    event = created({})
    event.data[:message].content_attributes = { is_unsupported: true }

    expect { listener.message_created(event) }.not_to have_enqueued_job(reply_job)
  end

  it 'Instagram com is_unsupported (mídia): a IA continua sendo chamada' do
    inbox = create(:channel_instagram).inbox

    expect { listener.message_created(created({ 'is_unsupported' => true }, inbox: inbox)) }.to have_enqueued_job(reply_job)
  end

  it 'TikTok com is_unsupported (mídia): a IA continua sendo chamada' do
    inbox = create(:channel_tiktok).inbox

    expect { listener.message_created(created({ 'is_unsupported' => true }, inbox: inbox)) }.to have_enqueued_job(reply_job)
  end

  it 'aviso sem recuperação: registra o motivo (NaoSuportada.ignorada)' do
    allow(Autonomia::Agents::Operate::NaoSuportada).to receive(:ignorada)
    event = created({ 'is_unsupported' => true })

    listener.message_created(event)

    expect(Autonomia::Agents::Operate::NaoSuportada).to have_received(:ignorada).with(event.data[:message])
  end

  it 'aviso com recuperação pendente: não registra agora (a recuperação decide)' do
    allow(Autonomia::Agents::Operate::NaoSuportada).to receive(:ignorada)

    listener.message_created(created({ 'is_unsupported' => true, 'hybrid_recovery' => 'pending' }))

    expect(Autonomia::Agents::Operate::NaoSuportada).not_to have_received(:ignorada)
  end
end
