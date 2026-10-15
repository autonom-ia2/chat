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

  # Autocura (#1633): quem ligou a autorização antes do assinante do evento estar no ar ficava sem os modelos v2 para
  # sempre. O envio real (`heal: true`) que encontra `ausente` com a autorização ligada enfileira a criação, com trava
  # por caixa.
  describe 'autocura dos modelos v2' do
    let(:templates) { [v1] }
    let(:lock_key) { format(described_class::HEAL_LOCK_KEY, inbox_id: inbox.id) }
    let(:job) { Crm::BookingV2::NoticeTemplateEnsureJob }

    # A trava mora no Redis, que não volta com a transação do exemplo. A página nova publicada com esta caixa e o
    # agendamento novo ligado: o que o job confere.
    before do
      Redis::Alfred.delete(lock_key)
      account.enable_features('crm_booking_v2')
      account.save!
      world.profile.update!(notice_inbox: inbox)
    end

    after { Redis::Alfred.delete(lock_key) }

    def ligar_autorizacao
      WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU,
                                      versao_aviso: 'v1', texto_aviso: 'Aviso.')
    end

    def heal_decide(kind: 'booked', template: configured, conversation: nil)
      described_class.new(inbox: inbox, contact: world.contact, template: template, kind: kind, conversation: conversation,
                          heal: true).decide
    end

    def trava?
      Redis::Alfred.exists?(lock_key)
    end

    # Motivo: o caminho da correção. `ausente` + autorização enfileira a criação UMA vez; o aviso seguinte, logo depois,
    # não enfileira de novo (sem a trava, cada aviso de cada contato enfileiraria um job).
    it 'ausente com autorização enfileira uma vez, e a segunda chamada não enfileira de novo' do
      ligar_autorizacao

      expect { heal_decide }.to have_enqueued_job(job).with(account.id, inbox.id).exactly(:once)
      expect { heal_decide(kind: 'hour_before') }.not_to have_enqueued_job(job)
    end

    # Motivo: o aviso daquele momento não espera a criação: continua na regra de hoje (o v1 configurado, ou o motivo
    # de pulo sem ele), e nada vai à Meta na hora.
    it 'o aviso de agora segue a regra de hoje, sem falar com a Meta' do
      ligar_autorizacao

      expect(heal_decide.template['name']).to eq('aviso_marcado')
      Redis::Alfred.delete(lock_key)
      expect(heal_decide(template: {})).to have_attributes(reason: 'template_required')
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
    end

    # Motivo: o padrão é sem efeito (`heal: false`): quem não é o envio real (a página pública, o teste) não pode
    # gastar a trava nem enfileirar.
    it 'sem heal não enfileira nem grava a trava' do
      ligar_autorizacao

      expect { decide }.not_to have_enqueued_job(job)
      expect(trava?).to be(false)
    end

    # Motivo: sem a autorização do dono o sistema não pode criar modelo na Meta (#1586); nem enfileira.
    it 'sem autorização não enfileira nem grava a trava' do
      expect { heal_decide }.not_to have_enqueued_job(job)
      expect(trava?).to be(false)
    end

    # Motivo: autorização desligada depois de ligada vale como sem autorização (a última linha manda).
    it 'autorização desligada não enfileira' do
      ligar_autorizacao
      WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::DESLIGOU,
                                      versao_aviso: 'v1', texto_aviso: 'Aviso.')

      expect { heal_decide }.not_to have_enqueued_job(job)
    end

    # Motivo: com o agendamento novo desligado o job não faria nada; a trava não pode ser gasta à toa.
    it 'agendamento novo desligado não enfileira nem grava a trava' do
      ligar_autorizacao
      account.disable_features('crm_booking_v2')
      account.save!

      expect { heal_decide }.not_to have_enqueued_job(job)
      expect(trava?).to be(false)
    end

    # Motivo: o job só cria para caixas de páginas novas publicadas; sem nenhuma com esta caixa, nada a fazer.
    it 'sem página publicada com esta caixa não enfileira nem grava a trava' do
      ligar_autorizacao
      world.profile.update!(enabled: false)

      expect { heal_decide }.not_to have_enqueued_job(job)
      expect(trava?).to be(false)
    end

    # Motivo: em análise o modelo já existe na Meta; enfileirar seria trabalho à toa.
    context 'when o v2 está em análise' do
      let(:templates) { [v1, v2('PENDING')] }

      it 'não enfileira' do
        ligar_autorizacao

        expect { heal_decide }.not_to have_enqueued_job(job)
      end
    end

    # Motivo: pronto, o v2 é usado; não há o que criar.
    context 'when o v2 está pronto' do
      let(:templates) { [v1, v2('APPROVED')] }

      it 'não enfileira' do
        ligar_autorizacao

        expect { heal_decide }.not_to have_enqueued_job(job)
      end
    end

    # Motivo: sem `kind` (o "Testar no meu WhatsApp") o v2 nem é consultado; não pode disparar criação.
    it 'sem kind não enfileira' do
      ligar_autorizacao

      expect { heal_decide(kind: nil) }.not_to have_enqueued_job(job)
    end

    # Motivo: com a janela aberta o aviso sai como texto, mas é a hora de os modelos ficarem prontos antes de a
    # conversa fechar. A decisão continua `session`, e a consulta só lê.
    context 'when a janela de 24 h está aberta' do
      let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: world.contact) }

      before do
        allow(Crm::FollowUps::MessagingWindow).to receive(:new)
          .and_return(instance_double(Crm::FollowUps::MessagingWindow, can_send_session_message?: true))
      end

      it 'enfileira e a decisão continua texto' do
        ligar_autorizacao
        allow(Whatsapp::Templates::Garantir).to receive(:call).and_call_original
        decision = nil

        expect { decision = heal_decide(conversation: conversation) }.to have_enqueued_job(job).with(account.id, inbox.id)
        expect(decision).to have_attributes(mode: :session, reason: nil, template: nil)
        expect(Whatsapp::Templates::Garantir).to have_received(:call).with(hash_including(criar: false))
        expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
      end

      # Motivo: sem heal, a janela aberta continua como era: nem consulta o Garantir.
      it 'sem heal nem consulta o Garantir' do
        ligar_autorizacao
        allow(Whatsapp::Templates::Garantir).to receive(:call)
        conversation # a conversa da caixa, que o Route acha sozinho

        expect(decide.mode).to eq(:session)
        expect(Whatsapp::Templates::Garantir).not_to have_received(:call)
      end
    end

    # Motivo: a fila fora do ar não pode derrubar o aviso: o erro vai ao tracker, o aviso segue a regra de hoje e a
    # trava sai, para o próximo aviso tentar de novo (senão a caixa ficaria 15 min sem autocura).
    it 'erro ao enfileirar vai ao tracker, o aviso segue e a trava não fica' do
      ligar_autorizacao
      allow(job).to receive(:perform_later).and_raise(StandardError, 'fila fora')
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      expect(heal_decide.template['name']).to eq('aviso_marcado')
      expect(tracker).to have_received(:capture_exception).once
      expect(trava?).to be(false)
    end
  end

  # Motivo: a tela pública pergunta "vai sair?" numa requisição web: o `Garantir` precisa ir com `criar: false`
  # (nunca cria, nunca fala com a Meta), mesmo sem o v2 na caixa.
  describe 'Sender#will_send?' do
    let(:templates) { [v1] }
    let(:meeting) do
      create_internal_meeting(world: world, starts_at: Time.zone.parse('2026-10-20T13:00:00Z'),
                              metadata: { 'booking_profile_id' => world.profile.id })
    end
    let(:lock_key) { format(described_class::HEAL_LOCK_KEY, inbox_id: inbox.id) }
    let(:notice) { Crm::MeetingNotice.create!(meeting: meeting, account: account, kind: 'booked', status: :pending, due_at: Time.current) }

    before do
      Redis::Alfred.delete(lock_key)
      account.enable_features('crm_booking_v2')
      account.save!
      world.profile.update!(notice_inbox: inbox, notice_templates: { 'booked' => configured })
      create_booking_invite(world: world, meeting: meeting, scheduled_at: Time.current, channel: 'public')
    end

    after { Redis::Alfred.delete(lock_key) }

    it 'consulta só para ler' do
      allow(Whatsapp::Templates::Garantir).to receive(:call).and_call_original

      expect(Crm::BookingV2::Notices::Sender.new(notice).will_send?).to be(true)
      expect(Whatsapp::Templates::Garantir).to have_received(:call).with(hash_including(criar: false))
      expect(Whatsapp::Templates::MetaClient).not_to have_received(:new)
      expect(channel.reload.message_templates.map { |item| item['name'] }).to eq(['aviso_marcado'])
    end

    # Motivo (#1633): a página pública é anônima e o `will_send?` tem contrato "sem efeito": mesmo com `ausente` e a
    # autorização ligada, não grava a trava nem enfileira a criação.
    it 'não grava a trava nem enfileira a autocura' do
      WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU,
                                      versao_aviso: 'v1', texto_aviso: 'Aviso.')
      sender = Crm::BookingV2::Notices::Sender.new(notice)

      expect { sender.will_send? }.not_to have_enqueued_job(Crm::BookingV2::NoticeTemplateEnsureJob)
      expect(Redis::Alfred.exists?(lock_key)).to be(false)
    end

    # Motivo (#1633): o envio real (o cron) é quem liga a autocura; sem isso ela nunca rodaria.
    it 'o envio real liga a autocura' do
      allow(described_class).to receive(:new)
        .and_return(instance_double(described_class, decide: described_class::Decision.new(reason: 'template_required')))

      Crm::BookingV2::Notices::Sender.new(notice).perform

      expect(described_class).to have_received(:new).with(hash_including(heal: true))
    end
  end
end
