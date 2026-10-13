module Crm
  module Ai
    class SettingsPresenter
      def initialize(pipeline:)
        @pipeline = pipeline
      end

      def perform
        {
          enabled: pipeline_settings[:enabled] != false,
          auto_move_enabled: pipeline_settings[:auto_move_enabled] == true,
          attribute_extraction_enabled: pipeline_settings[:attribute_extraction_enabled] == true,
          score_enabled: pipeline_settings[:score_enabled] == true,
          callback_enabled: pipeline_settings[:callback_enabled] != false,
          callback_mode: Config.pipeline_callback_mode(@pipeline),
          stale_hours: pipeline_settings[:stale_hours].presence || Config::DEFAULT_STALE_HOURS,
          auto_followup: Config.auto_followup_settings(@pipeline),
          handoff: Config.handoff_settings(nil, @pipeline),
          inboxes: @pipeline.inboxes.order(:name, :id).map { |inbox| { id: inbox.id, name: inbox.name } },
          team: team,
          stages: stages
        }
      end

      private

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

      def pipeline_settings
        Config.pipeline_ai_settings(@pipeline)
      end
    end
  end
end
