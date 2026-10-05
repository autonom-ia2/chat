require 'rails_helper'

# Guards the merge-safe metadata writes added for the Meta CAPI sync: neither the
# pipeline meta_sync PATCH nor the stage funnel_stage_type PATCH may clobber the
# sibling metadata['ai'] / metadata['goals'] keys written elsewhere.
RSpec.describe 'CRM meta_sync metadata API', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    if previous_value.nil?
      ENV.delete('CRM_KANBAN_ENABLED')
    else
      ENV['CRM_KANBAN_ENABLED'] = previous_value
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm/pipelines/:id (update_meta_sync!)' do
    it 'writes meta_sync while preserving metadata ai and goals' do
      account, user = create_account_and_user
      pipeline = account.crm_pipelines.create!(
        name: 'Funil', created_by: user, status: :active,
        metadata: { 'ai' => { 'tone' => 'formal' }, 'goals' => { 'monthly_target_cents' => 1000 } }
      )

      original_ai = pipeline.metadata['ai'].deep_dup

      patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
            params: { pipeline: { meta_sync: { enabled: true, events: { won: true, lost: false, moved: true },
                                               dataset_id: 'DS9' } } },
            headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      metadata = pipeline.reload.metadata
      expect(metadata['ai']).to eq(original_ai)
      expect(metadata['goals']).to eq('monthly_target_cents' => 1000)
      expect(metadata['meta_sync']).to eq(
        'enabled' => true,
        'events' => { 'won' => true, 'lost' => false, 'moved' => true },
        'dataset_id' => 'DS9'
      )
    end

    it 'leaves metadata untouched when no meta_sync payload is sent' do
      account, user = create_account_and_user
      pipeline = account.crm_pipelines.create!(name: 'Funil', created_by: user, status: :active, metadata: { 'ai' => { 'tone' => 'x' } })

      original_ai = pipeline.metadata['ai'].deep_dup

      patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
            params: { pipeline: { name: 'Funil 2' } },
            headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      metadata = pipeline.reload.metadata
      expect(metadata['ai']).to eq(original_ai)
      expect(metadata).not_to have_key('meta_sync')
    end

    context 'with the website-mode pixel_id (#1011)' do
      def patch_pixel(pixel_id)
        account, user = create_account_and_user
        pipeline = account.crm_pipelines.create!(name: 'Funil', created_by: user, status: :active,
                                                 metadata: { 'meta_sync' => { 'pixel_id' => '111' } })
        patch "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}",
              params: { pipeline: { meta_sync: { enabled: true, events: { won: true }, dataset_id: 'DS9', pixel_id: pixel_id } } },
              headers: auth_headers(user)
        expect(response).to have_http_status(:ok)
        pipeline.reload.metadata['meta_sync']
      end

      it 'stores a digits-only pixel id next to the dataset' do
        expect(patch_pixel(' 2164882667623689 ')).to include('dataset_id' => 'DS9', 'pixel_id' => '2164882667623689')
      end

      it 'clears the pixel id when it is blank' do
        expect(patch_pixel('')['pixel_id']).to be_nil
      end

      it 'drops a pixel id with non-digits or longer than 20 characters' do
        expect(patch_pixel('21648826abc')['pixel_id']).to be_nil
        expect(patch_pixel('1' * 21)['pixel_id']).to be_nil
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/crm/stages/:id (funnel_stage_type)' do
    def create_stage(account, user, metadata)
      pipeline = account.crm_pipelines.create!(name: 'Funil', created_by: user, status: :active)
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Qualificação', position: 0, metadata: metadata)
    end

    it 'sets a valid funnel_stage_type without dropping metadata ai' do
      account, user = create_account_and_user
      stage = create_stage(account, user, { 'ai' => { 'criteria' => 'keep-me' } })

      patch "/api/v1/accounts/#{account.id}/crm/stages/#{stage.id}",
            params: { stage: { funnel_stage_type: 'qualified' } },
            headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      metadata = stage.reload.metadata
      expect(metadata['funnel_stage_type']).to eq('qualified')
      expect(metadata['ai']).to eq('criteria' => 'keep-me')
    end

    it 'clears the classification for an invalid funnel_stage_type but keeps ai' do
      account, user = create_account_and_user
      stage = create_stage(account, user, { 'ai' => { 'criteria' => 'keep-me' }, 'funnel_stage_type' => 'qualified' })

      patch "/api/v1/accounts/#{account.id}/crm/stages/#{stage.id}",
            params: { stage: { funnel_stage_type: 'bogus' } },
            headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      metadata = stage.reload.metadata
      expect(metadata).not_to have_key('funnel_stage_type')
      expect(metadata['ai']).to eq('criteria' => 'keep-me')
    end

    it 'shallow-merges nested metadata without clobbering sibling keys' do
      account, user = create_account_and_user
      stage = create_stage(account, user, { 'ai' => { 'criteria' => 'keep-me' } })

      patch "/api/v1/accounts/#{account.id}/crm/stages/#{stage.id}",
            params: { stage: { metadata: { extra: 'value' } } },
            headers: auth_headers(user)

      expect(response).to have_http_status(:ok)
      metadata = stage.reload.metadata
      expect(metadata['extra']).to eq('value')
      expect(metadata['ai']).to eq('criteria' => 'keep-me')
    end
  end
end
