module Autonomia
  module Agents
    module Knowledge
      # Processa a ingestão de uma fonte de forma síncrona (embeddings são chamadas curtas — não há
      # background OpenAI aqui, logo não há poll). Idempotente via token-guard: só age se a fonte
      # ainda estiver processing E o sync_token for o desta execução; toda escrita posterior
      # (mark_ready!/mark_failed!) só vence se o token continuar ativo (anti-supersede).
      class ProcessJob < ApplicationJob
        queue_as :medium

        def perform(source_id, token)
          source = Autonomia::Agents::Source.for_kept_agents.find_by(id: source_id)
          return if source.blank? || !active?(source, token)

          count = Ingestor.new(source: source, token: token).perform
          source.mark_ready!(token, chunk_count: count)
          # Revisor v2: avalia a fonte recém-ingerida (nota/confiança/resumo) e recomputa o MAPA DE
          # TEMAS + confiança geral. Guardados pelo mesmo token (anti-supersede) e best-effort: o
          # Reviewer faz rescue interno → nunca derruba a ingestão que já gravou o conhecimento.
          Reviewer.new(source: source, token: token).review_source!
          Reviewer.recompute_overall!(source.agent)
        rescue Ingestor::Superseded
          # Outra ingestão (re-sync) venceu o token enquanto extraíamos: este job vira no-op e NÃO
          # toca o conhecimento (que já pertence à geração nova). Nada a marcar.
          nil
        rescue Ingestor::EmptyExtraction => e
          # Re-sync extraiu vazio: se a fonte JÁ tinha conhecimento bom, PRESERVA a geração anterior
          # (não apaga, restaura o estado/recuperabilidade); só marca failed se nunca houve entries.
          handle_empty_extraction(source, token, e.message)
        rescue Processors::Base::UnsupportedFormat => e
          mark_failed(source, token, "unsupported_format: #{e.message}")
        rescue Processors::Base::ExtractionError,
               Autonomia::Agents::EmbeddingService::EmbeddingError => e
          mark_failed(source, token, e.message)
        rescue StandardError => e
          Rails.logger.error("[Autonomia::Agents::Knowledge::ProcessJob] source=#{source_id} #{e.class}: #{e.message}")
          mark_failed(source, token, 'ingestion_error')
        end

        private

        def active?(source, token)
          source.processing? && source.sync_token == token
        end

        def mark_failed(source, token, message)
          return if source.blank?

          source.mark_failed!(token, message)
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
