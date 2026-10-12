require 'rails_helper'

# Follow-up escrito pela equipe (manual ou etapa do funil), fora das 24h, sem modelo, em caixa Oficial com
# WhatsApp Híbrido (chat#1349, PR B): o texto sai pelo WhatsApp API. Nada do que o cliente manda decide isso.
RSpec.describe 'Follow-up da equipe pelo WhatsApp API do Híbrido' do # rubocop:disable RSpec/DescribeClass
  include CrmHybridHelpers

  around do |example|
    with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '*', CRM_KANBAN_ENABLED: 'true') { example.run }
  end

  let!(:scenario) { build_crm_hybrid_scenario }
  let(:text) { 'Oi! Conseguiu ver o orçamento?' }

  def team_follow_up(scn = scenario, source: nil, metadata: {}, due_at: 10.minutes.ago)
    base = { 'message_body' => text }
    base['source'] = source if source
    scn[:account].crm_follow_ups.create!(
      card: scn[:card], conversation: scn[:conversation], contact: scn[:contact], title: 'Retomar',
      due_at: due_at, timezone: 'UTC', automation_mode: :auto_send_message, created_by: scn[:user],
      metadata: base.merge(metadata)
    )
  end

  describe Crm::FollowUps::AutoSendValidator do
    it 'aceita sem modelo fora das 24h quando o Híbrido está pronto no horário do envio' do
      expect { team_follow_up(due_at: 2.hours.from_now) }.not_to raise_error
    end

    it 'continua exigindo modelo quando a caixa não tem Híbrido' do
      plain = build_crm_hybrid_scenario(hybrid: false)

      expect { team_follow_up(plain) }
        .to raise_error(ActiveRecord::RecordInvalid, include('template fallback is required outside the messaging window'))
    end

    it 'continua exigindo modelo quando o Híbrido está desconectado' do
      scenario[:connection].update!(status: 'disconnected')

      expect { team_follow_up }
        .to raise_error(ActiveRecord::RecordInvalid, include('template fallback is required outside the messaging window'))
    end

    it 'continua exigindo modelo quando a origem crm_follow_up foi desligada' do
      scenario[:connection].update!(disabled_origins: ['crm_follow_up'])

      expect { team_follow_up }
        .to raise_error(ActiveRecord::RecordInvalid, include('template fallback is required outside the messaging window'))
    end

    it 'continua exigindo modelo quando a conta não está no piloto do Híbrido' do
      with_modified_env(WHATSAPP_HYBRID_ACCOUNT_IDS: '') do
        expect { team_follow_up }
          .to raise_error(ActiveRecord::RecordInvalid, include('template fallback is required outside the messaging window'))
      end
    end

    it 'aceita com modelo escolhido, como sempre' do
      expect { team_follow_up(metadata: { 'template_name' => 'retomada_orcamento', 'template_language' => 'pt_BR' }) }
        .not_to raise_error
    end
  end

  describe Crm::FollowUps::MessageSender do
    def perform(follow_up)
      described_class.new(follow_up: follow_up).perform
    end

    it 'manda o texto como sessão (sem modelo) pelo Híbrido, com a origem crm_follow_up' do
      follow_up = team_follow_up(source: 'manual')

      result = nil
      expect { result = perform(follow_up) }.to change(Message, :count).by(1)

      expect(result.status).to eq(:sent)
      expect(result.message.content).to eq(text)
      expect(result.message.content_attributes).to include('crm_follow_up_id' => follow_up.id, 'crm_follow_up_transport' => 'whatsapp_api')
      expect(result.message.content_attributes).not_to have_key('template_params')
      expect(follow_up.reload.metadata).to include('sent_message_id' => result.message.id, 'send_mode' => 'session')
      expect(WhatsappHybrid::Router.new(scenario[:conversation]).origin_of(result.message)).to eq('crm_follow_up')
    end

    it 'vale também para o follow-up de etapa do funil' do
      follow_up = team_follow_up(source: 'stage_automation')

      result = perform(follow_up)

      expect(result.status).to eq(:sent)
      expect(result.message.content_attributes).to include('crm_follow_up_transport' => 'whatsapp_api')
    end

    it 'vale para o follow-up criado dentro das 24h que venceu fora delas' do
      inside = build_crm_hybrid_scenario(last_inbound_ago: 1.hour.ago)
      follow_up = team_follow_up(inside, due_at: 1.hour.from_now)
      inside[:conversation].messages.incoming.last.update!(created_at: 30.hours.ago)

      result = perform(follow_up)

      expect(result.status).to eq(:sent)
      expect(result.message.content_attributes).to include('crm_follow_up_transport' => 'whatsapp_api')
    end

    it 'com modelo escolhido continua no caminho de modelo da oficial' do
      follow_up = team_follow_up(metadata: { 'template_name' => 'retomada_orcamento', 'template_language' => 'pt_BR' })

      result = perform(follow_up)

      expect(result.status).to eq(:sent)
      expect(result.message.content_attributes).to include('crm_follow_up_send_mode' => 'template')
      expect(result.message.content_attributes).not_to have_key('crm_follow_up_transport')
    end

    it 'dentro das 24h manda a sessão normal, sem marcar o transporte' do
      inside = build_crm_hybrid_scenario(last_inbound_ago: 1.hour.ago)
      follow_up = team_follow_up(inside)

      result = perform(follow_up)

      expect(result.status).to eq(:sent)
      expect(result.message.content_attributes).not_to have_key('crm_follow_up_transport')
    end

    it 'falha com whatsapp_api_unavailable, sem mensagem, quando o Híbrido caiu depois do agendamento' do
      follow_up = team_follow_up(due_at: 2.hours.from_now)
      scenario[:connection].update!(status: 'disconnected')

      result = nil
      expect { result = perform(follow_up) }.not_to change(Message, :count)

      expect(result.status).to eq(:failed)
      expect(result.error).to eq('whatsapp_api_unavailable')
    end

    it 'caixa que nunca teve Híbrido segue como hoje (template_name_required)' do
      plain = build_crm_hybrid_scenario(hybrid: false)
      follow_up = team_follow_up(plain, metadata: { 'template_name' => 'x', 'template_language' => 'pt_BR' })
      follow_up.update_columns(metadata: { 'source' => 'manual', 'message_body' => text }) # rubocop:disable Rails/SkipsModelValidations

      result = nil
      expect { result = perform(follow_up) }.not_to change(Message, :count)

      expect(result.status).to eq(:failed)
      expect(result.error).to eq('template_name_required')
    end

    it 'ignora delivery_transport forjado: sem Híbrido pronto, nenhum texto livre sai' do
      plain = build_crm_hybrid_scenario(hybrid: false)
      follow_up = team_follow_up(plain, source: 'ai_followup', metadata: { 'template_name' => 'x', 'template_language' => 'pt_BR' })
      follow_up.update_columns(metadata: { 'source' => 'manual', 'message_body' => text, 'delivery_transport' => 'whatsapp_api' }) # rubocop:disable Rails/SkipsModelValidations

      result = nil
      expect { result = perform(follow_up.reload) }.not_to change(Message, :count)

      expect(result.status).to eq(:failed)
      expect(result.error).to eq('template_name_required')
    end

    it 'sai pelo roteador do Híbrido de verdade (WAHA) com a origem crm_follow_up' do
      client = instance_double(Waha::Client)
      allow(Waha::Client).to receive(:new).and_return(client)
      allow(client).to receive_messages(check_contact_exists: { 'numberExists' => true, 'chatId' => '5511937016094@c.us' },
                                        new_message_id: '3EB0TEAM', send_text: { 'id' => 'true_5511937016094@c.us_3EB0TEAM' },
                                        start_typing: {}, stop_typing: {})
      allow(Kernel).to receive(:sleep)
      Redis::Alfred.delete("whatsapp_hybrid:chat_id:#{scenario[:connection].session_name}:5511937016094")
      follow_up = team_follow_up(source: 'manual')

      message = perform(follow_up).message
      Whatsapp::SendOnWhatsappService.new(message: message).perform

      expect(client).to have_received(:send_text).with(hash_including(session: scenario[:connection].session_name,
                                                                      text: text, id: '3EB0TEAM'))
      expect(message.reload.content_attributes).to include('whatsapp_transport' => 'web', 'whatsapp_transport_origin' => 'crm_follow_up')
    end

    it 'não vira falha quando o Híbrido cai bem entre o envio e a gravação de sent_message_id (corrida, revisão #1349)' do
      follow_up = team_follow_up(source: 'manual')
      sender = described_class.new(follow_up: follow_up)
      # persist_sent_message! grava sent_message_id com um update! no próprio follow_up (ainda pending), que
      # revalida pelo AutoSendValidator. Se o Híbrido cair bem nesse intervalo, a revalidação não pode
      # transformar o envio que já aconteceu em erro.
      allow(sender).to receive(:deliver_message!).and_wrap_original do |original|
        message = original.call
        scenario[:connection].update!(status: 'disconnected')
        message
      end

      result = sender.perform

      expect(result.status).to eq(:sent)
      expect(follow_up.reload.metadata).to include('sent_message_id' => result.message.id)
    end
  end

  describe Crm::FollowUps::DueProcessor do
    before { allow(Crm::FollowUps::Broadcaster).to receive(:broadcast_due) }

    it 'marca como atrasado com send_error whatsapp_api_unavailable (sem estourar) quando o Híbrido caiu' do
      follow_up = team_follow_up(due_at: 2.hours.from_now)
      scenario[:connection].update!(status: 'disconnected')
      follow_up.update_columns(due_at: 5.minutes.ago) # rubocop:disable Rails/SkipsModelValidations

      described_class.new(now: Time.current).perform

      expect(follow_up.reload.status).to eq('overdue')
      expect(follow_up.metadata).to include('send_error' => 'whatsapp_api_unavailable')
    end

    it 'envia pelo Híbrido e fecha o follow-up' do
      follow_up = team_follow_up(source: 'manual')

      described_class.new(now: Time.current).perform

      expect(follow_up.reload.status).to eq('done')
      expect(follow_up.metadata).to include('send_mode' => 'session')
    end
  end

  describe Crm::StageAutomations::StepExecutor do
    it 'cria o follow-up de etapa sem modelo e ele sai pelo Híbrido no vencimento' do
      automation = scenario[:account].crm_stage_automations.create!(
        pipeline: scenario[:card].pipeline, stage: scenario[:card].stage, name: 'Etapa', trigger_event: :on_enter, created_by: scenario[:user]
      )
      config = { title: 'Retomar', automation_mode: 'auto_send_message',
                 metadata: { message_body: text, delivery_transport: 'whatsapp_api' } }
      step = automation.steps.create!(
        account: scenario[:account], position: 0, delay_seconds: 3600, action_type: :create_follow_up, action_config: config
      )

      result = described_class.new(card: scenario[:card], step: step, actor: scenario[:user]).perform
      follow_up = Crm::FollowUp.find(result.payload[:follow_up_id])

      expect(result.status).to eq(:ok)
      expect(follow_up.metadata).to include('source' => 'stage_automation', 'message_body' => text)
      expect(follow_up.metadata).not_to have_key('delivery_transport')
      sent = Crm::FollowUps::MessageSender.new(follow_up: follow_up).perform
      expect(sent.status).to eq(:sent)
      expect(sent.message.content_attributes).to include('crm_follow_up_transport' => 'whatsapp_api')
    end

    it 'sem Híbrido a etapa falha ao criar, como hoje (modelo obrigatório)' do
      plain = build_crm_hybrid_scenario(hybrid: false)
      automation = plain[:account].crm_stage_automations.create!(
        pipeline: plain[:card].pipeline, stage: plain[:card].stage, name: 'Etapa', trigger_event: :on_enter, created_by: plain[:user]
      )
      step = automation.steps.create!(
        account: plain[:account], position: 0, delay_seconds: 3600, action_type: :create_follow_up,
        action_config: { title: 'Retomar', automation_mode: 'auto_send_message', metadata: { message_body: text } }
      )

      result = described_class.new(card: plain[:card], step: step, actor: plain[:user]).perform

      expect(result.status).to eq(:failed)
      expect(result.error).to include('template fallback is required')
    end
  end
end
