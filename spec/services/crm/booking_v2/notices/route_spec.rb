require 'rails_helper'

# Modelo v2 com botões dos avisos (#1524): no oficial com a janela fechada, o v2 aprovado passa na frente do modelo
# configurado (decisão do Rodrigo); fora do `:pronto` vale a regra de antes. A consulta ao `Garantir` só LÊ.
RSpec.describe Crm::BookingV2::Notices::Route do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:world) { build_booking_world(account: account) }
  let(:v1) do
    { 'name' => 'aviso_marcado', 'status' => 'APPROVED', 'language' => 'pt_BR', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Oi {{1}}, seu horário é {{2}}. Gerencie aqui: {{3}}' }] }
  end
  let(:pronto) { Whatsapp::Templates::Finalidades.pronto(:agendamento_ao_marcar) }
  let(:templates) { [v1, v2('APPROVED')] }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'api_key' => 'k', 'phone_number_id' => 'p', 'business_account_id' => 'waba-1' },
                              message_templates: templates)
  end
  let(:inbox) { channel.inbox }
  let(:configured) { { 'name' => 'aviso_marcado', 'language' => 'pt_BR' } }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true', 'CRM_CALENDAR_MEETINGS_ENABLED' => 'true', 'FRONTEND_URL' => 'https://app.example.com') do
      travel_to(Time.zone.parse('2026-10-12T14:00:00Z')) { example.run }
    end
  end

  before { allow(Whatsapp::Templates::MetaClient).to receive(:new).and_raise('a Meta não pode ser chamada') }

  def v2(status, category: 'UTILITY')
    pronto.corpo.deep_stringify_keys.merge('id' => '902', 'status' => status, 'category' => category)
  end

  def decide(kind: 'booked', template: configured)
    described_class.new(inbox: inbox, contact: world.contact, template: template, kind: kind).decide
  end

  # Motivo: o caminho novo. Aprovado como UTILITY, o v2 sai na frente do v1 configurado, com os campos do corpo e os
  # botões que o `TemplateFill` preenche.
  it ':pronto usa o v2 com os campos e os botões, na frente do configurado' do
    decision = decide

    expect(decision).to have_attributes(mode: :native_template, reason: nil)
    expect(decision.template['name']).to eq('agendamento_ao_marcar_v2')
    expect(decision.campos).to eq('1' => 'cliente.primeiro_nome', '2' => 'horario.data_hora')
    expect(decision.botoes).to eq([{ 'indice' => 0, 'tipo' => 'url', 'campo' => 'horario.link_codigo' },
                                   { 'indice' => 1, 'tipo' => 'quick_reply', 'payload' => 'stop_notices' }])
  end

  # Motivo: cada tipo de aviso consulta a sua finalidade (o lembrete de 1 hora não manda o "ao marcar").
  it 'consulta a finalidade do tipo do aviso' do
    allow(Whatsapp::Templates::Garantir).to receive(:call).and_call_original

    decide(kind: 'hour_before', template: {})

    expect(Whatsapp::Templates::Garantir).to have_received(:call)
      .with(inbox: inbox, finalidade: 'agendamento_1_hora_antes', criar: false)
  end

  # Motivo: em análise, o v1 escolhido à mão segue como reserva (decisão do Rodrigo).
  context 'when o v2 está em análise' do
    let(:templates) { [v1, v2('PENDING')] }

    it 'segue a regra de hoje: o v1 configurado, sem campos nem botões' do
      decision = decide

      expect(decision).to have_attributes(mode: :native_template, campos: nil, botoes: nil)
      expect(decision.template['name']).to eq('aviso_marcado')
    end
  end

  # Motivo: o v2 ainda não existe na caixa (`ausente`): nada é criado e vale a regra de hoje, inclusive o motivo de pulo.
  context 'when o v2 não está na caixa' do
    let(:templates) { [v1] }

    it 'segue a regra de hoje, sem falar com a Meta' do
      expect(decide.template['name']).to eq('aviso_marcado')
      expect(decide(template: {})).to have_attributes(reason: 'template_required')
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
    end
  end

  # Motivo: a Meta reclassificou como MARKETING: sem a 2ª marca do #1585 não serve; vale a regra de hoje.
  context 'when o v2 foi aprovado como MARKETING' do
    let(:templates) { [v1, v2('APPROVED', category: 'MARKETING')] }

    it 'segue a regra de hoje' do
      expect(decide.template['name']).to eq('aviso_marcado')
    end
  end

  # Motivo: a Meta recusa parâmetro vazio; contato sem primeiro nome não usa o v2 (o `{{1}}` sairia vazio).
  it 'contato sem primeiro nome segue a regra de hoje' do
    world.contact.update!(name: '')

    expect(decide.template['name']).to eq('aviso_marcado')
  end

  # Motivo: erro ao ler a lista da caixa só tira o v2; o aviso não cai por causa dele.
  it 'erro na consulta ao Garantir vai ao tracker e segue a regra de hoje' do
    allow(Whatsapp::Templates::Garantir).to receive(:call).and_raise(StandardError, 'lista quebrada')
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    expect(decide.template['name']).to eq('aviso_marcado')
    expect(tracker).to have_received(:capture_exception).once
  end

  # Motivo: sem `kind` (o "Testar no meu WhatsApp"), o v2 não é consultado.
  it 'sem kind não consulta o Garantir' do
    allow(Whatsapp::Templates::Garantir).to receive(:call)

    expect(decide(kind: nil).template['name']).to eq('aviso_marcado')
    expect(Whatsapp::Templates::Garantir).not_to have_received(:call)
  end

  # Motivo: a tela pública pergunta "vai sair?" numa requisição web: o `Garantir` precisa ir com `criar: false`
  # (nunca cria, nunca fala com a Meta), mesmo sem o v2 na caixa.
  describe 'Sender#will_send?' do
    let(:templates) { [v1] }
    let(:meeting) do
      create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                              metadata: { 'booking_profile_id' => world.profile.id })
    end

    before do
      account.enable_features('crm_booking_v2')
      account.save!
      world.profile.update!(notice_inbox: inbox, notice_templates: { 'booked' => configured })
      create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public')
    end

    it 'consulta só para ler' do
      allow(Whatsapp::Templates::Garantir).to receive(:call).and_call_original
      notice = Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', status: :pending, due_at: Time.current)

      expect(Crm::BookingV2::Notices::Sender.new(notice).will_send?).to be(true)
      expect(Whatsapp::Templates::Garantir).to have_received(:call).with(hash_including(criar: false))
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
      expect(channel.reload.message_templates.map { |item| item['name'] }).to eq(['aviso_marcado'])
    end
  end
end
