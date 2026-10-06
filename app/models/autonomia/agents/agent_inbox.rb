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
#  inbox_id           :bigint
#
# Indexes
#
#  idx_autonomia_agent_inboxes_on_inbox_uniq            (inbox_id) UNIQUE
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
    # Vínculo agente nativo ↔ inbox (Fase C). UNIQUE em inbox_id garante 1 bot por inbox.
    # `agent_bot` é o AgentBot nativo-espelho (outgoing_url NULL) usado como sender canônico
    # da resposta outgoing — entra no fluxo de bot do core sem disparar webhook (Gabriela).
    class AgentInbox < ApplicationRecord
      self.table_name = 'autonomia_agent_inboxes'

      scope :kept, -> { where(deleted_at: nil) }

      belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id
      belongs_to :inbox
      belongs_to :account
      # NON-optional: o AgentBot espelho é o sender canônico da resposta outgoing.
      # Sem ele a Message perde a identidade de AgentBot-sender (garantia anti-loop).
      belongs_to :agent_bot

      validates :inbox_id, uniqueness: { conditions: -> { kept } }, if: -> { deleted_at.nil? }
      # Tenancy (defesa em profundidade): o runtime resolve o vínculo só por inbox_id
      # (Operate.eligible_agent_inbox), então um registro inconsistente cruzaria contas.
      validate :linked_records_must_belong_to_account

      # Limpeza do espelho ao destruir o vínculo — centraliza o conserto de "caixa deletada"
      # E "agente deletado" num só lugar. Dispara quando o vínculo cai por:
      #   • Inbox#destroy  → has_many :autonomia_agent_inboxes, dependent: :destroy
      #   • Agent#destroy  → has_many :agent_inboxes, dependent: :destroy
      # Sem isso, o AgentBot-espelho + AgentBotInbox vazariam (hoje só o InboxConnector#disconnect!
      # os remove). Espelho da nossa criação: outgoing_url NULL → NUNCA toca a Gabriela (webhook real).
      after_destroy :cleanup_mirror_bot

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

      # Devolve ao humano as conversas em que o bot ainda está no comando: as `pending` da caixa e as
      # `open` que têm o espelho como ai_assignee (na caixa do espelho elas nascem open — ver
      # Conversation#set_active_bot_conversation). Mesmo caminho do disconnect manual.
      def release_bot_conversations!
        return if inbox.nil?

        pending = inbox.conversations.where(status: :pending)
        held_by_mirror = inbox.conversations.where(status: :open, assignee_agent_bot_id: agent_bot_id)
        pending.or(held_by_mirror).find_each(&:bot_handoff!)
      end

      private

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
