module Crm
  module Ai
    class SettingsPresenter
      # `quem_recebe: true` (só a tela de Atribuição de um funil, #1140) traz `recebem_por_caixa`; a lista de funis não paga
      # essa conta.
      def initialize(pipeline:, quem_recebe: false)
        @pipeline = pipeline
        @quem_recebe = quem_recebe
      end

      def perform
        ajustes.merge(ai_agents).merge(@quem_recebe ? { recebem_por_caixa: recebem_por_caixa } : {})
      end

      private

      def ajustes
        {
          enabled: pipeline_settings[:enabled] != false,
          auto_move_enabled: pipeline_settings[:auto_move_enabled] == true,
          attribute_extraction_enabled: pipeline_settings[:attribute_extraction_enabled] == true,
          score_enabled: pipeline_settings[:score_enabled] == true,
          callback_enabled: pipeline_settings[:callback_enabled] != false,
          callback_mode: Config.pipeline_callback_mode(@pipeline),
          stale_hours: pipeline_settings[:stale_hours].presence || Config::DEFAULT_STALE_HOURS,
          auto_followup: Config.auto_followup_settings(@pipeline),
          service_reminders: Config.service_reminders_settings(@pipeline),
          handoff: Config.handoff_settings(nil, @pipeline),
          inboxes: @pipeline.inboxes.order(:name, :id).map { |inbox| { id: inbox.id, name: inbox.name } },
          team: team,
          stages: stages
        }
      end

      def stages
        @pipeline.stages.order(:position, :id).map do |stage|
          {
            id: stage.id,
            name: stage.name,
            ai_criteria: Config.stage_ai_criteria(stage),
            handoff: Config.handoff_settings(stage, @pipeline),
            handoff_custom: (stage.metadata || {}).key?('ai_handoff')
          }
        end
      end

      # Quem está nas caixas ligadas ao funil (`inboxes`): é entre essas pessoas que a passagem escolhe
      # (HandoffMemberSelector usa os membros da caixa). As duas listas vão junto aqui para a tela de passagem funcionar
      # com a permissão de IA do CRM, sem depender das telas de caixas e de caixas do funil, que exigem poder configurar
      # caixa ou funil (#1385). Só quem ainda está na conta.
      def team
        User.joins(:inbox_members, :account_users)
            .where(inbox_members: { inbox_id: @pipeline.pipeline_inboxes.select(:inbox_id) })
            .where(account_users: { account_id: @pipeline.account_id })
            .distinct.order(:name, :id).pluck(:id, :name)
            .map { |id, name| { id: id, name: name } }
      end

      # #1140 (correção 3): em cada caixa do funil, quem pode receber uma conversa dele, pela regra do motor de entrega
      # (Crm::Entrega::QuemCuida.na_caixa). A tela avisa quando a pessoa fixa de uma regra não está entre elas: lá a
      # conversa vai para quem cuida do funil.
      def recebem_por_caixa
        @pipeline.inboxes.order(:name, :id).map do |inbox|
          { inbox_id: inbox.id, name: inbox.name,
            user_ids: Crm::Entrega::QuemCuida.na_caixa(inbox: inbox, pipeline_id: @pipeline.id).map(&:id) }
        end
      end

      # #1593: os agentes de IA das caixas do funil, só com a Fase 2 dos Agentes (sem ela a chave não vai e a tela mostra
      # só pessoas). Os que as regras salvas apontam vêm sempre, marcados parados quando não podem mais receber.
      def ai_agents
        agentes = Crm::AgentesIa.do_funil(@pipeline, escolhidos: agentes_escolhidos)
        agentes.nil? ? {} : { ai_agents: agentes }
      end

      def agentes_escolhidos
        regras = [Config.handoff_settings(nil, @pipeline)] + @pipeline.stages.map { |stage| Config.handoff_settings(stage, @pipeline) }
        regras.select { |regra| regra[:pool_type] == 'ai_agent' }.filter_map { |regra| regra[:pool_id] }.uniq
      end

      def pipeline_settings
        Config.pipeline_ai_settings(@pipeline)
      end
    end
  end
end
