module Crm
  module Ai
    class Config
      BOOLEAN = ActiveModel::Type::Boolean.new

      AUTO_MOVE_THRESHOLD = 0.75
      SUGGESTION_THRESHOLD = 0.55
      # IA entende a conversa F3 (decisão do Rodrigo, 30/10, #2389): fechar o card (Crm::Ai::FecharCard) é sempre sugestão,
      # a partir de SUGGESTION_THRESHOLD; a IA nunca fecha sozinha. Na semana, os fechamentos errados vieram com 0,95–0,99,
      # na mesma faixa dos certos: nenhum limiar de confiança separa um do outro. Mover de etapa segue AUTO_MOVE_THRESHOLD.
      DEBOUNCE_SECONDS = 15
      MIN_EVALUATION_INTERVAL_SECONDS = 30
      AUTO_MOVE_COOLDOWN_SECONDS = DEBOUNCE_SECONDS
      DEFAULT_STALE_HOURS = 168

      MODEL_SUMMARY = 'gpt-6-luna'.freeze
      MODEL_CLASSIFY = 'gpt-6-luna'.freeze
      # auto-move usa o modelo leve (custo) + effort high.
      MODEL_AUTO_MOVE = 'gpt-6-luna'.freeze
      MODEL_FOLLOWUP = 'gpt-6-luna'.freeze
      # E-mail builder copilot (multimodal generate). Full model — sees images/PDFs and writes MJML.
      # gpt-6.1-sol: mesma tarifa do 6-sol, mas leitura de cache -50% (pricing OpenAI, 2026-09-30).
      MODEL_EMAIL = 'gpt-6.1-sol'.freeze

      # REASONING EFFORT por tarefa (modelos seguem o leve). Todas as features leves usam 'high':
      # corte de custo (xhigh/max faturam muito mais token de raciocínio) sem trocar de modelo.
      # Escala da família 6: none/low/medium/high/xhigh/max.
      CLASSIFY_REASONING_EFFORT = 'high'.freeze
      SUMMARY_REASONING_EFFORT = 'high'.freeze
      VISION_REASONING_EFFORT = 'high'.freeze
      FOLLOWUP_REASONING_EFFORT = 'high'.freeze
      CALLBACK_REASONING_EFFORT = 'high'.freeze
      # Per-PDF byte cap and per-request PDF count cap for the e-mail copilot (guards download/base64
      # of attached PDFs before they become input_file content parts).
      PDF_BYTE_LIMIT = 32_000_000
      MAX_PDFS_PER_REQUEST = 5

      # AI auto follow-up ("de onde parou") MVP tuning.
      FOLLOWUP_MIN_CONFIDENCE = 0.6
      AUTO_FOLLOWUP_SCAN_CRON_MINUTES = 15
      AUTO_FOLLOWUP_TEMPLATE_CAP_HOURS = 24

      DEFAULT_AUTO_FOLLOWUP = {
        'enabled' => false,
        'mode' => 'auto_send',
        'allowed_days' => [0, 1, 2, 3, 4, 5, 6],
        'max_touches' => 3,
        'intervals_hours' => [20, 72, 168],
        'quiet_hours' => { 'start' => 8, 'end' => 20, 'tz' => 'contact' },
        'tone_instructions' => ''
      }.freeze

      # DETECÇÃO DE RETORNO POR DATA ("me liga terça que vem") — o classificador (que já lê TODA
      # mensagem) também extrai um pedido de retorno com data/hora; quando concreto e confiável, cria um
      # LEMBRETE (Crm::FollowUp reminder_only, type=call) na data — que já aparece no calendário e no
      # popup de lembrete. Só cria com confiança alta e data concreta futura (evita falso-positivo de
      # frase vaga). KILL-SWITCH: ENV AI_CALLBACK_DETECTION (default ON).
      CALLBACK_MIN_CONFIDENCE = 0.6
      CALLBACK_MAX_HORIZON_DAYS = 180          # ignora datas muito distantes (provável erro de leitura)
      CALLBACK_DEFAULT_HOUR = 9                 # sem hora/período → início do expediente
      CALLBACK_PERIOD_HOURS = { 'manha' => 9, 'tarde' => 14, 'noite' => 19 }.freeze

      def self.callback_detection_enabled?
        BOOLEAN.cast(ENV.fetch('AI_CALLBACK_DETECTION', true))
      end

      # Toggle POR FUNIL (pipeline.metadata['ai']['callback_enabled'], default LIGADO). Controlado na
      # config de IA do funil e no atalho do calendário. Combina com o kill-switch global da ENV.
      def self.pipeline_callback_enabled?(pipeline)
        pipeline_ai_settings(pipeline)[:callback_enabled] != false
      end

      # MODO do retorno por funil: 'reminder' (só lembrete na tela, default), 'message' (mensagem
      # auto-agendada na data — IA gera/escolhe template, fallback p/ lembrete) ou 'both' (os dois).
      CALLBACK_MODES = %w[reminder message both].freeze

      def self.pipeline_callback_mode(pipeline)
        mode = pipeline_ai_settings(pipeline)[:callback_mode].to_s
        CALLBACK_MODES.include?(mode) ? mode : 'reminder'
      end

      def self.attribute_extraction_enabled?
        raw = ENV.fetch('CRM_AI_ATTR_EXTRACTION', nil)
        enabled? && (raw.blank? || BOOLEAN.cast(raw))
      end

      # Score por funil, DESLIGADO por padrão: a IA passa a escrever em crm_cards.score de todos os
      # cards do funil, então a adoção é conta por conta, não por deploy.
      def self.pipeline_score_enabled?(pipeline)
        BOOLEAN.cast(pipeline_ai_settings(pipeline)[:score_enabled])
      end

      def self.pipeline_attribute_extraction_enabled?(pipeline)
        BOOLEAN.cast(pipeline_ai_settings(pipeline)[:attribute_extraction_enabled])
      end

      # Sem prefixo por padrão: a IA enxerga e preenche QUALQUER campo customizado da conta. Um funil
      # pode restringir gravando `attribute_prefix` no metadata (ex.: 'sw_' p/ o comportamento antigo).
      def self.attribute_extraction_prefix(pipeline)
        pipeline_ai_settings(pipeline)[:attribute_prefix].to_s
      end

      def self.attribute_extraction_min_confidence(pipeline)
        raw = pipeline_ai_settings(pipeline)[:attribute_min_confidence].presence || 0.6
        Float(raw).clamp(0.0, 1.0)
      rescue ArgumentError, TypeError
        0.6
      end

      # Timezone EFETIVO para ancorar "amanhã 10h" e gravar o lembrete: contato
      # (additional_attributes['timezone']) → país do contato → account.reporting_timezone →
      # default configurável (ENV['CRM_DEFAULT_TIMEZONE'] ou 'America/Sao_Paulo'). Espelha o
      # AutoFollowupPlanner (quiet hours) para consistência. Sempre devolve um nome de tz VÁLIDO.
      def self.resolved_timezone(account:, contact: nil)
        Crm::Timezone::Resolver.new(contact: contact, account: account).name_or_default
      end

      # Media enrichment (PR13.1): audio via transcription, image via vision caption.
      # whisper-1: aceita OGG/Opus (.oga — formato de voz do WhatsApp/WAHA), m4a (iOS/Instagram), mp3,
      # wav, webm. O gpt-4o-mini-transcribe REJEITA oga/ogg ("Unsupported file format oga", HTTP 400),
      # então quebrava a transcrição de áudio de WhatsApp. Override por ENV p/ trocar sem deploy.
      TRANSCRIBE_MODEL = ENV.fetch('CRM_AI_TRANSCRIBE_MODEL', 'whisper-1').freeze
      VISION_MODEL = 'gpt-6-luna'.freeze
      TRANSCRIPTION_BYTE_LIMIT = 25_000_000
      IMAGE_BYTE_LIMIT = 18_000_000
      # TTS (espelhamento de áudio — Onda 2c): voz a partir do texto da resposta. Saída `opus` = formato
      # de voz nativo do WhatsApp (toca como áudio de voz, não anexo). Override por ENV.
      TTS_MODEL = ENV.fetch('CRM_AI_TTS_MODEL', 'gpt-4o-mini-tts').freeze
      TTS_CHAR_LIMIT = 1200 # cap de entrada (custo/latência); a resposta do operate costuma ser curta
      MAX_MEDIA_ENRICH_PER_EVAL = 12
      TRANSCRIPT_MAX_CHARS = 1500
      CAPTION_MAX_CHARS = 400

      # Exclusão do follow-up automático de IA por contato (auto-followup e retorno por data).
      # Mora no contato, não no card, para valer em qualquer funil e sobreviver a um card novo. Contato fora do funil
      # (#2084, parceiro do mercado ou não é negócio) também fica de fora: a IA não corre atrás de quem não compra.
      CONTACT_FOLLOWUP_DISABLED_KEY = 'crm_ai_followup_disabled'.freeze

      def self.enabled?
        ::Crm::Config.enabled? && BOOLEAN.cast(ENV.fetch('CRM_AI_ENABLED', false))
      end

      def self.contact_followup_disabled?(contact)
        return false if contact.blank?
        return true if ::Crm::Relacao.fora_do_funil?(contact)

        BOOLEAN.cast(contact.additional_attributes.to_h[CONTACT_FOLLOWUP_DISABLED_KEY]) == true
      end

      def self.media_enabled?
        enabled? && BOOLEAN.cast(ENV.fetch('CRM_AI_MEDIA_ENABLED', true))
      end

      def self.pipeline_ai_settings(pipeline)
        (pipeline.metadata || {}).fetch('ai', {}).to_h.with_indifferent_access
      end

      # Agentes de área (#1447) só valem com a Fase 2 dos Agentes ligada na conta (e os Agentes ligados): sem ela, quem
      # responde é sempre a porta (Autonomia::Agents::QuemResponde), e entregar a conversa a uma área não teria efeito.
      def self.areas_ligadas?(account)
        account.present? && ::Autonomia::Agents::Config.enabled?(account) && ::Autonomia::Agents::Fase2.ligada?(account)
      end

      # Agente de IA responsável por caixa + funil (#1447): o agente que a tela "Quem cuida do quê?" gravou para o par,
      # se ele pode falar com cliente agora (atendendo, não interno, não de sistema). Sem a Fase 2, ou com o agente
      # parado, nil: o funil fica com a porta.
      def self.responsible_agent(inbox:, pipeline:)
        return if inbox.blank? || pipeline.blank? || !areas_ligadas?(inbox.account)

        linha = ::Crm::InboxAiAgent.where(inbox_id: inbox.id, pipeline_id: pipeline.id).select(:autonomia_agent_id)
        agente = ::Autonomia::Agents::Agent.kept.find_by(account_id: inbox.account_id, id: linha)
        agente if agente&.atende_cliente?
      end

      # Contrato com o Agentes IA (#1606, devolução de pessoa para a IA): o espelho (AgentBot) de área do responsável do
      # funil do assunto em foco (Crm::Assunto.funil_atual), com o mesmo critério do ResponsibleAgentSync#destino_para.
      # nil sem a Fase 2, sem card aberto, com o funil fora da caixa ou com a IA do funil desligada, com o agente parado
      # ou sem vínculo de área na caixa: aí quem recebe é a porta.
      def self.robo_do_funil(conversation)
        card = ::Crm::Assunto.funil_atual(conversation)
        return if card.nil? || !funil_de_destino?(card.pipeline, conversation.inbox)

        agente = responsible_agent(inbox: conversation.inbox, pipeline: card.pipeline)
        agent_inbox_for(inbox: conversation.inbox, agent: agente)&.agent_bot
      end

      # O vínculo de ÁREA do agente com a caixa (Autonomia::Agents::Areas): o espelho (AgentBot) dele ali é quem posta.
      # Sem vínculo, o agente não atende nessa caixa.
      def self.agent_inbox_for(inbox:, agent:)
        return if inbox.blank? || agent.blank?

        ::Autonomia::Agents::AgentInbox.kept.area.find_by(account_id: inbox.account_id, inbox_id: inbox.id, autonomia_agent_id: agent.id)
      end

      # Funil que pode receber um assunto aberto pelo agente: da conta, ativo, ligado à caixa (com o CRM ligado nela), com
      # etapa para o card nascer e a IA do funil ligada. O mesmo critério da IA de assunto (Crm::Subjects::Identifier#pipelines).
      def self.funil_de_destino?(pipeline, inbox)
        return false unless funil_da_caixa?(pipeline, inbox)

        pipeline.active? && pipeline_ai_settings(pipeline)[:enabled] != false && pipeline.stages.exists?
      end

      def self.funil_da_caixa?(pipeline, inbox)
        pipeline.present? && inbox.present? && pipeline.account_id == inbox.account_id &&
          ::Crm::InboxSetting.exists?(account_id: inbox.account_id, inbox_id: inbox.id, crm_enabled: true) &&
          pipeline.pipeline_inboxes.exists?(inbox_id: inbox.id)
      end
      private_class_method :funil_da_caixa?

      # Para onde o agente da conversa pode passar o cliente (#1447): os funis da caixa com responsável que é área nela,
      # menos o funil do assunto em atendimento. [{ pipeline_id:, nome:, agente_id:, agente_nome: }], na ordem do CRM.
      # Sem a Fase 2, vazio.
      def self.destinos_para(conversation)
        return [] unless areas_ligadas?(conversation.account)

        atual = ::Crm::Cards::ConversationCardFinder.new(account: conversation.account).find(conversation)
        fora = atual&.open? ? atual.pipeline_id : nil

        responsaveis_ligados(conversation.inbox).where.not(pipeline_id: fora).includes(:pipeline, :agent).to_a
                                                .select { |linha| destino?(linha, conversation.inbox) }
                                                .sort_by { |linha| [linha.pipeline.position, linha.pipeline.id] }
                                                .map { |linha| destino(linha) }
      end

      # As linhas da caixa cujo agente tem vínculo de área ativo com ela.
      def self.responsaveis_ligados(inbox)
        ligados = ::Autonomia::Agents::AgentInbox.kept.area.where(account_id: inbox.account_id, inbox_id: inbox.id)
                                                 .select(:autonomia_agent_id)
        ::Crm::InboxAiAgent.where(account_id: inbox.account_id, inbox_id: inbox.id, autonomia_agent_id: ligados)
      end
      private_class_method :responsaveis_ligados

      def self.destino?(linha, inbox)
        linha.agent.deleted_at.nil? && linha.agent.atende_cliente? && funil_de_destino?(linha.pipeline, inbox)
      end
      private_class_method :destino?

      def self.destino(linha)
        { pipeline_id: linha.pipeline.id, nome: linha.pipeline.name, agente_id: linha.agent.id, agente_nome: linha.agent.name }
      end
      private_class_method :destino

      def self.stage_ai_criteria(stage)
        (stage.metadata || {}).fetch('ai_criteria', '').to_s.strip
      end

      # Effective AI auto follow-up config for a pipeline. Pipeline-level
      # metadata.ai.auto_followup overrides the defaults; +enabled+ is always
      # cast to a real boolean so the planner/runner/scan-job can branch safely.
      def self.auto_followup_settings(pipeline)
        cfg = DEFAULT_AUTO_FOLLOWUP.merge(pipeline_ai_settings(pipeline).fetch('auto_followup', {}).to_h)
        cfg['enabled'] = BOOLEAN.cast(cfg['enabled'])
        cfg.with_indifferent_access
      end

      # Lembretes de Atender (#1498): avisar o andamento, perguntar se resolveu e, na Cobrança, lembrar do pagamento.
      # Vêm ligados só em funil criado pelos modelos de Atender (metadata.template); funil antigo convertido fica
      # desligado até alguém ligar, para nada mudar sozinho na conversão.
      SERVICE_REMINDER_KINDS = %w[progress resolved_check payment].freeze
      # #1589: o tempo de andamento e "deu certo?", em horas, escolhido na frase da tela. Só as opções dos botões valem;
      # qualquer outro valor (ou nenhum) é 1 dia, o tempo de antes da escolha.
      SERVICE_REMINDER_HOURS = { 'progress' => [4, 24, 48, 72], 'resolved_check' => [24, 48, 72, 168] }.freeze
      DEFAULT_SERVICE_REMINDER_HOURS = 24

      def self.service_reminders_settings(pipeline)
        saved = pipeline_ai_settings(pipeline).fetch('service_reminders', {}).to_h
        defaults = default_service_reminders(pipeline)
        ligados = SERVICE_REMINDER_KINDS.index_with do |kind|
          saved.key?(kind) ? BOOLEAN.cast(saved[kind]) == true : defaults[kind]
        end
        ligados.merge(service_reminder_hours(saved)).with_indifferent_access
      end

      # { 'progress_after_hours' => 24, 'resolved_check_after_hours' => 24 }
      def self.service_reminder_hours(saved)
        SERVICE_REMINDER_HOURS.to_h do |kind, opcoes|
          chave = "#{kind}_after_hours"
          [chave, service_reminder_option(opcoes, saved[chave]) || DEFAULT_SERVICE_REMINDER_HOURS]
        end
      end

      # A opção da tela que o valor é, exatamente (24 ou "24"); nil para qualquer outra coisa. Sem converter: "0x18" ou
      # 24.0 e 24.9 não viram 24.
      def self.service_reminder_option(opcoes, valor)
        opcoes.find { |horas| horas.eql?(valor) || horas.to_s.eql?(valor) }
      end

      # Modelos sem pedido aberto: sem aviso de andamento nem "deu certo?". Cobrança tem o lembrete de pagamento; a
      # Carteira (#2083) acompanha quem já tem plano, e o card fica meses em "Em uso" (a pessoa pode ligar depois).
      SEM_PEDIDO_TEMPLATES = %w[COBRANCA CARTEIRA].freeze

      def self.default_service_reminders(pipeline)
        template = (pipeline.metadata || {})['template'].to_s
        novo_de_atender = !pipeline.counts_as_sale? && template.present? && template != 'VENDAS'
        acompanha = novo_de_atender && SEM_PEDIDO_TEMPLATES.exclude?(template)
        { 'progress' => acompanha, 'resolved_check' => acompanha, 'payment' => novo_de_atender && template == 'COBRANCA' }
      end

      # Don't re-hand-off the same conversation within this window (loop/spam guard).
      HANDOFF_COOLDOWN_SECONDS = 6 * 60 * 60
      # TTL do convite R3: fecha ciclos esquecidos sem re-notificar nem escalar.
      HANDOFF_INVITE_TTL_SECONDS = 24 * 60 * 60
      HANDOFF_PICKUP_THRESHOLD_SECONDS = 15 * 60
      HANDOFF_MODES = %w[direct round_robin].freeze
      # 'ai_agent' (#1593): "A mesma pessoa" é um agente de IA (pool_id = id do Autonomia::Agents::Agent). Só vale com a
      # Fase 2 dos Agentes e na caixa em que ele trabalha; senão a conversa vai para alguém da equipe (Crm::Entrega).
      HANDOFF_POOL_TYPES = %w[inbox user ai_agent].freeze
      HANDOFF_ESCALATION_ACTIONS = %w[renotify escalate].freeze
      HANDOFF_RENOTIFY_MAX = 8
      # Fluxo do handoff: r2_direct = atribui direto (comportamento legado);
      # r3_invite = convida (participante + notificação) sem atribuir/calar o bot.
      HANDOFF_FLOW_MODES = %w[r2_direct r3_invite].freeze

      # Effective handoff config for a card's current stage. Stage-level config
      # overrides pipeline-level defaults so a funnel can set a baseline and a
      # stage can refine it.
      def self.handoff_settings(stage, pipeline)
        pipeline_cfg = pipeline_ai_settings(pipeline).fetch('handoff', {}).to_h
        stage_cfg = (stage&.metadata || {}).fetch('ai_handoff', {}).to_h
        cfg = pipeline_cfg.merge(stage_cfg)
        mode = handoff_selector(cfg)
        pickup_threshold_seconds = handoff_pickup_threshold_seconds(cfg)
        escalation_user_id = handoff_escalation_user_id(cfg)
        legacy_handoff_settings(cfg, mode, pickup_threshold_seconds, escalation_user_id)
          .merge(pool_handoff_settings(cfg, pickup_threshold_seconds, escalation_user_id))
          .with_indifferent_access
      end

      def self.legacy_handoff_settings(cfg, mode, pickup_threshold_seconds, escalation_user_id)
        {
          enabled: BOOLEAN.cast(cfg['enabled']),
          mode: mode,
          selector_mode: handoff_selector_mode(cfg, mode),
          handoff_mode: HANDOFF_FLOW_MODES.include?(cfg['handoff_mode']) ? cfg['handoff_mode'] : 'r2_direct',
          trigger: cfg['trigger'].to_s.strip,
          prefer_online: cfg.key?('prefer_online') ? BOOLEAN.cast(cfg['prefer_online']) : true,
          invite_ttl_seconds: handoff_invite_ttl_seconds(cfg),
          pickup_threshold_seconds: pickup_threshold_seconds,
          escalation_user_id: escalation_user_id
        }
      end
      private_class_method :legacy_handoff_settings

      def self.pool_handoff_settings(cfg, pickup_threshold_seconds, escalation_user_id)
        {
          pool_type: handoff_pool_type(cfg),
          pool_id: handoff_pool_id(cfg),
          renotify_after_seconds: handoff_renotify_after_seconds(cfg, pickup_threshold_seconds),
          escalation_action: handoff_escalation_action(cfg, escalation_user_id)
        }
      end
      private_class_method :pool_handoff_settings

      def self.handoff_invite_ttl_seconds(cfg)
        raw = cfg['invite_ttl_seconds'].to_s.strip
        parsed = raw.match?(/\A\d+\z/) ? raw.to_i : 0
        parsed.positive? ? parsed : HANDOFF_INVITE_TTL_SECONDS
      end

      def self.handoff_pickup_threshold_seconds(cfg)
        value = cfg['pickup_threshold_seconds']
        return HANDOFF_PICKUP_THRESHOLD_SECONDS unless value.to_s.match?(/\A\d+\z/)

        seconds = value.to_i
        seconds.positive? ? seconds : HANDOFF_PICKUP_THRESHOLD_SECONDS
      end

      def self.handoff_escalation_user_id(cfg)
        value = cfg['escalation_user_id']
        return value if value.is_a?(Integer) && value.positive?
        return unless value.is_a?(String) && value.match?(/\A\d+\z/)

        user_id = value.to_i
        user_id.positive? ? user_id : nil
      end

      def self.handoff_selector(cfg)
        HANDOFF_MODES.include?(cfg['mode']) ? cfg['mode'] : 'round_robin'
      end
      private_class_method :handoff_selector

      def self.handoff_selector_mode(cfg, mode)
        HANDOFF_MODES.include?(cfg['selector_mode']) ? cfg['selector_mode'] : mode
      end
      private_class_method :handoff_selector_mode

      def self.handoff_pool_type(cfg)
        HANDOFF_POOL_TYPES.include?(cfg['pool_type']) ? cfg['pool_type'] : 'inbox'
      end
      private_class_method :handoff_pool_type

      def self.handoff_pool_id(cfg)
        value = cfg['pool_id']
        return value if value.is_a?(Integer) && value.positive?
        return unless value.is_a?(String) && value.match?(/\A\d+\z/)

        pool_id = value.to_i
        pool_id.positive? ? pool_id : nil
      end
      private_class_method :handoff_pool_id

      def self.handoff_renotify_after_seconds(cfg, fallback)
        value = cfg['renotify_after_seconds']
        return fallback unless value.to_s.match?(/\A\d+\z/)

        seconds = value.to_i
        seconds.positive? ? seconds : fallback
      end
      private_class_method :handoff_renotify_after_seconds

      def self.handoff_escalation_action(cfg, escalation_user_id)
        action = if HANDOFF_ESCALATION_ACTIONS.include?(cfg['escalation_action'])
                   cfg['escalation_action']
                 else
                   default_escalation_action(escalation_user_id)
                 end
        action == 'escalate' && escalation_user_id.blank? ? 'renotify' : action
      end
      private_class_method :handoff_escalation_action

      def self.default_escalation_action(escalation_user_id) = escalation_user_id.present? ? 'escalate' : 'renotify'
      private_class_method :default_escalation_action
    end
  end
end
