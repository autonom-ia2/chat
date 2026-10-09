require 'rails_helper'

RSpec.describe 'Autonomia::Agents::MaterialProjection', type: :service do
  let(:account) { create(:account) }
  let(:service_class) { Autonomia::Agents::MaterialProjection }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Clara', agent_type: 'custom', status: :active, enabled: true,
      instruction: 'Atenda o cliente.'
    )
  end
  let(:vector) { Array.new(1536, 0.01) }

  def create_source(status: :ready, review_status: 'accepted', kind: :knowledge, summary: nil,
                    fingerprint: nil)
    Autonomia::Agents::Source.create!(
      account: account, agent: agent, source_type: 'txt', status: status, review_status: review_status,
      review_summary: summary, kind: kind, metadata: fingerprint ? { 'fingerprint' => fingerprint } : {}
    )
  end

  def create_entry(source, content: 'frete e horário de atendimento', embedding: nil)
    Autonomia::Agents::KnowledgeEntry.create!(
      account: account, agent: agent, source: source, content: content, status: :ready,
      chunk_index: 0, metadata: {}, embedding: embedding
    )
  end

  def projection
    service_class.new(agent: agent).call
  end

  def decision_for(source)
    projection.decision_for(source)
  end

  describe 'screen state and usage projection' do
    it 'presents a pending knowledge source as uploading and does not use it' do
      source = create_source(status: :pending)

      expect(decision_for(source)).to include(screen_state: 'uploading', uses: false)
      expect(projection.used_source_ids).to be_empty
      expect(projection.rejected_source_ids).to include(source.id)
    end

    it 'presents a processing knowledge source as reading and does not use it' do
      source = create_source(status: :processing)

      expect(decision_for(source)).to include(screen_state: 'reading', uses: false)
      expect(projection.used_source_ids).to be_empty
      expect(projection.rejected_source_ids).to include(source.id)
    end

    it 'presents a failed source without a usable generation as unreadable' do
      source = create_source(status: :failed)

      expect(decision_for(source)).to include(screen_state: 'unreadable', uses: false)
      expect(projection.used_source_ids).to be_empty
      expect(projection.rejected_source_ids).to include(source.id)
    end

    it 'presents a source that needs another file and never uses its old entries' do
      source = create_source(review_status: 'needs_resend')
      create_entry(source)

      expect(decision_for(source)).to include(screen_state: 'needs_another_file', uses: false)
      expect(projection.used_source_ids).to be_empty
      expect(projection.rejected_source_ids).to include(source.id)
    end

    it 'presents a source awaiting review and never uses its old entries' do
      source = create_source(review_status: 'needs_review')
      create_entry(source)

      expect(decision_for(source)).to include(screen_state: 'not_reviewed', uses: false)
      expect(projection.used_source_ids).to be_empty
      expect(projection.rejected_source_ids).to include(source.id)
    end

    it 'presents an accepted ready source as ready and returns its id as used' do
      source = create_source
      create_entry(source)

      expect(decision_for(source)).to include(screen_state: 'ready', uses: true, uses_reason: nil)
      expect(projection.used_source_ids).to contain_exactly(source.id)
      expect(projection.rejected_source_ids).to be_empty
    end

    it 'keeps a failed source ready when its accepted previous generation is usable' do
      source = create_source(status: :failed)
      create_entry(source)

      expect(decision_for(source)).to include(screen_state: 'ready', uses: true, uses_reason: nil)
      expect(projection.used_source_ids).to contain_exactly(source.id)
      expect(projection.rejected_source_ids).to be_empty
    end

    it 'keeps a legacy source with no review status ready when it has entries' do
      source = create_source(review_status: nil)
      create_entry(source)

      expect(decision_for(source)).to include(screen_state: 'ready', uses: true, uses_reason: nil)
      expect(projection.used_source_ids).to contain_exactly(source.id)
      expect(projection.rejected_source_ids).to be_empty
    end

    it 'marks an out-of-business source unused when another accepted source is in scope' do
      in_scope = create_source
      out_of_business = create_source(summary: 'Fora do negócio: seguros')
      create_entry(in_scope)
      create_entry(out_of_business)

      expect(decision_for(out_of_business)).to include(
        screen_state: 'out_of_business_not_used', uses: false, uses_reason: 'out_of_business'
      )
      expect(decision_for(in_scope)).to include(screen_state: 'ready', uses: true)
      expect(projection.used_source_ids).to contain_exactly(in_scope.id)
      expect(projection.rejected_source_ids).to contain_exactly(out_of_business.id)
    end

    it 'keeps all accepted out-of-business sources as the explicit fallback' do
      first = create_source(summary: 'Fora do negócio: seguros')
      second = create_source(summary: 'Fora do negócio: consórcios')
      create_entry(first)
      create_entry(second)

      expect(decision_for(first)).to include(
        screen_state: 'out_of_business_used', uses: true, uses_reason: 'out_of_business'
      )
      expect(decision_for(second)).to include(
        screen_state: 'out_of_business_used', uses: true, uses_reason: 'out_of_business'
      )
      expect(projection.used_source_ids).to contain_exactly(first.id, second.id)
      expect(projection.rejected_source_ids).to be_empty
    end

    it 'does not project media into the knowledge states or usage ids' do
      media = create_source(kind: :media, review_status: nil)
      create_entry(media)

      expect(decision_for(media)).to be_nil
      expect(projection.used_source_ids).to be_empty
      expect(projection.rejected_source_ids).to contain_exactly(media.id)
    end

    it 'uses preloaded sources and entry aggregates without querying associations' do
      source = create_source(fingerprint: 'fp-clara-v1')
      entry = create_entry(source)
      entry_versions = {
        source.id => { ready_count: 1, latest_updated_at: entry.updated_at }
      }

      allow(ActiveRecord::Base).to receive(:connection).and_raise('preloaded projection must not query')
      allow(agent).to receive(:sources).and_raise('preloaded projection must not load sources')
      allow(source).to receive(:knowledge_entries).and_raise('preloaded projection must not load entries')

      preloaded = service_class.new(
        agent: agent, sources: [source], entry_versions: entry_versions
      ).call

      expect(preloaded.decision_for(source)).to include(screen_state: 'ready', uses: true)
      expect(preloaded.used_source_ids).to contain_exactly(source.id)
      expect(preloaded.rejected_source_ids).to be_empty
    end

    it 'returns a deterministic complete snapshot and typed TestDigest input' do
      first_source = create_source(fingerprint: 'fp-first')
      second_source = create_source(fingerprint: 'fp-second')
      first_entry = create_entry(first_source)
      second_entry = create_entry(second_source)
      entry_versions = {
        first_source.id => { ready_count: 1, latest_updated_at: first_entry.updated_at },
        second_source.id => { ready_count: 1, latest_updated_at: second_entry.updated_at }
      }

      first = service_class.new(
        agent: agent, sources: [first_source, second_source], entry_versions: entry_versions
      ).call
      second = service_class.new(
        agent: agent, sources: [second_source, first_source], entry_versions: entry_versions
      ).call

      expect(first.material_snapshot_state).to eq('complete')
      expect(first.material_snapshot_digest).to start_with('sha256:')
      expect(first.material_snapshot_digest.length).to eq(7 + 64)
      expect(first.material_snapshot_digest).to eq(second.material_snapshot_digest)
      expect(first.test_digest_input(with_knowledge_effective: true)).to include(
        material_snapshot_digest: first.material_snapshot_digest,
        material_snapshot_state: 'complete',
        source_ids: contain_exactly(first_source.id, second_source.id),
        source_fingerprints: {
          first_source.id => 'fp-first', second_source.id => 'fp-second'
        },
        knowledge_entry_updated_at: [first_entry.updated_at, second_entry.updated_at].max.iso8601,
        with_knowledge_effective: true
      )
    end

    it 'does not change the snapshot for pending, failed, out-of-business, or media changes outside usage' do
      used_source = create_source(fingerprint: 'fp-used-v1')
      pending_source = create_source(status: :pending, fingerprint: 'fp-pending-v1')
      failed_source = create_source(status: :failed, fingerprint: 'fp-failed-v1')
      out_of_business_source = create_source(
        summary: 'Fora do negócio: seguros', fingerprint: 'fp-out-v1'
      )
      media_source = create_source(kind: :media, review_status: nil, fingerprint: 'fp-media-v1')
      create_entry(used_source)
      create_entry(out_of_business_source)
      create_entry(media_source)

      baseline = projection

      pending_source.update!(status: :processing, metadata: { 'fingerprint' => 'fp-pending-v2' })
      failed_source.update!(status: :ready, metadata: { 'fingerprint' => 'fp-failed-v2' })
      out_of_business_source.update!(metadata: { 'fingerprint' => 'fp-out-v2' })
      media_source.update!(metadata: { 'fingerprint' => 'fp-media-v2' })
      changed = projection

      expect(changed.used_source_ids).to contain_exactly(used_source.id)
      expect(changed.material_snapshot_digest).to eq(baseline.material_snapshot_digest)
    end

    it 'does not change the snapshot when a failed source preserves its usable generation' do
      source = create_source(fingerprint: 'fp-preserved')
      create_entry(source)
      baseline = projection

      source.update!(status: :failed)
      changed = projection

      expect(decision_for(source)).to include(screen_state: 'ready', uses: true)
      expect(changed.used_source_ids).to contain_exactly(source.id)
      expect(changed.material_snapshot_digest).to eq(baseline.material_snapshot_digest)
    end

    it 'changes the snapshot when a used fingerprint or ready entry version changes' do
      source = create_source(fingerprint: 'fp-used-v1')
      entry = create_entry(source)
      baseline = projection

      source.update!(metadata: { 'fingerprint' => 'fp-used-v2' })
      fingerprint_changed = projection
      expect(fingerprint_changed.material_snapshot_digest).not_to eq(baseline.material_snapshot_digest)

      entry.update_columns(updated_at: entry.updated_at + 1.hour) # rubocop:disable Rails/SkipsModelValidations
      entry_changed = projection
      expect(entry_changed.material_snapshot_digest).not_to eq(fingerprint_changed.material_snapshot_digest)
    end
  end

  describe 'Retriever parity' do
    let(:embedding_service) { instance_double(Autonomia::Agents::EmbeddingService) }

    let!(:in_scope_source) { create_source }
    let!(:out_of_business_source) { create_source(summary: 'Fora do negócio: seguros') }
    let!(:media_source) { create_source(kind: :media, review_status: nil) }
    let!(:needs_review_source) { create_source(review_status: 'needs_review') }

    before do
      create_entry(in_scope_source, embedding: vector)
      create_entry(out_of_business_source, embedding: vector)
      create_entry(media_source, embedding: vector)
      create_entry(needs_review_source, embedding: vector)
      allow(embedding_service).to receive(:embed).and_return(vector)
      allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedding_service)
    end

    it 'uses the same knowledge source ids in the projection and Retriever' do
      expected_ids = [in_scope_source.id]

      expect(projection.used_source_ids).to match_array(expected_ids)
      expect(projection.rejected_source_ids).to contain_exactly(
        out_of_business_source.id, media_source.id, needs_review_source.id
      )

      result = Autonomia::Agents::Retriever.new(agent: agent).retrieve('frete', top_k: 10)

      expect(result.map(&:source_id)).to match_array(expected_ids)
    end
  end

  describe 'Retriever parity for the all-out-of-business fallback' do
    let(:embedding_service) { instance_double(Autonomia::Agents::EmbeddingService) }
    let!(:first_source) { create_source(summary: 'Fora do negócio: seguros') }
    let!(:second_source) { create_source(summary: 'Fora do negócio: consórcios') }

    before do
      create_entry(first_source, embedding: vector)
      create_entry(second_source, embedding: vector)
      allow(embedding_service).to receive(:embed).and_return(vector)
      allow(Autonomia::Agents::EmbeddingService).to receive(:new).and_return(embedding_service)
    end

    it 'uses every accepted source when all accepted sources are out of business' do
      expected_ids = [first_source.id, second_source.id]

      expect(projection.used_source_ids).to match_array(expected_ids)
      expect(projection.rejected_source_ids).to be_empty

      result = Autonomia::Agents::Retriever.new(agent: agent).retrieve('frete', top_k: 10)

      expect(result.map(&:source_id)).to match_array(expected_ids)
    end
  end

  describe '.invalidate_if_digest_changed!' do
    let(:after_projection) do
      instance_double(Autonomia::Agents::MaterialProjection::Result, material_snapshot_digest: 'new-digest')
    end

    before { agent.update!(status: :draft) }

    it 'keeps a pending test that started after the material writer snapshot' do
      agent.update!(config: {
                      '_autonomia_agents_redesign' => {
                        'version' => 1, 'test_invalidated_by' => nil,
                        'test' => { 'session_id' => 'new-pending-session', 'completion' => 'pending' }
                      }
                    })

      result = service_class.invalidate_if_digest_changed!(
        agent: agent, before_digest: 'old-digest', after: after_projection,
        expected_session_id: 'writer-session'
      )

      expect(result).to be(false)
      expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to include(
        'session_id' => 'new-pending-session', 'completion' => 'pending'
      )
    end

    it 'keeps a completed test that started after the material writer snapshot' do
      agent.update!(config: {
                      '_autonomia_agents_redesign' => {
                        'version' => 1, 'test_invalidated_by' => nil,
                        'test' => { 'session_id' => 'new-completed-session', 'completion' => 'completed' }
                      }
                    })

      result = service_class.invalidate_if_digest_changed!(
        agent: agent, before_digest: 'old-digest', after: after_projection,
        expected_session_id: 'writer-session'
      )

      expect(result).to be(false)
      expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to include(
        'session_id' => 'new-completed-session', 'completion' => 'completed'
      )
    end

    it 'invalidates the writer session when it is still current' do
      agent.update!(config: {
                      '_autonomia_agents_redesign' => {
                        'version' => 1, 'test_invalidated_by' => nil,
                        'test' => { 'session_id' => 'writer-session', 'completion' => 'pending' }
                      }
                    })

      result = service_class.invalidate_if_digest_changed!(
        agent: agent, before_digest: 'old-digest', after: after_projection,
        expected_session_id: 'writer-session'
      )

      expect(result).to be(true)
      expect(agent.reload.config.dig('_autonomia_agents_redesign', 'test')).to be_nil
    end
  end
end
