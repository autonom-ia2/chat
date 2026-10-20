require 'rails_helper'

# #1675: toda mensagem do cliente avalia o card em foco (flag crm_avaliar_toda_mensagem), também na caixa de 2+ funis.
RSpec.describe Crm::Conversations::CardEmFoco do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account, name: 'Joana Lima') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:pos_venda) { create_crm_pipeline(account: account, user: admin, name: 'Pós-venda') }
  let!(:auto) { create_card(vendas, 'Seguro auto', focused_at: 1.minute.ago) }
  let!(:residencial) { create_card(pos_venda, 'Seguro residencial', focused_at: 2.minutes.ago) }
  let(:identifier) { instance_double(Crm::Subjects::Identifier) }

  before do
    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Cards::Broadcaster).to receive(:broadcast)
    [vendas, pos_venda].each do |pipeline, stage|
      account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: stage, auto_create_card: false,
                                           created_by: admin)
    end
    account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :off)
    account.enable_features!(described_class::FLAG)
    allow(Crm::Subjects::Identifier).to receive(:new).and_return(identifier)
    clear_enqueued_jobs
  end

  def create_card(pipeline_and_stage, title, focused_at:)
    pipeline, stage = pipeline_and_stage
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, primary_conversation: conversation,
                                     inbox: inbox, title: title, last_activity_at: 3.days.ago, last_message_at: 3.days.ago)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversation)
                         .update!(is_primary: true, focused_at: focused_at)
    card
  end

  def incoming(content = 'Fechado, quero contratar')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: content)
  end

  def sincronizar(message)
    Crm::Conversations::CardSyncer.new(conversation: conversation.reload, message: message).perform
  end

  def avaliacoes_agendadas
    enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }.map { |job| job['arguments'].first }
  end

  # Roda as avaliações agendadas depois do debounce e devolve os cards que a IA de fato leu.
  def avaliados
    lidos = []
    allow(Crm::Ai::Evaluator).to receive(:new) do |card:, **|
      lidos << card.id
      instance_double(Crm::Ai::Evaluator, perform: nil)
    end
    jobs = enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
    travel(Crm::Ai::Config::DEBOUNCE_SECONDS.seconds + 1.second) do
      jobs.each { |job| Crm::Ai::EvaluateCardJob.perform_now(*job['arguments']) }
    end
    lidos
  end

  describe 'com a IA de assunto desligada na caixa de 2 funis' do
    it 'a mensagem no mesmo assunto agenda a IA no card em foco e conta como atividade dele', :aggregate_failures do
      message = incoming

      expect(sincronizar(message)).to eq(auto)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(auto.last_message_at).to be_within(1.second).of(message.created_at)
      expect(residencial.reload.last_activity_at).to be < 1.day.ago
      expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(auto, Events::Types::CRM_CARD_UPDATED)
      expect(avaliados).to eq([auto.id])
    end

    it 'uma rajada de mensagens dá uma avaliação só' do
      3.times { |i| sincronizar(incoming("parte #{i}")) }

      expect(avaliacoes_agendadas.uniq).to eq([auto.id])
      expect(avaliados).to eq([auto.id])
    end

    it 'mensagem automática (sem pessoa) não agenda nem mexe na atividade' do
      message = create(:message, :bot_message, account: account, inbox: inbox, conversation: conversation, content: 'Recebemos sua mensagem')

      sincronizar(message)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'não volta a atividade que uma ação mais nova gravou' do
      message = incoming
      auto.update!(last_activity_at: 1.minute.from_now)

      sincronizar(message)

      expect(auto.reload.last_activity_at).to be > message.created_at
      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'a atividade é a hora da mensagem do cliente, não a da resposta que veio depois' do
      message = incoming
      travel(1.minute) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Já te mando')
      end

      sincronizar(message)

      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(auto.last_message_at).to be_within(1.second).of(message.created_at)
    end

    it 'com a IA do CRM desligada, nada muda' do
      allow(Crm::Ai::Config).to receive(:enabled?).and_return(false)

      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'com o CRM desligado na caixa, nada muda' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(crm_enabled: false)

      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'sem a flag, tudo como hoje: nem avaliação, nem atividade, nem trava' do
      account.disable_features!(described_class::FLAG)
      allow(Crm::Conversations::SyncLock).to receive(:new).and_call_original

      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
      expect(Crm::Conversations::SyncLock).not_to have_received(:new)
    end
  end

  # #1923: a equipe manda os valores depois da última mensagem do cliente; sem isto o card esperava o cliente voltar.
  describe 'mensagem da equipe na caixa de 2 funis' do
    let(:espera) { described_class::ESPERA_DA_EQUIPE }

    def da_equipe(content = 'Segue a cotação: R$ 1.200 por ano', **atributos)
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: content, **atributos)
    end

    def avaliados_depois(tempo)
      lidos = []
      allow(Crm::Ai::Evaluator).to receive(:new) do |card:, **|
        lidos << card.id
        instance_double(Crm::Ai::Evaluator, perform: nil)
      end
      jobs = enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
      travel(tempo) { jobs.each { |job| Crm::Ai::EvaluateCardJob.perform_now(*job['arguments']) } }
      lidos
    end

    it 'a pessoa da equipe escreve ao cliente: a IA relê o card em foco depois da espera da equipe', :aggregate_failures do
      message = da_equipe

      expect(sincronizar(message)).to eq(auto)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(auto.last_message_at).to be_within(1.second).of(message.created_at)
      expect(residencial.reload.last_activity_at).to be < 1.day.ago
      expect(avaliados_depois(espera + 1.second)).to eq([auto.id])
    end

    it 'no debounce do cliente a avaliação da equipe ainda não roda: volta para a fila até o fim da espera' do
      sincronizar(da_equipe)

      expect(avaliados_depois(Crm::Ai::Config::DEBOUNCE_SECONDS.seconds + 1.second)).to be_empty
      expect(enqueued_jobs.count { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }).to eq(2)
    end

    it 'rajada da equipe (texto, PDF, despedida): uma avaliação só' do
      da_equipe('Segue a cotação').tap { |message| sincronizar(message) }
      travel(30.seconds) { sincronizar(da_equipe('Qualquer dúvida estou à disposição')) }

      expect(avaliados_depois(espera + 1.second)).to eq([auto.id])
    end

    it 'a equipe escreve sem parar: uma avaliação por espera, não adiada para sempre' do
      sincronizar(da_equipe('parte 1'))
      travel(espera - 10.seconds) { sincronizar(da_equipe('parte 2')) }

      expect(avaliados_depois(espera + 1.second)).to eq([auto.id])
    end

    it 'o cliente responde dentro da espera: a avaliação da mensagem dele vale pelas duas' do
      sincronizar(da_equipe)
      travel(30.seconds) { sincronizar(incoming('Fechado, pode emitir')) }

      expect(avaliados_depois(espera + 1.second)).to eq([auto.id])
      expect(Crm::Ai::Evaluator).to have_received(:new).once
    end

    it 'avaliação do cliente já agendada: a da equipe não agenda outra nem a adia' do
      sincronizar(incoming('Quanto fica?'))
      travel(5.seconds) { sincronizar(da_equipe) }

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(avaliados_depois(Crm::Ai::Config::DEBOUNCE_SECONDS.seconds + 1.second)).to eq([auto.id])
    end

    it 'job da equipe roda antes do job do cliente que chegou primeiro: o cliente não espera a espera da equipe' do
      cliente = incoming('Fechado, pode emitir')
      equipe = travel(3.seconds) { da_equipe('Perfeito') }
      travel(4.seconds) { sincronizar(equipe) }
      travel(5.seconds) { sincronizar(cliente) }

      depois = Time.zone.parse(auto.reload.metadata.dig('ai', 'evaluate_after'))
      expect(depois - cliente.created_at).to be <= Crm::Ai::Config::DEBOUNCE_SECONDS + 6
    end

    it 'eco do app do celular (WhatsApp) também é a equipe' do
      message = da_equipe(sender: nil, content_attributes: { external_echo: true })
      message.update_columns(sender_type: nil, sender_id: nil) # rubocop:disable Rails/SkipsModelValidations

      sincronizar(message.reload)

      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'com a IA de assunto ligada, a mensagem da equipe relê o card em foco sem esperar decisão de assunto' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :auto)

      sincronizar(da_equipe)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(enqueued_jobs.map { |job| job['job_class'] }).not_to include(Crm::Subjects::IdentifyJob.name)
    end

    {
      'robô (AgentBot)' => -> { { sender: create(:agent_bot, account: account) } },
      'regra de automação em nome de alguém' => -> { { content_attributes: { automation_rule_id: 1 } } },
      'follow-up do CRM' => -> { { content_attributes: { crm_follow_up_id: 1 } } },
      'campanha' => -> { { additional_attributes: { campaign_id: 1 } } },
      'envio que falhou' => -> { { status: :failed } },
      'nota privada' => -> { { private: true } }
    }.each do |origem, atributos|
      it "#{origem}: não é uma pessoa respondendo agora, não agenda nem mexe na atividade" do
        sincronizar(da_equipe(**instance_exec(&atributos)))

        expect(avaliacoes_agendadas).to be_empty
        expect(auto.reload.last_activity_at).to be < 1.day.ago
      end
    end

    it 'sem a flag, como hoje: nada' do
      account.disable_features!(described_class::FLAG)

      sincronizar(da_equipe)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end
  end

  describe 'com a IA de assunto ligada na caixa de 2 funis' do
    before { account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :auto) }

    it 'o CardSyncer espera a decisão do assunto: não agenda nem mexe no card' do
      sincronizar(incoming)

      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
    end

    it 'assunto mantido: depois da decisão, a IA avalia o card em foco', :aggregate_failures do
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming
      sincronizar(message)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(avaliados).to eq([auto.id])
    end

    it 'a decisão quebrou (Jev fora): a mensagem é avaliada mesmo assim' do
      allow(identifier).to receive(:perform).and_raise(RuntimeError, 'Jev fora')
      message = incoming

      expect { Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id) }.to raise_error(RuntimeError, 'Jev fora')

      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'troca de assunto: avalia o card novo do foco, uma vez só' do
      allow(identifier).to receive(:perform) do
        Crm::Subjects::Acoes.focar(conversation: conversation, card: residencial)
        instance_double(Crm::SubjectDecision, state: 'applied')
      end
      message = incoming('E o residencial, já renovou?')
      sincronizar(message)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to eq([residencial.id])
      expect(avaliados).to eq([residencial.id])
    end

    it 'rajada: a mensagem que não é a última fica para o job da seguinte, que avalia uma vez' do
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      primeira = incoming('Fechado')
      segunda = incoming('quero contratar')

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, primeira.id)
      expect(avaliacoes_agendadas).to be_empty

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, segunda.id)
      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'texto recuperado pelo Híbrido depois da avaliação: a IA relê o card (#1638)' do
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming('Mensagem não suportada')
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      travel(1.minute) do
        message.update!(content: 'Fechado, quero contratar', content_attributes: { 'hybrid_recovered_at' => Time.current.utc.iso8601 })
        Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)
      end

      expect(avaliacoes_agendadas).to eq([auto.id, auto.id])
    end

    it 'sem a flag, depois da decisão nada é agendado (como hoje)' do
      account.disable_features!(described_class::FLAG)
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to be_empty
    end
  end

  describe 'na caixa de 1 funil com card ao chegar' do
    before do
      account.crm_pipeline_inboxes.find_by(pipeline: pos_venda.first).destroy!
      account.crm_pipeline_inboxes.find_by(pipeline: vendas.first).update!(auto_create_card: true)
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true)
      residencial.update!(status: :archived)
    end

    it 'com a IA de assunto desligada: o card ao chegar avalia, como hoje, sem segunda avaliação' do
      allow(described_class).to receive(:new).and_call_original

      sincronizar(incoming)

      expect(described_class).not_to have_received(:new)
      expect(avaliados).to eq([auto.id])
    end

    it 'com a IA de assunto ligada: avalia depois da decisão, uma vez só' do
      account.crm_inbox_settings.find_by(inbox: inbox).update!(subject_ai_mode: :auto)
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
      message = incoming
      sincronizar(message)
      expect(avaliacoes_agendadas).to be_empty

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(avaliados).to eq([auto.id])
    end
  end

  # Caso do Rodrigo (16/10): o funil Vendas vende seguro auto e residencial; o cliente tem dois cards nele, auto em
  # Fechamento e residencial em Proposta. Caixa de 1 funil com card ao chegar e IA de assunto Automática.
  describe 'na caixa de 1 funil com dois assuntos no mesmo funil' do
    let(:proposta) { create_crm_stage(account: account, pipeline: vendas.first, name: 'Proposta', position: 1) }
    let(:fechamento) { create_crm_stage(account: account, pipeline: vendas.first, name: 'Fechamento', position: 2) }
    let!(:auto) { create_card(vendas, 'Seguro auto', focused_at: 1.minute.ago) }
    let!(:residencial) { create_card(vendas, 'Seguro residencial', focused_at: 2.minutes.ago) }

    before do
      account.crm_pipeline_inboxes.find_by(pipeline: pos_venda.first).destroy!
      account.crm_pipeline_inboxes.find_by(pipeline: vendas.first).update!(auto_create_card: true)
      account.crm_inbox_settings.find_by(inbox: inbox).update!(auto_create_card: true, subject_ai_mode: :auto)
      auto.update!(stage: fechamento)
      residencial.update!(stage: proposta)
      clear_enqueued_jobs
    end

    def decide_foco_em(card)
      allow(identifier).to receive(:perform) do
        Crm::Subjects::Acoes.focar(conversation: conversation, card: card)
        instance_double(Crm::SubjectDecision, state: 'applied')
      end
    end

    def mantem_assunto
      allow(identifier).to receive(:perform).and_return(instance_double(Crm::SubjectDecision, state: 'kept'))
    end

    it 'mensagem do residencial: o foco vai para ele e só ele é lido; o card auto da chegada não ganha avaliação nem atividade',
       :aggregate_failures do
      decide_foco_em(residencial)
      message = incoming('E o seguro da casa, já dá para fechar?')

      expect(sincronizar(message)).to eq(auto)
      expect(avaliacoes_agendadas).to be_empty
      expect(auto.reload.last_activity_at).to be < 1.day.ago
      expect(Crm::Assunto.funil_atual(conversation)).to eq(auto)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(Crm::Assunto.funil_atual(conversation)).to eq(residencial)
      expect(avaliacoes_agendadas).to eq([residencial.id])
      expect(residencial.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(auto.reload.last_activity_at).to be < 1.day.ago
      expect(avaliados).to eq([residencial.id])
    end

    it 'mensagem do auto: o card auto, que está em foco, é lido; o residencial não' do
      mantem_assunto
      message = incoming('Fechado, quero contratar o do carro')
      sincronizar(message)

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliados).to eq([auto.id])
      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)
      expect(residencial.reload.last_activity_at).to be < 1.day.ago
    end

    it 'a IA move o card lido: residencial vai de Proposta para Fechamento, o auto fica onde está' do
      decide_foco_em(residencial)
      message = incoming('Pode fechar o da casa também')
      sincronizar(message)
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)
      allow(Crm::Ai::Evaluator).to receive(:new) do |card:, **|
        instance_double(Crm::Ai::Evaluator, perform: card.update!(stage: fechamento))
      end

      travel(Crm::Ai::Config::DEBOUNCE_SECONDS.seconds + 1.second) do
        enqueued_jobs.select { |job| job['job_class'] == Crm::Ai::EvaluateCardJob.name }
                     .each { |job| Crm::Ai::EvaluateCardJob.perform_now(*job['arguments']) }
      end

      expect(residencial.reload.stage).to eq(fechamento)
      expect(Crm::Ai::Evaluator).to have_received(:new).once
      expect(Crm::Ai::Evaluator).to have_received(:new).with(card: residencial, trigger: 'message')
    end

    it 'rajada no mesmo assunto: uma avaliação, no card em foco' do
      mantem_assunto
      mensagens = Array.new(3) { |i| incoming("parte #{i}") }
      mensagens.each do |message|
        sincronizar(message)
        Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)
      end

      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(avaliados).to eq([auto.id])
    end

    it 'mensagem da equipe: o card da chegada segue como hoje (a decisão do assunto é só da mensagem do cliente)' do
      message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Já te mando')

      sincronizar(message)

      expect(avaliacoes_agendadas).to eq([auto.id])
    end

    it 'decisão que roda antes de o card da chegada existir: o card novo é avaliado uma vez' do
      [auto, residencial].each { |card| card.update!(status: :archived) }
      mantem_assunto
      message = incoming('Quero um seguro para o carro')

      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)
      expect(avaliacoes_agendadas).to be_empty
      novo = sincronizar(message)

      expect(novo).to be_present
      expect(avaliacoes_agendadas).to eq([novo.id])
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)
      expect(avaliacoes_agendadas).to eq([novo.id])
    end

    it 'sem a flag, como hoje: o card da chegada é avaliado na hora e a decisão não agenda nada' do
      account.disable_features!(described_class::FLAG)
      decide_foco_em(residencial)
      message = incoming('E o seguro da casa?')
      sincronizar(message)
      expect(avaliacoes_agendadas).to eq([auto.id])
      expect(auto.reload.last_activity_at).to be_within(1.second).of(message.created_at)

      clear_enqueued_jobs
      Crm::Subjects::IdentifyJob.perform_now(conversation.id, message.id)

      expect(avaliacoes_agendadas).to eq([residencial.id])
    end
  end
end
