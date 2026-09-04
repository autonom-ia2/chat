# == Schema Information
#
# Table name: autonomia_agent_knowledge
#
#  id                 :bigint           not null, primary key
#  chunk_index        :integer          default(0), not null
#  content            :text             not null
#  embedding          :vector(1536)
#  embedding_large    :halfvec(3072)
#  metadata           :jsonb            not null
#  status             :integer          default("ready"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  autonomia_agent_id :bigint           not null
#  source_id          :bigint
#
# Indexes
#
#  idx_autonomia_knowledge_agent_status                   (autonomia_agent_id,status)
#  idx_autonomia_knowledge_embedding                      (embedding) USING ivfflat
#  idx_autonomia_knowledge_embedding_large                (embedding_large) USING hnsw
#  index_autonomia_agent_knowledge_on_account_id          (account_id)
#  index_autonomia_agent_knowledge_on_autonomia_agent_id  (autonomia_agent_id)
#  index_autonomia_agent_knowledge_on_source_id           (source_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (autonomia_agent_id => autonomia_agents.id)
#
module Autonomia
  module Agents
    class KnowledgeEntry < ApplicationRecord
      self.table_name = 'autonomia_agent_knowledge'

      has_neighbors :embedding, normalize: true # gem neighbor (cosine via normalize)

      belongs_to :account
      belongs_to :agent, class_name: 'Autonomia::Agents::Agent',
                         foreign_key: :autonomia_agent_id
      belongs_to :source, class_name: 'Autonomia::Agents::Source',
                          foreign_key: :source_id, optional: true

      enum status: { pending: 0, ready: 1 }
    end
  end
end
