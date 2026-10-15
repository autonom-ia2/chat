# == Schema Information
#
# Table name: autonomia_agent_inboxes
#
#  id                 :bigint           not null, primary key
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  agent_bot_id       :bigint           not null
#  autonomia_agent_id :bigint           not null
#  deleted_at         :datetime
#  inbox_id           :bigint
#  papel              :string           default("porta"), not null
#
# Indexes
#
#  idx_autonomia_agent_inboxes_on_live_inbox_agent_uniq  (inbox_id,autonomia_agent_id) UNIQUE WHERE (deleted_at IS NULL)
#  idx_autonomia_agent_inboxes_on_live_porta_uniq        (inbox_id) UNIQUE WHERE (papel = 'porta' AND deleted_at IS NULL)
#  index_autonomia_agent_inboxes_on_account_id          (account_id)
#  index_autonomia_agent_inboxes_on_agent_bot_id        (agent_bot_id)
#  index_autonomia_agent_inboxes_on_autonomia_agent_id  (autonomia_agent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (agent_bot_id => agent_bots.id)
#  fk_rails_...  (autonomia_agent_id => autonomia_agents.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
module Autonomia
  module Agents
    # Vínculo agente nativo ↔ inbox (Fase C). `agent_bot` é o AgentBot nativo-espelho (outgoing_url NULL) usado como
    # sender canônico da resposta outgoing — entra no fluxo de bot do core sem disparar webhook (Gabriela).
    #
    # Papel na caixa (#1433):
    # - porta: atende primeiro todas as conversas da caixa. Uma por caixa; o espelho dela tem o AgentBotInbox, então é
    #   o inbox.agent_bot (InboxConnector).
    # - area:  agente da equipe; recebe a conversa quando alguém passa (vira o ai_assignee com o espelho dele). Em
    #   caixa com porta ativa ou só de pessoas (sem porta e sem robô de fora); espelho próprio SEM AgentBotInbox
    #   (Autonomia::Agents::Areas).
    # Um agente tem no máximo um vínculo ativo por caixa. Quem responde a conversa: Autonomia::Agents::QuemResponde.
    class AgentInbox < ApplicationRecord
      self.table_name = 'autonomia_agent_inboxes'

      PAPEIS = %w[porta area].freeze
      # Folga sobre a janela do debounce para um turno da área ainda contar como EM ANDAMENTO: a chamada de IA (com
      # ferramentas) e a entrega em pedaços que vêm depois do settle (#1433).
      FOLGA_DO_TURNO = 2.minutes

      scope :kept, -> { where(deleted_at: nil) }
      scope :porta, -> { where(papel: 'porta') }
      scope :area, -> { where(papel: 'area') }

      belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id
      belongs_to :inbox
      belongs_to :account
      # NON-optional: o AgentBot espelho é o sender canônico da resposta outgoing.
      # Sem ele a Message perde a identidade de AgentBot-sender (garantia anti-loop).
      belongs_to :agent_bot

      validates :papel, inclusion: { in: PAPEIS }
      validates :inbox_id, uniqueness: { conditions: -> { kept.porta } }, if: -> { deleted_at.nil? && porta? }
      validates :autonomia_agent_id, uniqueness: { scope: :inbox_id, conditions: -> { kept } }, if: -> { deleted_at.nil? }
      validate :area_precisa_de_porta_ou_caixa_so_de_pessoas, if: -> { deleted_at.nil? && area? }
      # Tenancy (defesa em profundidade): o runtime resolve o vínculo só por inbox_id
      # (Operate.eligible_agent_inbox), então um registro inconsistente cruzaria contas.
      validate :linked_records_must_belong_to_account

      # #1366 — o PONTO ÚNICO da parada automática: todo caminho que tira um vínculo da caixa passa por um destes dois
      # (arquivar: desvincular a área; destroy, abaixo: desconectar a porta, caixa apagada). Saiu o último, o agente
      # para. O SoftDelete arquiva sem callback: o agente apagado já sai parado. O destroy do próprio agente não conta.
      after_update :parar_agente_sem_onde_trabalhar, if: -> { saved_change_to_deleted_at? && deleted_at.present? }

      # Limpeza do espelho ao destruir o vínculo — centraliza o conserto de "caixa deletada"
      # E "agente deletado" num só lugar. Dispara quando o vínculo cai por:
      #   • Inbox#destroy  → has_many :autonomia_agent_inboxes, dependent: :destroy
      #   • Agent#destroy  → has_many :agent_inboxes, dependent: :destroy
      # Sem isso, o AgentBot-espelho + AgentBotInbox vazariam (hoje só o InboxConnector#disconnect!
      # os remove). Espelho da nossa criação: outgoing_url NULL → NUNCA toca a Gabriela (webhook real).
      after_destroy :cleanup_mirror_bot
      after_destroy :parar_agente_sem_onde_trabalhar, unless: :saindo_com_o_agente?

      # #1035 — liga/desliga o espelho conforme o agente atende ou não. Desligando: inativa ANTES de
      # liberar, para que nenhuma conversa nova nasça com o bot enquanto as atuais voltam para a equipe.
      def sync_mirror!(operating:)
        if operating
          mirror_bot_inboxes.inactive.find_each { |bot_inbox| bot_inbox.update!(status: :active) }
        else
          mirror_bot_inboxes.active.find_each { |bot_inbox| bot_inbox.update!(status: :inactive) }
          release_bot_conversations!
        end
      end

      # O que é espelho de agente da plataforma: todo agent_bot de um vínculo, apagado ou não, de porta ou de área, em
      # qualquer caixa (#1648). A mesma regra para a lista de Agentes externos (RobosSemEspelho), o `externo` e o
      # `tipo_do_principal` do CRM e o robo_externo_na_caixa?: espelho nunca é agente externo.
      def self.espelhos
        unscoped.select(:agent_bot_id)
      end

      # Robô de fora da Autonom.ia na caixa (#1433): um AgentBotInbox cujo robô não é espelho de agente da plataforma
      # (AgentInbox.espelhos, #1648) — bot de webhook, como o n8n. Com ele, a caixa sem porta não é só de pessoas e não
      # recebe agente da equipe.
      def self.robo_externo_na_caixa?(inbox_id)
        AgentBotInbox.where(inbox_id: inbox_id).where.not(agent_bot_id: espelhos).exists?
      end

      def porta?
        papel == 'porta'
      end

      def area?
        papel == 'area'
      end

      # Devolve ao humano as conversas em que o bot ainda está no comando: as `pending` da caixa e as
      # `open` que têm o espelho como ai_assignee (na caixa do espelho elas nascem open — ver
      # Conversation#set_active_bot_conversation). Mesmo caminho do disconnect manual.
      # Área (#1433): só as conversas do espelho dela, que voltam para a porta (as `pending` da caixa são da porta); sem
      # porta atendendo, vão para a equipe humana.
      # Porta saindo (#1433, decisão do Rodrigo de 15/10): as áreas da caixa FICAM e a caixa passa a ser só de pessoas;
      # só as conversas da porta saem, pela regra de sempre. As da área continuam com ela.
      def release_bot_conversations!
        return if inbox.nil?
        return devolver_conversas_a_porta! if area?

        # Só as pending SEM dono ou do espelho desta porta: a pending que já tem uma área como ai_assignee é dela e fica
        # com ela quando a porta sai (#1433).
        pending = inbox.conversations.where(status: :pending, assignee_agent_bot_id: [nil, agent_bot_id])
        held_by_mirror = inbox.conversations.where(status: :open, assignee_agent_bot_id: agent_bot_id)
        # Desligar não é passar a conversa: o robô sai de vez, sem ficar esperando pessoa (#1377).
        pending.or(held_by_mirror).find_each { |conversation| conversation.bot_handoff!(keep_bot: false) }
      end

      # O turno desta mensagem ainda está em andamento: a marca do debounce do ReplyJob (a mesma que o settle confere)
      # aponta para ela e é recente. Também refaz o turno quando o dono muda (Operate::ReenfileirarTurno, #1606).
      def turno_em_andamento?(conversation, mensagem)
        stamp = conversation.additional_attributes.to_h[::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY]
        return false unless stamp.is_a?(Hash) && stamp['pending_message_id'] == mensagem.id

        janela = ::Autonomia::Agents::Config.debounce_seconds_for(agent) + FOLGA_DO_TURNO
        stamp['at'].to_f >= janela.ago.to_f
      end

      private

      # A conversa aberta que a área atendia volta para o robô da caixa (a porta), pelo mesmo caminho de atribuir um
      # robô pelo painel, e a porta responde à última mensagem do cliente que ficou sem resposta. Sem porta atendendo
      # (ou caixa só de pessoas), ou conversa já à espera de pessoa: vai para a equipe humana, sem robô.
      def devolver_conversas_a_porta!
        robo_da_porta = inbox.agent_bot_inbox&.active? ? inbox.agent_bot : nil
        inbox.conversations.where(status: :open, assignee_agent_bot_id: agent_bot_id).find_each do |conversation|
          if robo_da_porta.nil? || conversation.bot_handoff_waiting?
            conversation.bot_handoff!(keep_bot: false)
          else
            ::Conversations::AssignmentService.new(conversation: conversation, assignee_id: robo_da_porta.id,
                                                   assignee_type: 'AgentBot').perform
            responder_mensagem_pendente(conversation)
          end
        end
      end

      # Desmarcar ou pausar a área no meio de um turno dela silencia esse turno (o Responder reconfere quem responde).
      # Só ESSE turno é refeito pela porta: a última mensagem pública é do cliente E a marca do debounce do ReplyJob
      # (a mesma que o settle confere) aponta para ela e é recente. Mensagem antiga sem turno nunca vira resposta nova.
      # Enfileira depois do commit; o debounce e o `already_replied?` do Responder seguram resposta dupla.
      def responder_mensagem_pendente(conversation)
        ultima = conversation.messages.where(private: false, message_type: %i[incoming outgoing]).reorder(:created_at, :id).last
        return unless ultima&.incoming? && turno_em_andamento?(conversation, ultima)

        ActiveRecord.after_all_transactions_commit do
          ::Autonomia::Agents::Operate::ReplyJob.perform_later(conversation.id, ultima.id)
        end
      end

      # Caixa com porta ativa, ou só de pessoas (sem porta e sem robô de fora, #1433).
      def area_precisa_de_porta_ou_caixa_so_de_pessoas
        return if inbox_id.blank?
        return if self.class.kept.porta.where(inbox_id: inbox_id).where.not(id: id).exists?
        return unless self.class.robo_externo_na_caixa?(inbox_id)

        errors.add(:papel, 'area requires an active porta or an inbox served only by people')
      end

      def mirror_bot_inboxes
        AgentBotInbox.where(inbox_id: inbox_id, agent_bot_id: agent_bot_id)
      end

      def linked_records_must_belong_to_account
        return if account_id.blank?

        %i[agent inbox agent_bot].each do |association_name|
          record = public_send(association_name)
          next if record.blank? || record.account_id == account_id

          errors.add(association_name, 'must belong to the same account')
        end
      end

      def parar_agente_sem_onde_trabalhar
        agent.parar_se_sem_onde_trabalhar!(vinculo: self)
      end

      def saindo_com_o_agente?
        destroyed_by_association&.active_record == ::Autonomia::Agents::Agent
      end

      def cleanup_mirror_bot
        return if deleted_at.present?

        mirror_bot_inboxes.destroy_all
        # Guarda dura: só remove o AgentBot se for o espelho (outgoing_url NULL). Um bot webhook
        # (Gabriela) jamais é apagado por este caminho, mesmo que algum dado fique inconsistente.
        AgentBot.where(id: agent_bot_id, outgoing_url: nil).find_each(&:destroy)
      end
    end
  end
end
