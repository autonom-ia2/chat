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

        # #1367 — aviso à tela de quem abriu a conversa: "a thread mudou, busque de novo". Só ids, nunca
        # conteúdo; a tela continua lendo pelo `show`, que aplica o filtro de IP oculto.
        BUILD_THREAD_UPDATED = 'autonomia.build_thread.updated'.freeze

        def perform(thread_id, token)
          log_queue_wait(thread_id)
          thread = Autonomia::Agents::BuildThread.find_by(id: thread_id)
          return if thread.blank? || !active?(thread, token)

          build(thread, token)
          fotos_para_base(thread)
          notify_creator(thread)
        end

        private

        # #1426 — a foto da criação entra na base depois do turno (o rascunho já existe). Um erro aqui não derruba o
        # turno, que já foi gerado: vai ao log e ao Sentry com a thread, e a foto segue na conversa com o Construtor.
        def fotos_para_base(thread)
          Autonomia::Agents::Knowledge::FotosDaCriacao.new(thread.reload).para_base!
        rescue StandardError => e
          Rails.logger.error("[Autonomia::Agents::Builder::SubmitJob] fotos_da_criacao_failed thread=#{thread.id} #{e.class}")
          ChatwootExceptionTracker.new(e, account: thread.account).capture_exception
        end

        def build(thread, token)
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
            "[Autonomia::Agents::Builder::SubmitJob] apply_failed thread=#{thread.id} #{e.class}: " \
            "#{e.message} fields=#{fields.join(',')}"
          )
          fail_build(thread, token, 'apply_failed', fields: fields)
        rescue StandardError => e
          Rails.logger.error("[Autonomia::Agents::Builder::SubmitJob] thread=#{thread.id} #{e.class}: #{e.message}")
          fail_build(thread, token, 'build_error')
        end

        # #1367 — quanto o turno esperou na fila antes de começar (enqueued_at → perform). Vazio quando o
        # job rodou sem passar pela fila (perform_now).
        def log_queue_wait(thread_id)
          wait_ms = enqueued_at && ((Time.current - enqueued_at) * 1000).round
          Rails.logger.info("[Autonomia::Agents::Builder::SubmitJob] start thread=#{thread_id} queue_wait_ms=#{wait_ms}")
        end

        # #1367 (alavanca 4) — a tela de quem criou a thread fica sabendo na hora que o turno terminou,
        # pronto ou com falha. Publicação direta no canal da pessoa, sem passar pela fila `critical` do
        # atendimento. Melhor esforço: a consulta periódica da tela continua de reserva, então um aviso
        # perdido só atrasa a tela, nunca derruba o turno.
        def notify_creator(thread)
          token = thread.created_by&.pubsub_token
          return if token.blank?

          ActionCable.server.broadcast(token, { event: BUILD_THREAD_UPDATED,
                                                data: { account_id: thread.account_id, id: thread.id } })
        rescue StandardError => e
          Rails.logger.warn("[Autonomia::Agents::Builder::SubmitJob] notify_failed thread=#{thread.id} #{e.class}")
        end

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
