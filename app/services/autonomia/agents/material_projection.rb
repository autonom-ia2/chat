require 'digest'
require 'json'

class Autonomia::Agents::MaterialProjection
  REVIEW_REJECTIONS = %w[needs_resend needs_review].freeze
  REVIEW_SCREEN_STATES = { 'needs_resend' => 'needs_another_file', 'needs_review' => 'not_reviewed' }.freeze

  class << self
    def test_session_id(agent:)
      Autonomia::Agents::AgentStateStore.read(agent: agent).dig(:test, :session_id)
    end

    # A mudança de material só invalida um teste que ainda está no ciclo de rascunho. A chamada
    # acontece depois que o escritor liberou a row de Source; assim não há callback que tente
    # adquirir Agent enquanto o construtor já segura Source (ou o inverso).
    def invalidate_if_effective_change!(agent:, before:, after:, expected_session_id:)
      invalidate_if_digest_changed!(
        agent: agent, before_digest: before.material_snapshot_digest, after: after,
        expected_session_id: expected_session_id
      )
    end

    def invalidate_if_digest_changed!(agent:, before_digest:, after:, expected_session_id:)
      return false unless agent&.draft?
      return false if expected_session_id.blank?
      return false if before_digest.to_s == after.material_snapshot_digest.to_s

      Autonomia::Agents::AgentStateStore.invalidate_if_current!(
        agent: agent, reason: 'material', session_id: expected_session_id
      )
    end
  end

  Result = Struct.new(
    :decisions, :used_source_ids, :rejected_source_ids, :material_snapshot_digest,
    :material_snapshot_state, :source_fingerprints, :knowledge_entry_updated_at,
    keyword_init: true
  ) do
    def decision_for(source) = decisions[source.id]

    def test_digest_input(with_knowledge_effective:)
      {
        material_snapshot_digest: material_snapshot_digest,
        material_snapshot_state: material_snapshot_state,
        source_ids: used_source_ids,
        source_fingerprints: source_fingerprints,
        knowledge_entry_updated_at: knowledge_entry_updated_at && timestamp_string(knowledge_entry_updated_at),
        with_knowledge_effective: with_knowledge_effective
      }
    end

    private

    def timestamp_string(value) = value && (value.respond_to?(:iso8601) ? value.iso8601 : value.to_s)
  end

  def initialize(agent:, sources: nil, entry_versions: nil)
    @agent = agent
    @sources = sources
    @entry_versions = entry_versions
  end

  def call
    @call ||= build_result
  end

  private

  def build_result
    rows = source_rows
    versions = normalized_entry_versions(rows)
    knowledge_sources = rows.select(&:kind_knowledge?)
    all_accepted_out_of_business = all_accepted_out_of_business?(knowledge_sources)
    decisions, used_sources = project_decisions(rows, versions, all_accepted_out_of_business)
    snapshot = snapshot_for(rows, used_sources, versions)

    Result.new(
      decisions: decisions,
      material_snapshot_state: snapshot_state(knowledge_sources),
      **snapshot
    )
  end

  def snapshot_for(rows, used_sources, versions)
    used_source_ids = used_sources.map(&:id).sort
    source_fingerprints = used_sources.to_h do |source|
      [source.id, source.metadata.to_h['fingerprint'] || source.metadata.to_h[:fingerprint]]
    end
    {
      used_source_ids: used_source_ids,
      rejected_source_ids: (rows.map(&:id) - used_source_ids).sort,
      material_snapshot_digest: snapshot_digest(used_source_ids, source_fingerprints, versions),
      source_fingerprints: source_fingerprints,
      knowledge_entry_updated_at: used_sources.filter_map { |source| versions.dig(source.id, :latest_updated_at) }.max
    }
  end

  def project_decisions(rows, versions, all_accepted_out_of_business)
    decisions = {}
    used_sources = []

    rows.each do |source|
      decision = nil
      decision = source_decision(source, versions[source.id], all_accepted_out_of_business) if source.kind_knowledge?
      decisions[source.id] = decision
      used_sources << source if decision&.fetch(:uses, false)
    end

    [decisions, used_sources]
  end

  def source_decision(source, version, all_accepted_out_of_business)
    state = base_state(source, version)
    return { screen_state: state, uses: false } unless state == 'ready' && usable_review?(source)

    return { screen_state: 'ready', uses: true, uses_reason: nil } unless out_of_business?(source)

    out_of_business_decision(all_accepted_out_of_business)
  end

  def out_of_business_decision(all_accepted_out_of_business)
    state = all_accepted_out_of_business ? 'out_of_business_used' : 'out_of_business_not_used'
    { screen_state: state, uses: all_accepted_out_of_business, uses_reason: 'out_of_business' }
  end

  def all_accepted_out_of_business?(knowledge_sources)
    accepted_sources = knowledge_sources.select { |source| source.review_status == 'accepted' }
    accepted_sources.any? && accepted_sources.all? { |source| out_of_business?(source) }
  end

  def source_rows = (@source_rows ||= Array(@sources || @agent.sources.reload).to_a)

  def normalized_entry_versions(rows)
    return load_entry_versions(rows) if @entry_versions.nil?

    @entry_versions.each_with_object({}) do |(source_id, value), versions|
      versions[source_id.to_i] = normalize_entry_version(value)
    end
  end

  def normalize_entry_version(value)
    data = value.respond_to?(:to_h) ? value.to_h : { ready_count: value }
    {
      ready_count: entry_version_value(data, :ready_count, :count).to_i,
      latest_updated_at: entry_version_value(data, :latest_updated_at, :updated_at)
    }
  end

  def entry_version_value(data, *keys)
    keys.each do |key|
      value = data[key] || data[key.to_s]
      return value if value
    end
    nil
  end

  def load_entry_versions(rows)
    ids = rows.select(&:kind_knowledge?).map(&:id)
    return {} if ids.empty?

    Autonomia::Agents::KnowledgeEntry
      .where(account_id: @agent.account_id, autonomia_agent_id: @agent.id, source_id: ids, status: :ready)
      .group(:source_id)
      .pluck(:source_id, Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)'))
      .to_h { |source_id, count, latest| [source_id, { ready_count: count, latest_updated_at: latest }] }
  end

  def base_state(source, version)
    return pending_state(source) if pending_or_processing?(source)
    return review_state(source) if REVIEW_REJECTIONS.include?(source.review_status)
    return 'unreadable' unless ready_or_failed?(source)

    entry_state(version)
  end

  def pending_or_processing?(source) = source.pending? || source.processing?

  def ready_or_failed?(source) = source.ready? || source.failed?

  def entry_state(version) = version&.[](:ready_count)&.positive? ? 'ready' : 'unreadable'

  def pending_state(source) = source.pending? ? 'uploading' : 'reading'

  def review_state(source) = REVIEW_SCREEN_STATES.fetch(source.review_status, 'unreadable')

  def usable_review?(source) = source.review_status.nil? || source.review_status == 'accepted'

  def out_of_business?(source) = source.review_status == 'accepted' && Autonomia::Agents::Knowledge::Reviewer.out_of_business?(source.review_summary)

  def snapshot_state(knowledge_sources)
    return 'empty' if knowledge_sources.empty?

    return 'partial' if knowledge_sources.any? do |source|
      source.pending? || source.processing? || source.failed? || REVIEW_REJECTIONS.include?(source.review_status)
    end

    'complete'
  end

  def snapshot_digest(used_source_ids, fingerprints, versions)
    canonical = used_source_ids.map do |source_id|
      {
        source_id: source_id,
        fingerprint: fingerprints[source_id],
        knowledge_entry_updated_at: digest_timestamp_string(versions.dig(source_id, :latest_updated_at))
      }
    end
    "sha256:#{Digest::SHA256.hexdigest(JSON.generate(canonical))}"
  end

  def digest_timestamp_string(value) = value && (value.respond_to?(:iso8601) ? value.iso8601(6) : value.to_s)
end
