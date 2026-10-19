require 'rails_helper'

# #1870 — retenção: linhas sem mudança há mais de 30 dias saem em lote; as recentes ficam.
describe ConversaCanal::LimparEmailLidosJob do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, :imap_email, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }

  def linha(sincronizado_em)
    message = create(:message, conversation: conversation, account: account, inbox: channel.inbox, message_type: :incoming)
    ConversaCanal::EmailLido.create!(account: account, inbox: channel.inbox, message: message, sincronizado_em: sincronizado_em)
  end

  it 'apaga só as linhas com sincronizado_em antes da retenção' do
    velha = linha(31.days.ago)
    recente = linha(29.days.ago)

    described_class.perform_now

    expect(ConversaCanal::EmailLido.pluck(:id)).to eq([recente.id])
    expect(ConversaCanal::EmailLido.exists?(velha.id)).to be(false)
  end

  it 'está no cron do projeto, na fila low' do
    agenda = YAML.safe_load(Rails.root.join('config/schedule.yml').read)['conversa_canal_limpar_email_lidos_job']

    expect(agenda).to include('class' => described_class.name, 'queue' => 'low')
  end
end
