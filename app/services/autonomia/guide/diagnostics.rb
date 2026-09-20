module Autonomia
  module Guide
    # V3 — READ-ONLY diagnostics for the Guia da Plataforma. Given an account + user, inspects the real
    # account state and returns human-readable pt_BR findings (problems + how to fix). NEVER writes:
    # every branch only reads ActiveRecord / jsonb columns / Redis GET (reauthorization_required?) /
    # ENV. Methods that mutate or hit the network (authorization_error!, prompt_reauthorization!,
    # validate_provider_config?, access_token refresh, Waha::Client, token services, Creator/jobs) are
    # intentionally AVOIDED. Fail-safe: any error → nil (the guide just answers without live state).
    class Diagnostics
      CHECKS = %w[channel notifications ai_agent routing calendar].freeze

      def self.run(check, account:, user:)
        new(account: account, user: user).run(check)
      end

      def initialize(account:, user:)
        @account = account
        @user = user
      end

      # Tri-state: Array<String> of pt_BR findings on success (may be empty = nothing wrong), or nil when
      # the check itself failed — so the caller never turns an error into a false "tudo certo".
      def run(check)
        return nil unless CHECKS.include?(check.to_s)

        send(check.to_s)
      rescue StandardError => e
        Rails.logger.error("[autonomia][guide][diagnostics] #{check} account=#{@account&.id}: #{e.class}: #{e.message}")
        nil
      end

      private

      def inboxes
        @inboxes ||= @account.inboxes.includes(:channel).to_a
      end

      def reauth?(channel)
        channel.respond_to?(:reauthorization_required?) && channel.reauthorization_required?
      end

      # Account-controlled strings (inbox name, mailbox e-mail) are interpolated into the findings, which
      # are later injected into the LLM context. Strip brackets/newlines/control chars + cap length so a
      # crafted inbox name can't break out of the [ESTADO REAL ...] block or inject instructions.
      def safe(str)
        visivel = str.to_s.delete('[]').chars.map { |c| c.ord < 32 ? ' ' : c }.join
        visivel.squeeze(' ').strip[0, 80].to_s
      end

      # --- CANAIS / conexão de caixa ---
      def channel
        return ['A conta ainda não tem nenhuma caixa de entrada criada — não há por onde receber mensagens. Crie uma em Configurações > Caixas de entrada > Nova caixa.'] if inboxes.empty?

        findings = []
        inboxes.each do |inbox|
          ch = inbox.channel
          label = safe(inbox.name)
          next if ch.nil?

          if inbox.whatsapp?
            pc = (ch.provider_config || {}).to_h
            if pc['source'] == 'embedded_signup' && reauth?(ch)
              findings << "WhatsApp Oficial \"#{label}\": a autorização com a Meta expirou — reconecte/reautorize nas Configurações da caixa."
            elsif ch.provider == 'whatsapp_cloud' && (pc['api_key'].blank? || pc['phone_number_id'].blank? || pc['business_account_id'].blank?)
              findings << "WhatsApp Oficial \"#{label}\": credenciais da Meta incompletas (Token, Phone Number ID ou Business Account ID) — preencha nas Configurações da caixa."
            end
          end

          if inbox.api? && ch.respond_to?(:waha_provider?) && ch.waha_provider?
            aa = (ch.additional_attributes || {}).to_h
            findings << "WhatsApp API \"#{label}\": ainda não foi totalmente provisionado — abra a caixa em Conexão e leia o QR Code para parear." if aa['session'].blank? || aa['app_id'].blank?
          end

          if inbox.email?
            if ch.try(:google?) || ch.try(:microsoft?) || ch.try(:legacy_google?)
              findings << "E-mail \"#{label}\": a conta Google/Microsoft perdeu a autorização (OAuth) — reconecte refazendo o login." if (ch.provider_config || {}).to_h.empty? || reauth?(ch)
            else
              findings << "E-mail \"#{label}\": recebimento por IMAP desligado — novos e-mails não entram. Ative o IMAP nas Configurações da caixa." if ch.try(:imap_enabled) != true
              findings << "E-mail \"#{label}\": envio não configurado (SMTP desligado e não verificado) — dá pra receber mas não responder. Ative o SMTP." if ch.try(:smtp_enabled) != true && ch.try(:verified_for_sending) != true
            end
          end

          findings << "Instagram \"#{label}\": a autorização com a Meta expirou — reconecte refazendo o login." if (inbox.instagram? || inbox.try(:instagram_direct?)) && reauth?(ch)
          findings << "Facebook \"#{label}\": a autorização da página com a Meta expirou — reconecte a página." if inbox.facebook? && reauth?(ch)
          findings << "Caixa \"#{label}\": sem nenhum agente nem bot — mesmo recebendo mensagens, ninguém vê as conversas. Adicione um agente em Configurações da caixa > Colaboradores." if inbox.inbox_members.empty? && inbox.agent_bot_inbox.nil?
        end
        findings
      end

      # --- NOTIFICAÇÕES ---
      def notifications
        findings = []
        s = @user.notification_settings.find_by(account_id: @account.id)
        if s.nil?
          findings << 'Não há configuração de notificação salva para você nesta conta — abra Perfil > Configurações de notificação e salve as preferências ao menos uma vez.'
        else
          if s.push_flags.to_i.zero?
            findings << 'Todas as notificações push estão desativadas — ative em Perfil > Configurações de notificação.'
          elsif !(s.push_conversation_assignment? || s.push_assigned_conversation_new_message? || s.push_conversation_mention?)
            findings << 'Os pushes dos eventos principais (conversa atribuída, nova mensagem atribuída, menção) estão desligados.'
          end
          if s.email_flags.to_i.zero?
            findings << 'Todas as notificações por e-mail estão desativadas — ative em Perfil > Configurações de notificação.'
          elsif !(s.email_conversation_assignment? || s.email_assigned_conversation_new_message? || s.email_conversation_mention?)
            findings << 'Os e-mails dos eventos principais (conversa atribuída, nova mensagem atribuída, menção) estão desligados.'
          end
        end

        subs = @user.notification_subscriptions
        if subs.empty?
          findings << 'Nenhuma inscrição de push registrada (navegador/app) — acesse pelo navegador e permita as notificações quando solicitado.'
        elsif subs.where(subscription_type: NotificationSubscription.subscription_types[:browser_push]).none?
          findings << 'Sem inscrição de push do navegador — habilite as notificações no navegador onde usa o Chatwoot.'
        end

        findings << 'Seu e-mail ainda não foi confirmado — os e-mails de notificação não são enviados até confirmar (reenvie o e-mail de confirmação e clique no link).' if @user.confirmed_at.nil?
        findings
      end

      # --- IA / AGENTE AUTONOMIA ---
      def ai_agent
        findings = []
        unless ::Autonomia::Agents::Config.enabled?(@account)
          findings << 'Os Agentes de IA (Autonomia) não estão habilitados para esta conta — sem isso nenhum agente responde.'
        end
        findings << 'Nenhuma chave de IA configurada/resolvível (chave do Kanban AI da conta ou de sistema) — sem ela o agente não gera respostas.' unless ::Crm::Ai::CredentialResolver.new(account: @account).configured?

        agent = ::Autonomia::Agents::Agent
        active = agent.where(account_id: @account.id, enabled: true, status: agent.statuses[:active])
        operable = active.where(actuation: [agent.actuations[:external], agent.actuations[:both]])
                         .where("COALESCE(config->>'system_key','') = ''")
        if !active.exists?
          findings << 'Nenhum agente habilitado E ativo nesta conta — agentes em rascunho/pausados não respondem.'
        elsif !operable.exists?
          findings << 'Há agente ativo, mas nenhum apto a atender o cliente: todos são internos (copiloto) ou de sistema. Mude a atuação para Externo/Ambos.'
        elsif !::Autonomia::Agents::AgentInbox.where(account_id: @account.id, autonomia_agent_id: operable.select(:id)).exists?
          findings << 'Existe agente apto, mas ele não está conectado a nenhuma caixa de entrada — conecte-o a uma caixa (aba Canais do agente).'
        end
        findings
      end

      # --- ROTEAMENTO / ATRIBUIÇÃO AUTOMÁTICA ---
      def routing
        findings = []
        inboxes.each do |inbox|
          label = "Caixa \"#{safe(inbox.name)}\""
          unless inbox.enable_auto_assignment?
            findings << "#{label}: atribuição automática DESLIGADA — novas conversas ficam sem responsável até alguém pegar manualmente."
            next
          end
          members = inbox.inbox_members.to_a
          if members.empty?
            findings << "#{label}: atribuição automática ligada, mas SEM agentes vinculados — ninguém para atribuir. Adicione agentes em Colaboradores."
            next
          end
          cfg = inbox.auto_assignment_config.is_a?(Hash) ? inbox.auto_assignment_config : {}
          findings << "#{label}: há um limite de conversas por agente definido — se todos atingirem o limite, ninguém fica elegível e novas conversas não são atribuídas." if cfg['max_assignment_limit'].to_i.positive?

          member_ids = members.map(&:user_id)
          online = @account.account_users.human.where(user_id: member_ids).any? { |au| au.availability == 'online' }
          findings << "#{label}: nenhum agente vinculado está 'Online' no cadastro — a atribuição automática só envia para agentes online." unless online
          findings << "#{label}: horário de funcionamento ativo e FORA do expediente agora — a atribuição cai/zera fora do horário." if inbox.working_hours_enabled? && inbox.out_of_office?
        end
        findings
      end

      # --- CALENDÁRIO / REUNIÕES ---
      def calendar
        return ['O recurso de reuniões/calendário está desligado nesta instalação (CRM_CALENDAR_MEETINGS_ENABLED) — é ajuste de servidor; peça ao administrador da plataforma para ativar.'] unless ::Crm::Config.calendar_meetings_enabled?(@account)

        email_channels = inboxes.map(&:channel).compact.select { |c| c.is_a?(::Channel::Email) }
        oauth = email_channels.select { |c| %w[google microsoft].include?(c.provider) }
        return ['Nenhuma caixa de e-mail conectada via Google/Microsoft (OAuth) — só esses provedores oferecem calendário. Conecte usando "Entrar com Google/Microsoft".'] if oauth.empty?

        cal = oauth.select { |c| c.calendar_enabled == true }
        return ['Há caixa Google/Microsoft conectada, mas nenhuma com o calendário habilitado — reconecte autorizando o acesso ao Calendário.'] if cal.empty?

        findings = []
        cal.each do |c|
          name = c.respond_to?(:email) && c.email.present? ? safe(c.email) : "caixa ##{c.try(:inbox)&.id}"
          findings << "Calendário (#{name}): conectado SEM a permissão de calendário — reconecte aceitando o escopo de Calendário." if c.calendar_scope_granted != true
          cfg = (c.provider_config || {}).to_h
          findings << "Calendário (#{name}): faltam os tokens de acesso (access/refresh) — reconecte pelo 'Entrar com Google/Microsoft' para repopular." if cfg['refresh_token'].blank? || cfg['access_token'].blank?
          findings << "Calendário (#{name}): a caixa acumulou falhas e está marcada para reautorizar — reconecte a conta Google/Microsoft." if reauth?(c)
        end
        findings
      end
    end
  end
end
