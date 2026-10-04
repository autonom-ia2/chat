class Crm::StageAutomations::Persister
  def initialize(account:, user:, stage:, attributes:)
    @account = account
    @user = user
    @stage = stage
    @attributes = attributes.to_h.with_indifferent_access
  end

  def create!
    automation = @account.crm_stage_automations.create!(
      pipeline: @stage.pipeline,
      stage: @stage,
      name: @attributes[:name],
      description: @attributes[:description],
      trigger_event: @attributes[:trigger_event],
      enabled: @attributes.key?(:enabled) ? @attributes[:enabled] : true,
      position: @attributes[:position] || next_position,
      created_by: @user,
      metadata: @attributes[:metadata] || {}
    )
    replace_steps!(automation)
    automation
  end

  def update!(automation)
    automation.update!(automation_attributes)
    replace_steps!(automation) if @attributes.key?(:steps)
    automation
  end

  private

  def automation_attributes
    @attributes.slice(:name, :description, :trigger_event, :enabled, :position, :metadata).compact
  end

  # A tela manda todos os passos a cada salvar. Eles são atualizados no lugar, na ordem, e só os que
  # sobram são apagados: o id do passo sobrevive a um salvar que só renomeia — a espera do Decisor
  # (#858) e o passo atrasado (StageAutomationStepJob) guardam esse id.
  def replace_steps!(automation)
    steps = @attributes[:steps]
    return if steps.blank?

    existentes = automation.steps.ordered.to_a
    steps.each_with_index do |step_attrs, index|
      valores = step_values(step_attrs.to_h.with_indifferent_access, index)
      existentes[index] ? existentes[index].update!(valores) : automation.steps.create!(valores)
    end
    automation.steps.where(id: existentes.drop(steps.size).map(&:id)).destroy_all
  end

  def step_values(attrs, index)
    { account: @account, position: attrs[:position] || index, delay_seconds: attrs[:delay_seconds] || 0,
      action_type: attrs[:action_type], action_config: attrs[:action_config] || {} }
  end

  def next_position
    (@account.crm_stage_automations.where(stage_id: @stage.id).maximum(:position) || -1) + 1
  end
end
