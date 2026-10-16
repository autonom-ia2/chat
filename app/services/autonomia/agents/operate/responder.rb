module Autonomia
  module Agents
    module Operate
      # Fase C "Operar" — RESPONDER (modelo INSTRUÇÃO-DIRIGIDO). Chamado pelo ReplyJob (após o debounce)
      # com a conversa elegível (SEM responsável + AgentInbox de agente ATIVO; status é irrelevante).
      # Monta o histórico das N últimas mensagens públicas, chama o Answerer em modo trust_instruction e:
      #   - se a resposta for o SINAL DE SILÊNCIO (`conversation_closed_for_now`) -> NÃO posta nada (fica
      #     em silêncio); é a instrução dizendo "não responda agora" (anti-loop / robôs / despedidas);
      #   - se a resposta vier vazia (falha de IA) -> SILÊNCIO (sem fallback de sistema);
      #   - caso contrário -> posta a resposta OUTGOING pelo caminho canônico (Messages::MessageBuilder
      #     com sender AgentBot espelho), igual ao Crm::FollowUps::MessageSender.
      #
      # SEM HANDOFF DE SISTEMA NA RESPOSTA: "passar para humano" é TEXTO da instrução e a resposta
      # postada não muda. O que o sinal `should_handoff` da instrução faz (#284) é fechar o ciclo do
      # ai_assignee: `conversation.bot_handoff!` (solta o espelho, abre a conversa) + evento handed_off.
      #
      # ANTI-LOOP: a mensagem postada é OUTGOING (sender AgentBot), logo NUNCA é incoming e o
      # MessageListener a ignora. SEGURANÇA/IP: só o texto destinado ao cliente é postado; nunca
      # instruction/scaffold/prompt vai à mensagem/log/content_attributes — só o id do agente.
      class Responder
        # Sinal de silêncio padrão (a instrução emite isto em vez de uma resposta). Override por agente
        # via config['silence_tokens'] (lista). Match exato após normalizar (trim + minúsculas + markdown).
        SILENCE_TOKEN = 'conversation_closed_for_now'.freeze
        # Os silêncios que são falha (motivo_do_silencio): soltam a posse do turno, que pode ser retomado (#1606).
        SILENCIOS_DE_FALHA = %w[ia_falhou vazio].freeze

        Result = Struct.new(:status, :message, :error, keyword_init: true) do
          def self.replied(message)
            new(status: :replied, message: message)
          end

          # Não postou (sinal de silêncio, IA indisponível, ou não-elegível na hora de postar).
          def self.silenced
            new(status: :silenced)
          end

          # Porta de engajamento bloqueou (#284): não postou e passou direto para humanos.
          # `error` carrega o motivo (audience | schedule).
          def self.skipped(reason)
            new(status: :skipped, error: reason)
          end
        end

        # `posse` (#1606): o valor com que o settle ficou com o turno (PosseDoTurno.valor). Vai ao ReenfileirarTurno e à
        # entrega em pedaços, para soltar só a posse que ainda é deste turno.
        def initialize(conversation:, agent_inbox:, reply_to_message_id: nil, posse: nil)
          @conversation = conversation
          @agent_inbox  = agent_inbox
          @agent        = agent_inbox.agent
          @reply_to_message_id = reply_to_message_id
          @posse = posse
        end

        # -> Result
        def perform
          # C4 (custo): recheck BARATO de elegibilidade ANTES da chamada cara de IA (LLM + embedding).
          # Entre o debounce e este ponto um humano pode ter assumido a conversa (ou o agente foi
          # desligado/movido de caixa) — sem esta guarda o custo da geração já teria sido pago à toa.
          # O recheck autoritativo pós-IA (dentro do lock, em classic_deliver/deliver_*) PERMANECE.
          return silencio_por_inelegibilidade unless still_eligible?

          # PORTA DE ENGAJAMENTO (#284 · Entrega 2a): público-alvo + horário de atuação, avaliada ANTES
          # da chamada cara de IA. Config vazia -> nil -> segue exatamente como antes.
          blocked = ::Autonomia::Agents::Operate::EngagementGate.new(agent: @agent, conversation: @conversation).blocked_reason
          return skip_for_humans(blocked) if blocked
          # #1669: uma pessoa da equipe já respondeu esta mensagem do cliente -> nem chama a IA (não gasta).
          return silencio_por_pessoa if pessoa_respondeu?

          # A chamada à IA (lenta) roda FORA do lock para não segurar a linha da conversa.
          result = sem_marca_da_equipe(answer)
          # SINAL DE SILÊNCIO da instrução -> não posta nada (IF-node "parar"). Anti-loop / automações.
          # O turno ficou mudo, mas a ferramenta assíncrona JÁ FOI ACEITA dentro dele: despacha assim
          # mesmo, com `replied: false`, para que o próprio job avise o cliente de que a consulta
          # começou. Descartar aqui deixaria o cliente sem cotação e sem explicação.
          # Sem texto utilizável (falha de IA / resposta vazia) -> SILÊNCIO, sem fallback de sistema.
          motivo = motivo_do_silencio(result)
          return silence_with_async(result, motivo) if motivo.present?

          outcome = deliver(result)
          depois_da_entrega(result, outcome)
          outcome
        rescue ::Autonomia::Insurance::QuoteAgent::Builder::EscolhasIncompletas => e
          # ESCOLHAS INCOMPLETAS (#380): o Agente de Cotação não montou o prompt — a chave
          # `agente_de_cotacao` do config está presente e incompleta (só escrita fora do Builder produz
          # isso). A recusa é a certa (uma variável nunca chega ao modelo), mas cair só no resgate largo
          # deixava o corretor vendo silêncio em TODA conversa sem a causa em lugar nenhum além do log.
          # Registra o evento, uma vez por conversa, e segue pelo MESMO caminho de falha de sempre.
          registrar_escolhas_incompletas(e)
          falha_no_turno(e)
        rescue StandardError => e
          falha_no_turno(e)
        end

        # A resposta do agente é o sinal de silêncio? (compara o texto inteiro, normalizado, com o(s)
        # token(s) de silêncio). A instrução é quem decide emitir o sinal; aqui o sistema só HONRA.
        def silence_signal?(result)
          reply = result&.reply.to_s
          return false if reply.blank?

          silence_tokens.include?(normalize_token(reply))
        end

        def silence_tokens
          custom = Array(@agent.config&.dig('silence_tokens')).map { |token| normalize_token(token) }.reject(&:blank?)
          custom.presence || [normalize_token(SILENCE_TOKEN)]
        end

        # Normaliza p/ comparação: minúsculas + tira espaços e aspas/crase/asterisco SÓ das pontas
        # (markdown que o modelo às vezes adiciona). NUNCA mexe nos underscores internos do token.
        def normalize_token(value)
          value.to_s.strip.downcase.gsub(/\A["'`*\s]+|["'`*\s]+\z/, '')
        end

        private

        # Falha inesperada no turno -> SILÊNCIO (sem texto de sistema). Loga a classe p/ diagnóstico, nunca
        # a mensagem. A execução assíncrona aceita nunca chega a falar com o portal: melhor não cotar do
        # que cotar e não ter como entregar.
        def falha_no_turno(error)
          Rails.logger.warn("[autonomia][operate] responder_failed agent=#{@agent.id} conv=#{@conversation.id} #{error.class}")
          soltar_posse
          ::Autonomia::Agents::Tools::AsyncDispatcher.new(delivery: @delivery, agent: @agent).discard!
          Result.silenced
        end

        # Uma vez por conversa: a segunda mensagem do mesmo cliente não duplica o evento. A mensagem do
        # erro é só o NOME do campo que falta (`Builder.conferir_escolhas!`), nunca o valor de outra escolha — por
        # isso pode ir ao log. O EventLogger nunca levanta.
        def registrar_escolhas_incompletas(error)
          Rails.logger.warn("[autonomia][operate] escolhas_incompletas agent=#{@agent.id} conv=#{@conversation.id} campo=#{error.message}")
          return if @agent.events.skipped_escolhas_incompletas.exists?(conversation_id: @conversation.id)

          ::Autonomia::Agents::Operate::EventLogger.skipped(agent: @agent, conversation: @conversation,
                                                            reason: 'escolhas_incompletas')
        end

        # A instrução sinalizou "passar para humano" (should_handoff) -> fecha o ciclo do ai_assignee:
        # bot_handoff! (solta o AgentBot-espelho, abre a conversa, dispara CONVERSATION_BOT_HANDOFF) +
        # evento handed_off. Só enquanto o espelho ainda está no comando (ai_assignee = espelho ou
        # pending) — depois disso a conversa já foi entregue e o sinal repetido é ignorado (1 evento
        # por episódio). A guarda é rechecada DENTRO do lock (with_lock recarrega sob FOR UPDATE):
        # duas respostas concorrentes não duplicam o handoff nem o evento — a segunda encontra a
        # conversa já liberada. Sem return/break dentro do with_lock (dispararia ROLLBACK).
        # Best-effort: nunca derruba a resposta já postada.
        def handoff_if_signaled(result)
          return unless result&.handoff&.dig(:should)

          released = false
          @conversation.with_lock do
            if bot_still_in_command?
              @conversation.bot_handoff!
              released = true
            end
          end
          return unless released

          ::Autonomia::Agents::Operate::EventLogger.handed_off(agent: @agent, conversation: @conversation, result: result)
          ::Autonomia::Agents::NotaDoEncaminhamento.postar(@conversation)
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] handoff_signal_failed agent=#{@agent.id} conv=#{@conversation.id} #{e.class}")
          nil
        end

        # A porta bloqueou (fora do público-alvo / fora do horário): o agente NÃO responde e passa a
        # conversa DIRETO para humanos — mesmo caminho do handoff sinalizado (bot_handoff! sob lock, guarda
        # rechecada com estado fresco para que duas respostas concorrentes não dupliquem) + evento
        # skipped_<motivo>, uma vez por episódio. Depois de liberada, o sinal repetido é silêncio.
        def skip_for_humans(reason)
          released = false
          @conversation.with_lock do
            if bot_still_in_command?
              @conversation.bot_handoff!
              released = true
            end
          end
          ::Autonomia::Agents::Operate::EventLogger.skipped(agent: @agent, conversation: @conversation, reason: reason) if released
          Result.skipped(reason)
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] engagement_skip_failed agent=#{@agent.id} conv=#{@conversation.id} #{e.class}")
          Result.skipped(reason)
        end

        # Espelho DESTE vínculo ainda é o ai_assignee (ou a conversa ainda está pending). Chamar só com
        # estado fresco (dentro do with_lock).
        def bot_still_in_command?
          ::Autonomia::Agents::Operate.espelho_no_comando?(@conversation, @agent_inbox)
        end

        # Escolhe o caminho de entrega (extraído do perform p/ legibilidade; mesma ordem de sempre):
        #   1) ESPELHAMENTO DE ÁUDIO (Onda 2c, gated): cliente mandou áudio neste turno + recurso
        #      ligado -> responde EM ÁUDIO (TTS). Falha de síntese -> cai no texto (nunca fica mudo).
        #   2) ENTREGA HUMANIZADA (aditiva, kill-switch): quebra em pedaços com "digitando" + pausa.
        #   3) OFF (ENV/por-agente) -> caminho CLÁSSICO de 1 mensagem (ZERO mudança de comportamento).
        def deliver(result)
          return deliver_voice(result) if voice_reply_applies?
          return deliver_humanized(result) if ::Autonomia::Agents::Config.humanize_delivery_enabled?(@agent)

          classic_deliver(result)
        end

        # Caminho CLÁSSICO: 1 mensagem única (comportamento original, intocado). Usado quando a
        # humanização está OFF e como FALLBACK quando o quebrador não produz pedaço (resposta só com
        # caracteres invisíveis) — preserva paridade exata com o modo OFF.
        #
        # Lock por conversa só na hora de postar: reavalia elegibilidade com estado fresco (um humano
        # pode ter assumido durante a chamada à IA) e garante idempotência (retry do Sidekiq após post
        # não duplica). IMPORTANTE (Rails 7.1): NÃO usar return/break dentro do with_lock — dispararia
        # ROLLBACK e descartaria a mensagem recém-postada. Computa-se o Result numa variável.
        def classic_deliver(result)
          outcome = @conversation.with_lock do
            parada_na_hora_de_postar || Result.replied(post_reply!(result.reply))
          end

          # Fase F (ADITIVO/best-effort): só registra quando uma resposta NOVA foi postada
          # (outcome.message presente — exclui already_replied?, que devolve message nil, e
          # o caso still_eligible?==false, que virou handoff). EventLogger nunca levanta.
          if outcome.status == :replied && outcome.message.present?
            ::Autonomia::Agents::Operate::EventLogger.replied(
              agent: @agent, conversation: @conversation, result: result, message: outcome.message
            )
          end
          outcome
        end

        # As guardas da hora de postar, na ordem de sempre, chamadas DENTRO do lock (estado fresco). -> o Result de quem
        # não posta (silêncio, ou `replied(nil)` quando um settle anterior já respondeu) ou nil para postar. É um método,
        # não um bloco: o `return` aqui não sai do with_lock.
        def parada_na_hora_de_postar
          return silencio_por_inelegibilidade unless still_eligible?
          return silencio_por_turno_superado if turno_superado?
          return Result.replied(nil) if already_replied? # um settle anterior já entregou (retry): não é silêncio

          silencio_por_pessoa if pessoa_respondeu?
        end

        # ESPELHAMENTO DE ÁUDIO: só quando o cliente mandou áudio NESTE turno (media.transcripts) e o
        # recurso está ligado (ENV/por-agente). Caso contrário, fluxo de texto normal.
        def voice_reply_applies?
          media.transcripts.any? && ::Autonomia::Agents::Config.voice_reply_enabled?(@agent)
        end

        # Sintetiza a resposta em áudio (TTS) e posta como mensagem outgoing SÓ-ÁUDIO. A síntese (lenta)
        # roda FORA do lock; o lock só posta. Falha/áudio vazio -> cai no texto (post_reply!), nunca mudo.
        def deliver_voice(result)
          audio = synthesize_audio(result.reply) # fora do lock; nil em falha
          outcome = @conversation.with_lock do
            # Sem áudio (falha na síntese) -> fallback texto.
            parada_na_hora_de_postar || Result.replied(audio.present? ? post_audio_reply!(audio) : post_reply!(result.reply))
          end
          if outcome.status == :replied && outcome.message.present?
            ::Autonomia::Agents::Operate::EventLogger.replied(agent: @agent, conversation: @conversation, result: result,
                                                              message: outcome.message)
          end
          outcome
        end

        # -> bytes (opus) ou nil. NUNCA loga o texto. Fail-safe (qualquer erro -> nil -> fallback texto).
        def synthesize_audio(text)
          credential = Crm::Ai::CredentialResolver.new(account: @agent.account).resolve
          return if credential.blank?

          Crm::Ai::SpeechClient.new(credential: credential)
                               .synthesize(text,
                                           voice: ::Autonomia::Agents::Config.voice_for(@agent),
                                           instructions: ::Autonomia::Agents::Config.voice_instructions_for(@agent))
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] tts_failed agent=#{@agent.id} #{e.class}")
          nil
        end

        # Mensagem outgoing SÓ-ÁUDIO (espelhamento): mesmo sender/anti-loop do post_reply!, com o anexo de
        # áudio construído ANTES do save (o envio por canal dispara nos callbacks da Message outgoing).
        def post_audio_reply!(audio_bytes)
          message = @conversation.messages.new(
            content: '',
            account_id: @agent_inbox.account_id,
            inbox_id: @conversation.inbox_id,
            message_type: :outgoing,
            sender_type: 'AgentBot',
            sender_id: @agent_inbox.agent_bot_id,
            content_attributes: {
              autonomia_agent_id: @agent.id,
              autonomia_reply_to_message_id: @reply_to_message_id,
              autonomia_voice: true
            }
          )
          # meta['is_voice_message']=true -> os provedores (WhatsApp Cloud etc.) enviam como ÁUDIO DE VOZ
          # (voice note), não como arquivo de áudio comum — mesmo contrato do caminho canônico do core.
          message.attachments.new(account_id: @agent_inbox.account_id, file_type: :audio,
                                  meta: { 'is_voice_message' => true }).tap do |att|
            att.file.attach(io: StringIO.new(audio_bytes), filename: 'resposta.ogg', content_type: 'audio/ogg')
          end
          message.save!
          message
        end

        # Inicia a entrega humanizada: quebra a resposta, mostra "digitando" e agenda o 1º pedaço.
        # Guardas baratas aqui (idempotência/elegibilidade); as AUTORITATIVAS (lock + token + por-chunk)
        # vivem no ChunkedDeliveryJob. NÃO posta nada de forma síncrona.
        def deliver_humanized(result)
          parada = parada_antes_dos_pedacos
          return parada if parada

          chunks = ::Autonomia::Agents::Operate::ReplyChunker.call(result.reply)
          # Quantos pedaços a cadeia vai postar. A entrega ASSÍNCRONA espera esse número aparecer
          # antes de publicar, para não se intercalar no meio da frase que o agente ainda está
          # "digitando" (a cadeia pode durar até 90s).
          @expected_chunks = chunks.length
          # Nada a quebrar (ex.: resposta só com invisíveis) -> caminho clássico (paridade com OFF),
          # nunca engole a resposta silenciosamente.
          return classic_deliver(result) if chunks.empty?

          # `used_entry_ids` viaja no meta (só ids) para o job registrar as fontes no evento replied.
          meta = {
            'confidence' => result.confidence, 'answered_from_knowledge' => result.answered_from_knowledge,
            'used_entry_ids' => ::Autonomia::Agents::Operate::EventLogger.used_entry_ids(result),
            'posse' => @posse
          }
          ::Autonomia::Agents::Operate::TypingIndicator.new(conversation: @conversation, agent_inbox: @agent_inbox).on
          ::Autonomia::Agents::Operate::ChunkedDeliveryJob
            .set(wait: (chunks.first['delay_ms'].to_i / 1000.0).clamp(0.1, 30.0).seconds)
            .perform_later(@conversation.id, @agent_inbox.id, @reply_to_message_id, chunks, 0, meta)
          Result.replied(nil)
        end

        # As guardas baratas da entrega em pedaços, na ordem de sempre. -> o Result de quem não agenda, ou nil.
        def parada_antes_dos_pedacos
          return Result.replied(nil) if already_replied? # um settle anterior já entregou
          return silencio_por_inelegibilidade unless still_eligible? # humano assumiu durante a IA -> não posta

          silencio_por_pessoa if pessoa_respondeu? # a pessoa respondeu durante a IA; o job reconfere a cada pedaço
        end

        # Motor de resposta em modo INSTRUÇÃO-DIRIGIDO: devolve a resposta do modelo como veio (sem
        # portão de confiança nem handoff de sistema). reply pode vir nil (falha de IA) -> silêncio.
        # MULTIMODAL (Onda 2 / Track B): passa as imagens/figurinhas do turno como input_image; a
        # transcrição de áudio já vem embutida em `query`.
        def answer
          ::Autonomia::Agents::Answerer.new(
            agent: @agent,
            query: query,
            history: history,
            images: media.images,
            documents: media.documents,
            trust_instruction: true,
            delivery: delivery,
            **rodadas_do_turno
          ).answer
        end

        # As rodadas do turno: as do principal com ajudante (tema 14, #1434) ou, sem ajudante, as de sempre — seis para a
        # Lia (`QuoteAgent::Builder`), uma para os demais. A Lia nunca tem ajudante, então segue igual.
        def rodadas_do_turno
          ::Autonomia::Agents::Ajudantes.rodadas(@agent) || ::Autonomia::Insurance::QuoteAgent::Builder.rodadas_do_turno(@agent)
        end

        # QUAL DOS SILÊNCIOS, e por que isto existe. Os três caminhos terminavam no mesmo `silenced`,
        # sem nada que os separasse: perguntado em 21/09/2026 quantas vezes a instrução mandou calar
        # de propósito, não havia como responder — só dava para inferir por mensagem de cliente sem
        # resposta, que mistura os três. Rótulo nosso, de lista fechada, nunca texto do cliente.
        #
        #   `sinal`        — a instrução decidiu calar (a pessoa só reconheceu, ou veio robô).
        #   `ia_falhou`    — a IA não devolveu resultado.
        #   `vazio`        — devolveu, mas sem texto utilizável.
        #   `nao_elegivel` — o turno tinha o que dizer e não disse: um humano assumiu (ou o agente
        #                    saiu do ar) durante a chamada de IA, e o texto foi descartado.
        #   Na hora de postar (#1606): `dono_mudou` (outro agente da caixa virou o dono) e `turno_superado` (o cliente
        #   escreveu de novo durante a IA; responde o settle da mensagem nova).
        #   `pessoa_respondeu` (#1669): uma pessoa da equipe respondeu esta mensagem do cliente, antes ou durante a IA.
        def motivo_do_silencio(result)
          return 'sinal' if silence_signal?(result)
          return 'ia_falhou' if result.nil?
          return 'vazio' if result.reply.to_s.strip.blank?

          nil
        end

        # Silêncio, mas SEM abandonar o que a ferramenta assíncrona já aceitou dentro do turno: o
        # cliente pediu a consulta e vai receber o aviso e o resultado pelo job.
        def silence_with_async(_result, motivo)
          registrar_silencio(motivo)
          if SILENCIOS_DE_FALHA.include?(motivo)
            soltar_posse
            refazer_pelo_dono_novo
          end
          dispatch_async(replied: false)
          Result.silenced
        end

        # #1606: a IA falhou e, durante a chamada, outro vínculo ativo da caixa virou o dono por um caminho sem o evento
        # de troca (o robô atribuído pela tela). Sem isto o turno ficaria sem dono: a posse foi solta, mas ninguém chama o
        # dono novo. Com o evento, o assinante já enfileirou, e o SET NX do ReenfileirarTurno barra este segundo pedido.
        def refazer_pelo_dono_novo
          return if still_eligible? || !dono_mudou?

          ::Autonomia::Agents::Operate::ReenfileirarTurno.call(conversation: @conversation, message_id: @reply_to_message_id,
                                                               origem: :responder, quem_perdeu: @agent_inbox,
                                                               posse_de_quem_perdeu: @posse)
        end

        # #1606: uma mensagem mais nova do cliente abriu outro turno durante a IA (a marca do debounce aponta para ela).
        # A resposta deste turno ficou velha: é descartada, e o settle do turno novo responde, uma vez. Mesmo critério do
        # ChunkedDeliveryJob#current_turn? (sem marca, segue). Chamar só com estado fresco (depois de still_eligible?, que
        # relê a conversa, dentro do lock). Só com a Fase 2; fora dela posta como sempre.
        def turno_superado?
          return false if @reply_to_message_id.blank? || !::Autonomia::Agents::Fase2.ligada?(@conversation.account)

          stamp = @conversation.additional_attributes.to_h[::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY]
          pendente = stamp.is_a?(Hash) ? stamp['pending_message_id'] : nil
          pendente.present? && pendente != @reply_to_message_id.to_i
        end

        def silencio_por_turno_superado
          registrar_silencio('turno_superado')
          Result.silenced
        end

        # #1669: uma pessoa da equipe respondeu publicamente depois da mensagem do cliente deste turno. Só com a Fase 2
        # (PessoaDaEquipe). A posse do turno fica: este turno foi respondido, pela pessoa. A IA segue na conversa.
        def pessoa_respondeu?
          ::Autonomia::Agents::Operate::PessoaDaEquipe.respondeu_depois?(@conversation, @reply_to_message_id)
        end

        def silencio_por_pessoa
          @calou_pela_pessoa = true
          registrar_silencio('pessoa_respondeu')
          Result.silenced
        end

        # Depois da entrega: despacha a consulta assíncrona aceita no turno e honra o handoff pedido pela instrução.
        # #1669: se a resposta foi descartada porque uma pessoa da equipe respondeu (`pessoa_respondeu`), a pessoa já
        # está atendendo. A consulta que já começou segue (como no `turno_superado`), mas SEM o aviso de começo ao
        # cliente (`replied: true` = não avisa): o aviso seria a IA falando por cima da pessoa. E o handoff pedido pela IA
        # não roda: passar a conversa para "humanos" com a pessoa já nela abriria a fila de espera à toa.
        def depois_da_entrega(result, outcome)
          dispatch_async(replied: outcome.status == :replied || @calou_pela_pessoa.present?)
          handoff_if_signaled(result) unless @calou_pela_pessoa
        end

        # #1669: se o modelo imitou a moldura da mensagem da equipe, ela sai da resposta antes de qualquer entrega. Só
        # com a Fase 2 (fora dela a moldura nem entra no histórico). Resposta que fica vazia cai no silêncio `vazio`.
        def sem_marca_da_equipe(result)
          return result if result.nil? || !::Autonomia::Agents::Operate::PessoaDaEquipe.aplica?(@conversation)

          limpa = ::Autonomia::Agents::Operate::PessoaDaEquipe.sem_marca(result.reply)
          return result if limpa == result.reply

          ::Autonomia::Agents::AnswerResult.new(reply: limpa, confidence: result.confidence, handoff: result.handoff,
                                                used_knowledge: result.used_knowledge,
                                                answered_from_knowledge: result.answered_from_knowledge,
                                                raw_reply: result.raw_reply, error: result.error)
        end

        # #1606: o turno que FALHOU (IA sem resultado, resposta vazia, exceção) pode ser retomado — pela troca de dono ou
        # pela volta ao mesmo dono. Solta a posse deste settle (compare-and-delete com o valor dele). O silêncio por `sinal`
        # é decisão da instrução e o turno respondido seguem com a chave: é o que impede responder duas vezes.
        def soltar_posse
          return unless ::Autonomia::Agents::Fase2.ligada?(@conversation.account)

          ::Autonomia::Agents::Operate::PosseDoTurno.soltar(@conversation.id, @reply_to_message_id, @agent_inbox.id, @posse)
        end

        # O turno mudo porque deixou de ser nosso: humano assumiu, agente desligado, conversa movida.
        # Não despacha assíncrono nem posta — só deixa o rastro, para que este motivo não se confunda
        # com os outros três na contagem. Quando quem assumiu foi OUTRO agente da caixa (`dono_mudou`, #1606), o turno
        # não morre: é refeito pelo dono novo (ReenfileirarTurno, com SET NX contra dois reenfileiramentos).
        def silencio_por_inelegibilidade
          return silencio_por_dono_novo if dono_mudou?

          registrar_silencio('nao_elegivel')
          Result.silenced
        end

        def silencio_por_dono_novo
          registrar_silencio('dono_mudou')
          ::Autonomia::Agents::Operate::ReenfileirarTurno.call(conversation: @conversation, message_id: @reply_to_message_id,
                                                               origem: :responder, quem_perdeu: @agent_inbox,
                                                               posse_de_quem_perdeu: @posse)
          Result.silenced
        end

        # O único lugar que escreve a linha. Campos: dois ids nossos e um rótulo de lista fechada —
        # nada do que o cliente escreveu, nada do que o modelo respondeu.
        def registrar_silencio(motivo)
          Rails.logger.info("[autonomia][operate] silencio agent=#{@agent.id} conv=#{@conversation.id} motivo=#{motivo}")
        end

        # CONTEXTO DE ENTREGA (#313). Só existe no atendimento — é o que autoriza uma ferramenta
        # ASSÍNCRONA a ser aceita, e é o coletor das execuções aceitas neste turno.
        def delivery
          @delivery ||= ::Autonomia::Agents::Tools::Delivery.new(conversation: @conversation,
                                                                 agent_inbox: @agent_inbox,
                                                                 origin_message_id: @reply_to_message_id)
        end

        # Promove as execuções aceitas no turno e as enfileira. `replied` diz se o turno vai entregar
        # texto ao cliente: quando não vai, o job dispara o evento de começo (`Tools::Evento`), e a Lia avisa.
        def dispatch_async(replied:)
          return unless @delivery&.any_runs?

          ::Autonomia::Agents::Tools::AsyncDispatcher
            .new(delivery: @delivery, agent: @agent)
            .dispatch!(replied: replied, expected_chunks: @expected_chunks.to_i)
        end

        # Mídia do turno atual (imagens/figurinhas inline + transcrições de áudio), gateada por flag
        # global/por-agente. OFF -> vazio (responde só ao texto, ZERO regressão). Memoizada: uma vez por
        # perform (roda FORA do lock, junto da chamada lenta de IA).
        def media
          @media ||= if ::Autonomia::Agents::Config.operate_media_enabled?(@agent)
                       MessageMedia.new(messages: current_turn_incoming, agent: @agent).extract
                     else
                       MessageMedia::EMPTY
                     end
        end

        # Reavaliação FRESCA do CONTRATO INTEIRO (Operate.eligible_agent_inbox) dentro do lock, ainda
        # na MESMA caixa do agente: sem responsável + agente ligado/ativo/não-interno/não-sistema +
        # feature on + allowlist. Cobre o que mudou durante a chamada de IA (humano assumiu, agente
        # desligado, conversa movida de caixa) — em qualquer um desses casos NÃO posta.
        # Guarda quem a releitura achou (@quem_responde_agora), para o silêncio dizer se foi pessoa ou outro dono.
        def still_eligible?
          @quem_responde_agora = ::Autonomia::Agents::Operate.eligible_agent_inbox(@conversation.reload)
          @quem_responde_agora.present? && @quem_responde_agora.id == @agent_inbox.id
        end

        # #1606: outro vínculo ativo da caixa virou o dono da conversa (Sync do CRM, passagem). Só com a Fase 2; fora
        # dela a escolha é sempre a porta, e um vínculo diferente aqui segue sendo `nao_elegivel`, como antes.
        def dono_mudou?
          @quem_responde_agora.present? && @quem_responde_agora.id != @agent_inbox.id &&
            ::Autonomia::Agents::Fase2.ligada?(@conversation.account)
        end

        # Idempotência: já existe uma resposta outgoing do bot para ESTA mensagem incoming?
        # Bloqueia post duplicado num retry do Sidekiq que ocorra após um post bem-sucedido.
        def already_replied?
          return false if @reply_to_message_id.blank?

          # `content_attributes` é coluna `json` gravada via Rails `store(coder: JSON)`,
          # i.e. STRING JSON dentro de json: `->>` devolve NULL e nunca casa, e no `::text`
          # as aspas internas vêm ESCAPADAS (`\"autonomia_reply_to_message_id\":123`). O id
          # serializa como NÚMERO (Integer do arg do Sidekiq) — `...:123` sem aspas — mas o
          # regex tolera também a forma string (`"?...?"`). Fronteira `[,}]` evita casar 12 em
          # 123. Sem isto a guarda anti-duplicata ficaria sempre falsa (retry -> resposta dupla).
          id = Regexp.escape(@reply_to_message_id.to_s)
          pattern = %(autonomia_reply_to_message_id\\\\?":"?#{id}"?[,}])
          @conversation.messages.outgoing.where(sender_type: 'AgentBot')
                       .where('content_attributes::text ~ ?', pattern)
                       .exists?
        end

        # query = última mensagem INCOMING pública (o que o contato acaba de perguntar), enriquecida com:
        # (1) o CONTEXTO da mensagem referenciada (reply citado / reação que chega como texto com
        # in_reply_to, ex.: WAHA "*Reagiu com* 👍") — dá ao modelo O QUE o cliente respondeu/reagiu;
        # (2) as transcrições de áudio do turno (uma mensagem de áudio costuma vir com content vazio).
        # Imagens NÃO entram aqui — vão como input_image.
        def query
          message = last_incoming_message
          base = message&.content.to_s
          transcribed = media.transcripts.map { |text| "[áudio do cliente, transcrito automaticamente]: #{text}" }
          texto = [quoted_context(message), base.presence, *transcribed].compact.join("\n")
          # #1669: com a Fase 2, a chave da moldura da equipe escrita pelo cliente é neutralizada (não se forja a moldura).
          return texto unless ::Autonomia::Agents::Operate::PessoaDaEquipe.aplica?(@conversation)

          ::Autonomia::Agents::Operate::PessoaDaEquipe.neutralizar(texto)
        end

        def last_incoming_message
          recent_messages.reverse.find(&:incoming?)
        end

        # Contexto da mensagem referenciada via `in_reply_to` (reply citado OU reação entregue como texto
        # pelo canal, ex.: WAHA). Escopado à conversa, truncado, fail-safe. Sem referência -> nil (a query
        # fica idêntica ao comportamento anterior).
        def quoted_context(message)
          ref_id = message&.content_attributes.to_h['in_reply_to']
          return if ref_id.blank?

          # `.chat` exclui notas PRIVADAS e activities (mesmo escopo do history) -> nunca vaza conteúdo
          # de nota interna ao LLM mesmo que in_reply_to aponte para uma (P1 privacidade, codex).
          referenced = @conversation.messages.chat.find_by(id: ref_id)
          quoted = referenced&.content.to_s.strip.tr("\n", ' ').first(160)
          return if quoted.blank?

          side = referenced.outgoing? ? 'sua mensagem' : 'uma mensagem anterior dele'
          "[Em referência a #{side}: \"#{quoted}\"]"
        rescue StandardError
          nil
        end

        # Incoming do TURNO atual = mensagens incoming após a última saída (bot/humano) na janela
        # recente; se não houve saída ainda, todas as incoming da janela. É daí que a mídia é extraída
        # (cobre o caso "cliente manda a imagem e o texto em mensagens separadas" dentro do debounce).
        def current_turn_incoming
          msgs = recent_messages
          last_outgoing_index = msgs.rindex { |message| !message.incoming? }
          window = last_outgoing_index ? msgs[(last_outgoing_index + 1)..] : msgs
          Array(window).select(&:incoming?)
        end

        # history = a janela de `recent_messages`, em ordem cronológica, mapeada para o formato do
        # Answerer: incoming -> user, outgoing -> assistant. Activity/private já são excluídas pelo
        # scope `chat`. Com a Fase 2 (#1669), o que uma pessoa da equipe escreveu vai marcado como dela
        # (PessoaDaEquipe.item_do_historico); robô e sistema seguem como sempre.
        def history
          return history_com_a_equipe if ::Autonomia::Agents::Operate::PessoaDaEquipe.aplica?(@conversation)

          recent_messages.map do |message|
            { role: message.incoming? ? 'user' : 'assistant', content: message.content.to_s }
          end
        end

        def history_com_a_equipe
          ActiveRecord::Associations::Preloader.new(records: recent_messages, associations: :sender).call
          whatsapp = @conversation.inbox.whatsapp?
          recent_messages.map { |message| ::Autonomia::Agents::Operate::PessoaDaEquipe.item_do_historico(message, whatsapp: whatsapp) }
        end

        # Mensagens públicas, não-activity, em ordem cronológica: das últimas `HISTORY_MAX_INTERACOES`
        # mensagens do cliente em diante (chat#625), com tudo o que o agente respondeu no meio, sob o teto
        # `HISTORY_MAX_MESSAGES` (as mais recentes ficam).
        def recent_messages
          @recent_messages ||= janela_do_historico.reorder(created_at: :desc)
                                                  .limit(::Autonomia::Agents::Config::HISTORY_MAX_MESSAGES)
                                                  .to_a
                                                  .reverse
        end

        def janela_do_historico
          chat = @conversation.messages.chat
          desde = chat.incoming.reorder(created_at: :desc)
                      .offset(::Autonomia::Agents::Config::HISTORY_MAX_INTERACOES - 1)
                      .pick(:created_at)
          desde ? chat.where(created_at: desde..) : chat
        end

        # Caminho CANÔNICO channel-agnóstico (= Crm::FollowUps::MessageSender): a entrega
        # por canal (WhatsApp/Instagram/email/webchat) é feita pelos jobs de canal do
        # Chatwoot disparados nos callbacks da Message outgoing. Nada por-canal aqui.
        def post_reply!(text)
          Messages::MessageBuilder.new(
            nil,
            @conversation,
            ActionController::Parameters.new(
              content: text,
              message_type: 'outgoing',
              sender_type: 'AgentBot',
              sender_id: @agent_inbox.agent_bot_id, # AgentBot nativo-espelho
              private: false,
              content_attributes: {
                autonomia_agent_id: @agent.id,
                autonomia_reply_to_message_id: @reply_to_message_id
              }
            )
          ).perform
        end
      end
    end
  end
end
