module Autonomia
  module Agents
    module Knowledge
      # Submete a ingestão de uma fonte: marca processing + gera o sync_token (begin_ingestion!) e
      # delega o trabalho pesado (extração+embedding) ao ProcessJob. Separação submeter->processar
      # idêntica ao padrão Submit/Poll da Fase C. Re-sync = novo IngestJob (novo token supersede o
      # anterior; jobs velhos viram no-op pelo token-guard).
      class IngestJob < ApplicationJob
        queue_as :medium

        def perform(source_id)
          source = Autonomia::Agents::Source.for_kept_agents.find_by(id: source_id)
          return if source.blank?

          before_material_projection = source.material_projection
          before_material_snapshot_digest = before_material_projection.material_snapshot_digest
          before_material_snapshot_session_id = Autonomia::Agents::MaterialProjection.test_session_id(
            agent: source.agent
          )
          token = source.begin_ingestion!
          ProcessJob.perform_later(
            source.id, token, before_material_snapshot_digest, before_material_snapshot_session_id
          )
        end
      end
    end
  end
end
