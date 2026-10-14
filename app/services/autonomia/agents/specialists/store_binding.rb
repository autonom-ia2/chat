# frozen_string_literal: true

require 'delegate'

# Read-through definition, with execution authority and costs bound to the buyer account.
class Autonomia::Agents::Specialists::StoreBinding < SimpleDelegator
  attr_reader :agent

  def initialize(specialist, agent:)
    super(specialist)
    @agent = agent
  end

  def account
    agent.account
  end

  def account_id
    agent.account_id
  end

  def tools
    catalog = Autonomia::Agents::Tools::Bound.for_agent(agent, especialista: self).index_by(&:slug)
    ferramentas_do_sistema.filter_map { |slug| catalog[slug.to_s] }
  end
end
