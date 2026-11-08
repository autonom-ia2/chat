require 'rails_helper'

# #1460 (repetir), #1461 (sem card) e #1462 (quem recebe).
RSpec.describe 'CRM reminders that repeat, without card and with chosen recipients', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    previous_value.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_value
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create_crm_agent(account: account, name: 'Paula').first }
  let(:other_agent) { create_crm_agent(account: account, name: 'Bruno').first }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: agent, title: 'Plano anual')
  end
  let(:base_url) { "/api/v1/accounts/#{account.id}/crm" }
  let(:next_monday) { Time.zone.now.in_time_zone('America/Sao_Paulo').next_occurring(:monday).change(hour: 10) }

  def create_reminder(user, follow_up)
    post "#{base_url}/follow_ups", params: { follow_up: { automation_mode: 'reminder_only', timezone: 'America/Sao_Paulo' }.merge(follow_up) },
                                   headers: auth_headers(user), as: :json
  end

  describe 'without a card (#1461)' do
    it 'creates a reminder that only lives in the calendar and is visible to its creator only' do
      create_reminder(agent, title: 'Pagar o aluguel', due_at: 2.hours.from_now.iso8601)

      expect(response).to have_http_status(:created)
      payload = response.parsed_body['payload']
      expect(payload['card_id']).to be_nil
      follow_up_id = payload['id']

      get "#{base_url}/follow_ups/#{follow_up_id}", headers: auth_headers(other_agent), as: :json
      expect(response).to have_http_status(:not_found)

      get "#{base_url}/follow_ups/#{follow_up_id}", headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:ok)
    end

    it 'links a customer without an open deal' do
      contact = account.contacts.create!(name: 'Roberto Alves')
      create_reminder(agent, title: 'Aniversário', contact_id: contact.id, due_at: 1.day.from_now.iso8601)

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['payload']['contact']['name']).to eq('Roberto Alves')
    end

    it 'refuses a message to the customer without a card' do
      create_reminder(agent, title: 'Mensagem', automation_mode: 'auto_send_message', due_at: 1.day.from_now.iso8601)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'lets who receives complete it, but only the creator changes or cancels it' do
      create_reminder(agent, title: 'Conferir o caixa', due_at: 1.day.from_now.iso8601,
                             recipient_mode: 'users', recipient_user_ids: [other_agent.id])
      id = response.parsed_body['payload']['id']

      post "#{base_url}/follow_ups/#{id}/cancel", headers: auth_headers(other_agent), as: :json
      expect(response).to have_http_status(:unauthorized)

      post "#{base_url}/follow_ups/#{id}/complete", headers: auth_headers(other_agent), as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']['status']).to eq('done')
    end

    it 'shows the reminder to the people who receive it' do
      create_reminder(agent, title: 'Conferir o caixa', due_at: 1.day.from_now.iso8601,
                             recipient_mode: 'users', recipient_user_ids: [other_agent.id])

      get "#{base_url}/follow_ups/#{response.parsed_body['payload']['id']}", headers: auth_headers(other_agent), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  # #2130: antes, o lembrete de uma vez era criado (201) e o DueProcessor o cancelava em silêncio.
  describe 'one-time reminder on an archived card' do
    before { card.update!(status: :archived) }

    it 'refuses it, saying why, in the account language' do
      account.update!(locale: 'pt_BR')

      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: 1.day.from_now.iso8601)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('message' => 'Este card está arquivado. Restaure o card antes de criar um lembrete.',
                                         'code' => 'card_archived')
      expect(account.crm_follow_ups.count).to eq(0)
    end

    it 'refuses a scheduled message to the customer too' do
      create_reminder(agent, card_id: card.id, title: 'Mensagem', automation_mode: 'auto_send_message', due_at: 1.day.from_now.iso8601)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('card_archived')
      expect(account.crm_follow_ups.count).to eq(0)
    end

    it 'refuses it when only the archive barrier sees the card archived' do
      card.update!(status: :open)
      allow(Crm::Cards::Archiver).to receive(:arquivado_sob_trava?).and_wrap_original do |original, card_id|
        Crm::Card.where(id: card_id).update_all(status: Crm::Card.statuses[:archived]) # rubocop:disable Rails/SkipsModelValidations
        original.call(card_id)
      end

      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: 1.day.from_now.iso8601)

      expect(response.parsed_body['code']).to eq('card_archived')
      expect(account.crm_follow_ups.count).to eq(0)
    end

    it 'still creates the reminder on an open card' do
      card.update!(status: :open)

      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: 1.day.from_now.iso8601)

      expect(response).to have_http_status(:created)
    end
  end

  describe 'who receives (#1462)' do
    it 'keeps the old behaviour when the panel does not send recipients' do
      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: 1.day.from_now.iso8601)

      expect(Crm::FollowUp.last).to be_recipients_legacy
    end

    it 'follows the card owner at the moment of the reminder' do
      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: 1.day.from_now.iso8601, recipient_mode: 'card_owner')
      follow_up = Crm::FollowUp.last
      card.update!(owner: admin)

      expect(Crm::FollowUps::RecipientResolver.new(follow_up.reload).users).to eq([admin])
    end

    it 'sends to a whole team' do
      team = account.teams.create!(name: 'financeiro')
      team.add_members([agent.id, other_agent.id])
      create_reminder(agent, title: 'Cobrar', due_at: 1.day.from_now.iso8601, recipient_mode: 'team', recipient_team_id: team.id)

      expect(Crm::FollowUps::RecipientResolver.new(Crm::FollowUp.last).users).to contain_exactly(agent, other_agent)
    end

    it 'refuses "whoever handles the customer" without a card' do
      create_reminder(agent, title: 'Ligar', due_at: 1.day.from_now.iso8601, recipient_mode: 'card_owner')

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('crm.follow_up.recipient_owner_needs_card')
    end

    it 'falls back to the creator when nobody is left to receive' do
      team = account.teams.create!(name: 'vazio')
      create_reminder(agent, title: 'Ligar', due_at: 1.day.from_now.iso8601, recipient_mode: 'team', recipient_team_id: team.id)

      expect(Crm::FollowUps::RecipientResolver.new(Crm::FollowUp.last).users).to eq([agent])
    end
  end

  describe 'repeating (#1460)' do
    it 'creates the series and only the first time as a reminder' do
      create_reminder(agent, card_id: card.id, title: 'Ligar para a Mariana', due_at: next_monday.iso8601,
                             recipient_mode: 'card_owner', recurrence: { frequency: 'weekly', weekdays: [1] })

      expect(response).to have_http_status(:created)
      payload = response.parsed_body['payload']
      expect(payload['series']['frequency']).to eq('weekly')
      expect(Crm::FollowUp.where(series_id: payload['series_id']).count).to eq(1)

      get "#{base_url}/follow_up_series/#{payload['series_id']}", headers: auth_headers(agent), as: :json
      series = response.parsed_body['payload']
      expect(series['next_occurrences'].size).to eq(5)
      expect(series['recipient_names']).to eq(['Paula'])
    end

    # #2101: antes, o 422 dizia "Ends on leaves no date to remind".
    it 'refuses a series on an archived card, saying why, in the account language' do
      account.update!(locale: 'pt_BR')
      card.update!(status: :archived)

      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: next_monday.iso8601, recurrence: { frequency: 'weekly', weekdays: [1] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('message' => 'Este card está arquivado. Restaure o card antes de criar um lembrete.',
                                         'code' => 'card_archived')
      expect(account.crm_follow_up_series.count).to eq(0)
      expect(account.crm_follow_ups.count).to eq(0)
    end

    it 'says it in English for an English account' do
      card.update!(status: :archived)

      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: next_monday.iso8601, recurrence: { frequency: 'weekly', weekdays: [1] })

      expect(response.parsed_body['message']).to eq('This card is archived. Restore it before creating a reminder.')
    end

    # A barreira do SeriesMaterializer (arquivado_sob_trava?) vê o card arquivado depois da conferência do Creator.
    it 'gives the same answer when only the materializer barrier sees the card archived' do
      allow(Crm::Cards::Archiver).to receive(:arquivado_sob_trava?).and_wrap_original do |original, card_id|
        Crm::Card.where(id: card_id).update_all(status: Crm::Card.statuses[:archived]) # rubocop:disable Rails/SkipsModelValidations
        original.call(card_id)
      end

      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: next_monday.iso8601, recurrence: { frequency: 'weekly', weekdays: [1] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('card_archived')
      expect(account.crm_follow_up_series.count).to eq(0)
    end

    it 'refuses repeating a message to the customer (phase 2)' do
      create_reminder(agent, card_id: card.id, title: 'Mensagem', due_at: next_monday.iso8601, automation_mode: 'snooze_conversation',
                             recurrence: { frequency: 'weekly', weekdays: [1] })

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'creates the next time once the current one is done, and never twice' do
      create_reminder(agent, title: 'Conferir o caixa', due_at: 1.hour.from_now.iso8601, recurrence: { frequency: 'daily' })
      first = Crm::FollowUp.last
      post "#{base_url}/follow_ups/#{first.id}/complete", headers: auth_headers(agent), as: :json

      Crm::FollowUpSeriesMaterializerJob.perform_now
      Crm::FollowUpSeriesMaterializerJob.perform_now

      times = Crm::FollowUp.where(series_id: first.series_id).order(:occurrence_at)
      expect(times.count).to eq(2)
      expect(times.last.occurrence_at - times.first.occurrence_at).to eq(1.day)
    end

    it 'pauses without erasing dates, stays silent while paused, resumes and ends' do
      create_reminder(agent, title: 'Conferir o caixa', due_at: 1.minute.ago.iso8601, recurrence: { frequency: 'daily' })
      follow_up = Crm::FollowUp.last
      series_url = "#{base_url}/follow_up_series/#{follow_up.series_id}"

      post "#{series_url}/pause", headers: auth_headers(agent), as: :json
      expect(response.parsed_body['payload']['status']).to eq('paused')
      expect(response.parsed_body['payload']['next_occurrences']).not_to be_empty

      expect(Crm::FollowUps::ReminderNotifier).not_to receive(:new)
      Crm::FollowUps::DueProcessor.new.perform
      expect(follow_up.reload.metadata['canceled_reason']).to eq('series_paused')

      post "#{series_url}/resume", headers: auth_headers(agent), as: :json
      expect(Crm::FollowUp.where(series_id: follow_up.series_id).pending.count).to eq(1)

      post "#{series_url}/end", headers: auth_headers(agent), as: :json
      expect(response.parsed_body['payload']['status']).to eq('ended')
      expect(Crm::FollowUp.where(series_id: follow_up.series_id).pending.count).to eq(0)
    end

    it 'changes this and all next times without touching what already happened' do
      create_reminder(agent, title: 'Ligar', due_at: 1.hour.from_now.iso8601, recurrence: { frequency: 'daily' })
      series_id = Crm::FollowUp.last.series_id

      patch "#{base_url}/follow_up_series/#{series_id}",
            params: { follow_up_series: { title: 'Ligar de manhã', due_at: next_monday.iso8601,
                                          recurrence: { frequency: 'weekly', weekdays: [1] } } },
            headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:ok)
      pending = Crm::FollowUp.where(series_id: series_id).pending
      expect(pending.count).to eq(1)
      expect(pending.first.title).to eq('Ligar de manhã')
      expect(pending.first.due_at.to_i).to eq(next_monday.to_i)
    end

    it 'keeps the chosen end when only the frequency changes, and only the creator changes it' do
      create_reminder(agent, title: 'Ligar', due_at: 1.hour.from_now.iso8601, recipient_mode: 'users', recipient_user_ids: [other_agent.id],
                             recurrence: { frequency: 'daily', ends_mode: 'after_count', occurrences_count: 4 })
      series_url = "#{base_url}/follow_up_series/#{Crm::FollowUp.last.series_id}"

      post "#{series_url}/pause", headers: auth_headers(other_agent), as: :json
      expect(response).to have_http_status(:unauthorized)

      patch series_url, params: { follow_up_series: { recurrence: { frequency: 'weekly', weekdays: [1] } } },
                        headers: auth_headers(agent), as: :json
      expect(response.parsed_body['payload']).to include('frequency' => 'weekly', 'ends_mode' => 'after_count', 'occurrences_count' => 4)
    end

    it 'filters the calendar by pipeline and keeps reminders without card' do
      pipeline, = pipeline_and_stage
      create_reminder(agent, title: 'Conferir o caixa', due_at: 1.hour.from_now.iso8601, recurrence: { frequency: 'daily' })
      create_reminder(agent, card_id: card.id, title: 'Ligar', due_at: 1.hour.from_now.iso8601, recurrence: { frequency: 'daily' })

      get "#{base_url}/calendar/events", params: { from: Time.current.iso8601, to: 3.days.from_now.iso8601, pipeline_id: pipeline.id },
                                         headers: auth_headers(agent)

      expect(response).to have_http_status(:ok)
      titles = response.parsed_body['payload'].select { |event| event['recurring'] }.map { |event| event['title'] }.uniq
      expect(titles).to contain_exactly('Conferir o caixa', 'Ligar')
    end

    it 'does not let another agent see a series without card' do
      create_reminder(agent, title: 'Ligar', due_at: 1.hour.from_now.iso8601, recurrence: { frequency: 'daily' })

      get "#{base_url}/follow_up_series/#{Crm::FollowUp.last.series_id}", headers: auth_headers(other_agent), as: :json
      expect(response).to have_http_status(:not_found)
    end

    it 'shows the next times in the calendar, marked as repeating' do
      create_reminder(agent, title: 'Conferir o caixa', due_at: 1.hour.from_now.iso8601, recurrence: { frequency: 'daily' })

      get "#{base_url}/calendar/events", params: { from: Time.current.iso8601, to: 5.days.from_now.iso8601 },
                                         headers: auth_headers(agent)

      events = response.parsed_body['payload'].select { |event| event['recurring'] }
      expect(events.count { |event| event['virtual'] }).to be >= 4
      expect(events.count { |event| !event['virtual'] }).to eq(1)
    end

    # #1568: as vezes calculadas trazem o mesmo responsável que a vez criada (o "Só os meus" do calendário).
    it 'gives the next times the same owner the created time has' do
      create_reminder(admin, title: 'Ligar toda semana', card_id: card.id, due_at: 1.hour.from_now.iso8601,
                             recurrence: { frequency: 'daily' })

      get "#{base_url}/calendar/events", params: { from: Time.current.iso8601, to: 3.days.from_now.iso8601 },
                                         headers: auth_headers(admin)

      events = response.parsed_body['payload'].select { |event| event['title'] == 'Ligar toda semana' }
      real = events.find { |event| !event['virtual'] }
      expect(real['assignee_id']).to eq(agent.id)
      expect(events.select { |event| event['virtual'] }.pluck('assignee_id').uniq).to eq([agent.id])
    end
  end
end
