module Autonomia
  module Agents
    module Knowledge
      # Processa a ingestão de uma fonte de forma síncrona (embeddings são chamadas curtas — não há
      # background OpenAI aqui, logo não há poll). Idempotente via token-guard: só age se a fonte
      # ainda estiver processing E o sync_token for o desta execução; toda escrita posterior
      # (mark_ready!/mark_failed!) só vence se o token continuar ativo (anti-supersede).
      class ProcessJob < ApplicationJob
        queue_as :medium

        def perform(source_id, token, before_material_snapshot_digest = nil,
                    before_material_snapshot_session_id = nil)
          source = Autonomia::Agents::Source.for_kept_agents.find_by(id: source_id)
          return if source.blank? || !active?(source, token)

          snapshot = {
            digest: before_material_snapshot_digest || source.material_projection.material_snapshot_digest,
            session_id: before_material_snapshot_session_id
          }
          process_source(source, token, snapshot)
        rescue StandardError => e
          handle_error(source, token, e, snapshot)
        end

        private

        def active?(source, token)
          source.processing? && source.sync_token == token
        end

        def mark_failed(source, token, message)
          return if source.blank?

          source.mark_failed!(token, message)
        end

        def process_source(source, token, snapshot)
          count = Ingestor.new(source: source, token: token).perform
          source.mark_ready!(token, chunk_count: count)
          Reviewer.new(source: source, token: token).review_source!(
            before_material_snapshot_digest: snapshot[:digest],
            expected_session_id: snapshot[:session_id]
          )
          Reviewer.recompute_overall!(source.agent)
          finalize_material_change(source, token, snapshot)
        end

        def recover_failed_source(source, token, message, snapshot, preserve_generation: false)
          if preserve_generation
            handle_empty_extraction(source, token, message)
          else
            mark_failed(source, token, message)
          end
          finalize_material_change(source, token, snapshot)
        end

        def finalize_material_change(source, token, snapshot)
          return if source.blank? || snapshot.blank? || snapshot[:digest].blank?

          source.reload
          return unless source.sync_token == token

          Autonomia::Agents::MaterialProjection.invalidate_if_digest_changed!(
            agent: source.agent,
            before_digest: snapshot[:digest],
            after: source.material_projection,
            expected_session_id: snapshot[:session_id]
          )
        rescue StandardError => e
          Rails.logger.warn(
            '[Autonomia::Agents::Knowledge::ProcessJob] material invalidation degraded ' \
            "source=#{source&.id} #{e.class}: #{e.message}"
          )
          nil
        end

        def handle_error(source, token, error, snapshot)
          return if error.is_a?(Ingestor::Superseded)

          if error.is_a?(Ingestor::EmptyExtraction)
            recover_failed_source(source, token, error.message, snapshot, preserve_generation: true)
          elsif error.is_a?(Processors::Base::UnsupportedFormat)
            recover_failed_source(source, token, "unsupported_format: #{error.message}", snapshot)
          elsif extraction_error?(error)
            recover_failed_source(source, token, error.message, snapshot)
          else
            log_unexpected_error(source, error)
            recover_failed_source(source, token, 'ingestion_error', snapshot)
          end
        end

        def extraction_error?(error)
          error.is_a?(Processors::Base::ExtractionError) ||
            error.is_a?(Autonomia::Agents::EmbeddingService::EmbeddingError)
        end

        def log_unexpected_error(source, error)
          Rails.logger.error(
            "[Autonomia::Agents::Knowledge::ProcessJob] source=#{source&.id} #{error.class}: #{error.message}"
          )
        end

        def handle_empty_extraction(source, token, message)
          return if source.blank?

          if Autonomia::Agents::KnowledgeEntry.where(source_id: source.id).exists?
            Rails.logger.warn(
              "[Autonomia::Agents::Knowledge::ProcessJob] empty re-ingest source=#{source.id} " \
              "(#{message}) — preserving previous generation, KB kept retrievable"
            )
            source.restore_previous_generation!(token)
          else
            mark_failed(source, token, message)
          end
        end
      end
    end
  end
end
