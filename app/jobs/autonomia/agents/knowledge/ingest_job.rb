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

          token = source.begin_ingestion!
          ProcessJob.perform_later(source.id, token)
        end
      end
    end
  end
end
