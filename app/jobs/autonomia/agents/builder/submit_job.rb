module Autonomia
  module Agents
    class Builder
      # Roda a geração do Construtor de forma SÍNCRONA: uma chamada ao ResponsesClient (reasoning
      # baixo, alguns segundos) que já faz o parse, cria/edita o Agent e marca a thread `ready` —
      # sem PollJob/background. Um chat precisa de resposta rápida, não de uma operação de minutos.
      #
      # O `token` é o build_token ativo do BuildThread: toda escrita posterior (mark_ready!/
      # mark_failed! e agent.apply_builder_config!) é guardada por ele (anti-supersede). Se a thread
      # foi substituída por uma nova geração no meio do caminho, o run! vira no-op e nada é gravado.
      class SubmitJob < ApplicationJob
        queue_as :medium

        def perform(thread_id, token)
          thread = Autonomia::Agents::BuildThread.find_by(id: thread_id)
          return if thread.blank? || !active?(thread, token)

          Autonomia::Agents::Builder.new(account: thread.account, build_thread: thread).run!(token)
        rescue Crm::Ai::ResponsesClient::Error => e
          fail_build(thread, token, e.message)
        rescue ActiveRecord::ActiveRecordError => e
          # Validação/persistência falhou ao aplicar a config (ex.: RecordInvalid por campo longo): falha
          # a thread em vez de deixar o erro borbulhar p/ o Sidekiq (que reexecutaria e travaria em
          # `processing`). FALHA NUNCA SILENCIOSA: registramos QUAIS campos reprovaram, para o state da
          # thread dizer ao dono que NADA foi aplicado e por quê — antes disso ele perdia o ajuste sem
          # nenhum sinal e passava dias achando que tinha configurado o agente.
          fields = invalid_fields(e)
          Rails.logger.error(
            "[Autonomia::Agents::Builder::SubmitJob] apply_failed thread=#{thread_id} #{e.class}: " \
            "#{e.message} fields=#{fields.join(',')}"
          )
          fail_build(thread, token, 'apply_failed', fields: fields)
        rescue StandardError => e
          Rails.logger.error("[Autonomia::Agents::Builder::SubmitJob] thread=#{thread_id} #{e.class}: #{e.message}")
          fail_build(thread, token, 'build_error')
        end

        private

        def active?(thread, token)
          thread.processing? && thread.build_token == token
        end

        # Quais atributos reprovaram na validação. Só nomes de coluna (`tone`, `instruction`), nunca o
        # conteúdo. Erros de persistência sem `record` (deadlock, conexão) devolvem lista vazia.
        def invalid_fields(error)
          return [] unless error.is_a?(ActiveRecord::RecordInvalid)

          Array(error.record&.errors&.attribute_names).map(&:to_s).uniq
        end

        # Só marca falha se ESTA geração ainda era a ativa (ganhou o update guardado pelo token).
        def fail_build(thread, token, message, fields: [])
          return if thread.blank?

          thread.mark_failed!(token, message, fields: fields)
        end
      end
    end
  end
end
