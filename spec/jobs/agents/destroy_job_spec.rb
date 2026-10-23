require 'rails_helper'

RSpec.describe Agents::DestroyJob do
  subject(:job) { described_class.perform_later(account, user) }

  let!(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:team1) { create(:team, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let(:store) { Conversations::UnreadCounts::FilteredCountStore }

  before do
    create(:team_member, team: team1, user: user)
    create(:inbox_member, inbox: inbox, user: user)
    create(:conversation, account: account, assignee: user, inbox: inbox)
  end

  it 'enqueues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(account, user)
      .on_queue('low')
  end

  describe '#perform' do
    it 'remove inboxes, teams, and conversations when removed from account' do
      described_class.perform_now(account, user)

      user.reload
      expect(user.teams.length).to eq 0
      expect(user.inboxes.length).to eq 0
      expect(user.notification_settings.length).to eq 0
      expect(user.assigned_conversations.where(account: account).length).to eq 0
    end

    # #2095: com o id de quem saiu, o card não se grava mais (Crm::Card#validate_owner_account).
    # Só com a flag crm_arquivados (decisão do Rodrigo, 23/10); desligada, como na main.
    context 'with CRM cards owned by the user who left' do
      let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: user) }
      let!(:mine) do
        pipeline, stage = pipeline_and_stage
        account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Do que sai', owner: user, status: :archived)
      end

      it 'solta os cards de quem saiu da conta, e só os desta conta, com a flag crm_arquivados' do
        account.enable_features!(:crm_arquivados)
        other_account = create(:account)
        create(:account_user, account: other_account, user: user)
        other_pipeline, other_stage = create_crm_pipeline(account: other_account, user: user)
        elsewhere = other_account.crm_cards.create!(pipeline: other_pipeline, stage: other_stage, title: 'Outra conta', owner: user)

        described_class.perform_now(account, user)

        expect(mine.reload.owner_id).to be_nil
        expect(elsewhere.reload.owner_id).to eq(user.id)
        expect(mine.update(status: :open)).to be(true)
      end

      it 'sem a flag crm_arquivados, deixa o card com o dono de antes, como na main' do
        described_class.perform_now(account, user)

        expect(mine.reload.owner_id).to eq(user.id)
        expect(user.assigned_conversations.where(account: account)).to be_empty
      end
    end

    it 'invalidates saved filter snapshots when assigned conversations are unassigned' do
      account.enable_features!(:unread_count_for_filters)

      expect do
        described_class.perform_now(account, user)
      end.to change { store.conversation_version(account.id) }.by(1)
    end
  end
end
