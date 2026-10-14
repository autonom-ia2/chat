module Autonomia
  module Agents
    module Operate
      # ENTREGA HUMANIZADA — INDICADOR "DIGITANDO" por canal. Mostra/limpa o "digitando" do agente
      # durante as pausas entre os pedaços da resposta. Adaptador com DEGRADAÇÃO GRACIOSA: cada canal
      # usa o mecanismo que tem; canal sem suporte simplesmente não mostra typing (a entrega chunk+delay
      # continua). NUNCA levanta no caminho vivo (best-effort, rescue largo) — typing é cosmético.
      #
      #   - Web widget / API (chat ao vivo): NATIVO. Dispara CONVERSATION_TYPING_ON/OFF pelo dispatcher
      #     (mesmo caminho do TypingStatusManager); o widget do contato mostra a bolha "digitando".
      #   - WhatsApp Cloud oficial: chama a API da Meta (status:read + typing_indicator) referenciando o
      #     wamid da última mensagem do cliente — idêntico ao nó "WA API Oficial" do fluxo n8n. WhatsApp
      #     não tem "typing off": o indicador some sozinho (~25s) ou quando a mensagem chega → off vira no-op.
      #   - Instagram: sender_action typing_on/off (Graph). Best-effort; se a conta/permite não suportar,
      #     degrada silenciosamente.
      #   - Demais canais: no-op.
      class TypingIndicator
        include Events::Types

        def initialize(conversation:, agent_inbox:)
          @conversation = conversation
          @agent_inbox  = agent_inbox
          @channel = conversation.inbox&.channel
        end

        def on
          dispatch(true)
        end

        def off
          dispatch(false)
        end

        private

        def dispatch(typing_on)
          case @channel
          when Channel::WebWidget, Channel::Api
            web_widget_typing(typing_on)
          when Channel::Whatsapp, Channel::Instagram
            channel_typing(typing_on)
          end
        rescue StandardError => e
          # Typing é cosmético: qualquer falha (rede/credencial/versão de API) NÃO pode quebrar a entrega.
          Rails.logger.warn("[autonomia][operate][typing] degraded conv=#{@conversation.id} #{e.class}")
          nil
        end

        # Web widget: emite o evento nativo do Chatwoot. O "user" é o AgentBot-espelho (tem
        # push_event_data); o ActionCableListener faz broadcast ao contato (token do contact_inbox).
        def web_widget_typing(typing_on)
          event = typing_on ? CONVERSATION_TYPING_ON : CONVERSATION_TYPING_OFF
          Rails.configuration.dispatcher.dispatch(
            event, Time.zone.now,
            conversation: @conversation, user: @agent_inbox.agent_bot, is_private: false
          )
        end

        # WhatsApp Cloud e Instagram: o envio por canal (e o gate AI_HUMANIZE_CHANNEL_TYPING) mora em
        # Conversations::ChannelTyping::Deliverer, o mesmo objeto que atende o robô externo (chat#1442).
        def channel_typing(typing_on)
          ::Conversations::ChannelTyping::Deliverer.new(conversation: @conversation, typing_status: typing_on ? 'on' : 'off').perform
        end
      end
    end
  end
end
