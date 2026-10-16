require 'rails_helper'

# Aviso fora da janela pelo modelo v2 com botões (#1524): uma mensagem só, com o corpo e os `buttons` no formato que o
# envio do upstream espera (`Whatsapp::Templates::SendComponents`) e a marca do aviso para o "Parar avisos".
RSpec.describe Crm::BookingV2::Notices::Sender do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:pronto) { Whatsapp::Templates::Finalidades.pronto(:agendamento_ao_marcar) }
  let(:v2) { pronto.corpo.deep_stringify_keys.merge('id' => '902', 'status' => 'APPROVED') }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'api_key' => 'k', 'phone_number_id' => 'p', 'business_account_id' => 'waba-1' },
                              message_templates: [v2])
  end
  let(:inbox) { channel.inbox }
  let(:meeting) do
    create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                            metadata: { 'booking_profile_id' => world.profile.id })
  end
  let!(:invite) { create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public') }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before do
    account.enable_features('crm_booking_v2')
    account.save!
    world.profile.update!(notice_inbox: inbox)
    allow(Whatsapp::Templates::MetaClient).to receive(:new).and_raise('a Meta não pode ser chamada')
  end

  # Motivo: o contrato com o envio. Corpo pela ordem dos `campos`, o URL com o código do link de gestão (o fim de
  # `/b/<código>`), a resposta rápida só com o payload, e a marca `crm_booking_notice_id` que o listener confere.
  it 'janela fechada + v2 pronto: manda o modelo com o corpo, os botões e a marca, numa mensagem só' do
    notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', status: :sending, attempts: 1,
                                        due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, 'booked'))

    expect { described_class.new(notice).perform }.to change(Message, :count).by(1)

    message = Message.find(notice.reload.message_id)
    code = invite.url.split('/b/').last
    expect(notice.status).to eq('sent')
    expect(message.additional_attributes['template_params']).to eq(
      'name' => 'agendamento_ao_marcar_v2', 'language' => 'pt_BR',
      'processed_params' => {
        'body' => { '1' => 'Marcos', '2' => '20/10 às 10:00' },
        'buttons' => [{ 'type' => 'url', 'parameter' => code }, { 'type' => 'quick_reply', 'payload' => 'stop_notices' }]
      }
    )
    expect(message.content).to eq(pronto.texto.sub('{{1}}', 'Marcos').sub('{{2}}', '20/10 às 10:00'))
    expect(message.content_attributes).to include('crm_booking_notice' => true, 'crm_booking_notice_id' => notice.id)
    expect(Crm::BookingV2::NoticeStopPartJob).not_to have_been_enqueued
  end

  # Motivo: o `{{2}}` sai no fuso da reunião (o da página), nunca no do servidor nem em "Brasília". 13:00 UTC em Manaus
  # (UTC-4) é 09:00, não as 10:00 de São Paulo.
  it 'o dia e a hora saem no fuso da reunião' do
    meeting.update!(timezone: 'America/Manaus')
    notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', status: :sending, attempts: 1,
                                        due_at: Crm::BookingV2::Notices::Scheduler.expected_due_at(meeting, 'booked'))

    described_class.new(notice).perform

    body = Message.find(notice.reload.message_id).additional_attributes.dig('template_params', 'processed_params', 'body')
    expect(body['2']).to eq('20/10 às 09:00')
  end

  # Motivo: o `template_params` chega à Meta como o upstream monta (corpo + URL com o código + payload estável).
  it 'o envio do upstream monta os componentes do corpo e dos dois botões' do
    params = { 'name' => 'agendamento_ao_marcar_v2', 'language' => 'pt_BR',
               'processed_params' => { 'body' => { '1' => 'Marcos', '2' => '20/10 às 10:00' },
                                       'buttons' => [{ 'type' => 'url', 'parameter' => 'AB3K9QXZ' },
                                                     { 'type' => 'quick_reply', 'payload' => 'stop_notices' }] } }

    components = Whatsapp::TemplateProcessorService.new(channel: channel, template_params: params).call.last

    expect(components).to include(
      { type: 'button', sub_type: 'url', index: 0, parameters: [{ type: 'text', text: 'AB3K9QXZ' }] },
      { type: 'button', sub_type: 'quick_reply', index: 1, parameters: [{ type: 'payload', payload: 'stop_notices' }] }
    )
    expect(components.first).to include(type: 'body')
  end
end
