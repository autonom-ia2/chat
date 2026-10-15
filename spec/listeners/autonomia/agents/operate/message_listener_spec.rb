require 'rails_helper'

# chat#1489: no WhatsApp da conta com a flag `whatsapp_hybrid_recovery`, a nossa IA espera quando o aviso de "mensagem
# não suportada" tem recuperação em curso (`hybrid_recovery: pending`). Sem a flag, ou sem recuperação, igual à main.
# Instagram e TikTok também marcam `is_unsupported` (em mídia): lá a IA segue como antes.
describe Autonomia::Agents::Operate::MessageListener do
  let(:listener) { described_class.instance }
  let(:whatsapp_inbox) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:reply_job) { Autonomia::Agents::Operate::ReplyJob }
  let(:pending) { { 'is_unsupported' => true, 'hybrid_recovery' => 'pending' } }

  before do
    allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
    whatsapp_inbox.account.enable_features!(WhatsappHybrid::UnsupportedRecovery::FEATURE)
  end

  def created(attributes, inbox: whatsapp_inbox)
    conversation = create(:conversation, account: inbox.account, inbox: inbox)
    message = create(:message, message_type: :incoming, account: inbox.account, inbox: inbox, conversation: conversation,
                               content: 'texto', content_attributes: attributes)
    Events::Base.new('message.created', Time.zone.now, message: message)
  end

  it 'chama a IA para mensagem comum do contato' do
    expect { listener.message_created(created({})) }.to have_enqueued_job(reply_job)
  end

  context 'with the flag on' do
    it 'aviso com recuperação em curso: a IA espera' do
      expect { listener.message_created(created(pending)) }.not_to have_enqueued_job(reply_job)
    end

    it 'lê a marca com chave em símbolo (mensagem ainda em memória, recém-criada)' do
      event = created({})
      event.data[:message].content_attributes = { is_unsupported: true, hybrid_recovery: 'pending' }

      expect { listener.message_created(event) }.not_to have_enqueued_job(reply_job)
    end

    it 'aviso sem recuperação (caixa sem WhatsApp API pronto, tipo que não é mensagem nova): vai para a IA como na main' do
      expect { listener.message_created(created({ 'is_unsupported' => true })) }.to have_enqueued_job(reply_job)
    end

    it 'aviso cuja recuperação já falhou: vai para a IA como na main (o evento novo não existe aqui)' do
      failed = { 'is_unsupported' => true, 'hybrid_recovery' => 'failed' }

      expect { listener.message_created(created(failed)) }.to have_enqueued_job(reply_job)
    end
  end

  context 'with the flag off (igual à main)' do
    before { whatsapp_inbox.account.disable_features!(WhatsappHybrid::UnsupportedRecovery::FEATURE) }

    it 'até o aviso marcado como pendente segue para a IA' do
      expect { listener.message_created(created(pending)) }.to have_enqueued_job(reply_job)
    end
  end

  it 'Instagram com is_unsupported (mídia): a IA continua sendo chamada' do
    inbox = create(:channel_instagram).inbox

    expect { listener.message_created(created({ 'is_unsupported' => true }, inbox: inbox)) }.to have_enqueued_job(reply_job)
  end

  it 'TikTok com is_unsupported (mídia): a IA continua sendo chamada' do
    inbox = create(:channel_tiktok).inbox

    expect { listener.message_created(created({ 'is_unsupported' => true }, inbox: inbox)) }.to have_enqueued_job(reply_job)
  end
end
