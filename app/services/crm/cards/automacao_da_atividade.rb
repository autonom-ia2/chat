# A automação que fez a atividade do card (#2509). O Mover e o Closer gravam `by: 'automacao'`, a `origem` (`livre`,
# `regra` ou `etapa`) e o `automacao_id` (#2428). A linha do tempo mostra "Automação «nome»" em vez da pessoa que a
# ligou ou do "sistema". Os nomes saem numa consulta por origem, só das automações desta conta.
#
# `pode_abrir`: a tela liga o nome à automação só quando a pessoa vê as automações (automation_view) e a tela dela
# existe: a da Automação livre pede a flag automacao_editor, a da regra pede automations. A de etapa mora na
# configuração do funil e fica sem link.
class Crm::Cards::AutomacaoDaAtividade
  MODELOS = {
    'livre' => [Autonomia::Automacao::Definicao, :nome],
    'regra' => [AutomationRule, :name],
    'etapa' => [Crm::StageAutomation, :name]
  }.freeze
  TELA = { 'livre' => 'automacao_editor', 'regra' => 'automations' }.freeze

  def initialize(account:, account_user:, activities:)
    @account = account
    @account_user = account_user
    @activities = activities
  end

  def para(activity)
    origem, id = origem_e_id(activity)
    return if origem.nil?

    nome = nomes.dig(origem, id)
    { origem: origem, id: id, nome: nome, pode_abrir: nome.present? && pode_abrir?(origem) }
  end

  private

  def origem_e_id(activity)
    return unless activity.payload.is_a?(Hash)

    payload = activity.payload.stringify_keys
    return unless payload['by'] == 'automacao' && MODELOS.key?(payload['origem'])

    id = payload['automacao_id'].to_i
    [payload['origem'], id] if id.positive?
  end

  def nomes
    @nomes ||= @activities.filter_map { |activity| origem_e_id(activity) }.group_by(&:first).to_h do |origem, pares|
      modelo, coluna = MODELOS.fetch(origem)
      [origem, modelo.where(account_id: @account.id, id: pares.map(&:last).uniq).pluck(:id, coluna).to_h]
    end
  end

  def pode_abrir?(origem)
    TELA.key?(origem) && @account_user&.permission_granted?('automation_view') && @account.feature_enabled?(TELA[origem])
  end
end
