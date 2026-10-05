require 'rails_helper'

# O aviso urgente do Guia (#935, D5) vira notificação `guide_alert`: sino, push e e-mail que já existem.
RSpec.describe Notification do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:aviso) do
    Autonomia::Guide::Aviso.create!(account: account, user: admin, chave: 'k', gravidade: 'urgente',
                                    texto: "Conexão caída: 1 agora (o limite é 0).\n\nQuer que eu veja isso com você?")
  end
  let(:notificacao) { described_class.create!(notification_type: :guide_alert, user: admin, account: account, primary_actor: aviso) }

  it 'é o tipo 11 e tem título e texto próprios', :aggregate_failures do
    expect(described_class::NOTIFICATION_TYPES[:guide_alert]).to eq(11)
    expect(notificacao.push_message_title).to eq('The Guide has an urgent warning for you')
    expect(notificacao.push_message_body).to start_with('Conexão caída: 1 agora')
    expect(notificacao.push_event_data[:primary_actor]).to eq(id: aviso.id, texto: aviso.texto, gravidade: 'urgente')
  end

  it 'quem entra numa conta já recebe o aviso urgente por e-mail e push' do
    setting = admin.notification_settings.find_by(account: account)

    expect([setting.email_guide_alert?, setting.push_guide_alert?]).to eq([true, true])
  end

  it 'o push abre o painel da conta com o Guia aberto, não uma conversa', :aggregate_failures do
    allow(WebPush).to receive(:payload_send)
    with_modified_env VAPID_PUBLIC_KEY: 'test', FRONTEND_URL: 'https://app.exemplo.com' do
      create(:notification_subscription, user: admin)

      Notification::PushNotificationService.new(notification: notificacao).perform
    end

    expect(WebPush).to have_received(:payload_send) do |argumentos|
      mensagem = JSON.parse(argumentos[:message])
      expect(mensagem['url']).to eq("https://app.exemplo.com/app/accounts/#{account.id}/dashboard?guia=aviso")
      expect(mensagem['tag']).to eq("guide_alert_#{aviso.id}_#{notificacao.id}")
    end
  end

  it 'o e-mail sai pelo mailer do aviso' do
    mailer = double
    allow(AgentNotifications::GuideAlertMailer).to receive(:with).and_return(mailer)
    allow(mailer).to receive(:guide_alert).and_return(instance_double(ActionMailer::MessageDelivery, deliver_later: true))

    Notification::EmailNotificationService.new(notification: notificacao).perform

    expect(mailer).to have_received(:guide_alert).with(aviso, admin)
  end

  it 'o e-mail traz o título, o texto do aviso e o link que abre o Guia', :aggregate_failures do
    with_modified_env SMTP_ADDRESS: 'smtp.exemplo.com', FRONTEND_URL: 'https://app.exemplo.com' do
      email = AgentNotifications::GuideAlertMailer.with(account: account).guide_alert(aviso, admin).message
      expect(email.subject).to eq('The Guide has an urgent warning for you')
      expect(email.body.encoded).to include('Conexão caída: 1 agora')
      expect(email.body.encoded).to include("https://app.exemplo.com/app/accounts/#{account.id}/dashboard?guia=aviso")
    end
  end

  it 'limpar duplicadas não apaga a notificação de uma conversa com o mesmo id do aviso' do
    conversa = create(:conversation, account: account)
    da_conversa = described_class.create!(notification_type: :conversation_assignment, user: admin, account: account,
                                          primary_actor: conversa)
    allow(aviso).to receive(:id).and_return(conversa.id)
    notificacao.update_columns(primary_actor_id: conversa.id) # rubocop:disable Rails/SkipsModelValidations

    Notification::RemoveDuplicateNotificationJob.perform_now(notificacao)

    expect(described_class.exists?(da_conversa.id)).to be(true)
  end
end
