# #858 — automação com Decisor que fica LIGADA depois do pedido do Guia age sozinha a cada gatilho:
# pergunta ao Jev, manda mensagem, move card. O desfazer apaga a automação, não o que ela já fez.
# Então criar ligada (ela nasce ligada quando o corpo não diz), ligar, ou pôr o Decisor numa automação
# ligada não tem desfazer e passa pela confirmação da pessoa (`Acoes#desfazivel?`). É isto que garante
# "só liga depois que a pessoa aprova o teste" — não o texto do manual.
#
# Vale para as regras de automação e para as automações de etapa do CRM, que têm o mesmo passo.
class Autonomia::Guide::RegraComDecisor
  REGRAS = ['POST automation_rules', 'PATCH automation_rules/:id'].freeze
  ETAPAS = ['POST crm/stages/:stage_id/stage_automations', 'PATCH crm/stage_automations/:id', 'PUT crm/stage_automations/:id'].freeze
  PASSOS_DE_ETAPA = ['POST crm/stage_automations/:stage_automation_id/steps', 'PATCH crm/stage_automations/:stage_automation_id/steps/:id',
                     'PUT crm/stage_automations/:stage_automation_id/steps/:id'].freeze

  def initialize(account)
    @account = account
  end

  def fica_ligada?(acao, dados)
    return false if dados.nil?
    return regra_ligada?(acao, dados) if REGRAS.include?(acao)
    return etapa_ligada?(acao, dados) if ETAPAS.include?(acao)
    return passo_em_etapa_ligada?(acao, dados) if PASSOS_DE_ETAPA.include?(acao)

    false
  end

  private

  def regra_ligada?(acao, dados)
    corpo = corpo(dados)
    regra = acao.start_with?('PATCH') ? @account.automation_rules.find_by(id: caminho(dados)[:id]) : nil
    ligada?(corpo, :active, regra&.active) && com_decisor?(corpo.key?(:actions) ? corpo[:actions] : regra&.actions, :action_name)
  end

  def etapa_ligada?(acao, dados)
    corpo = corpo(dados, :stage_automation)
    automacao = acao.start_with?('POST') ? nil : @account.crm_stage_automations.find_by(id: caminho(dados)[:id])
    passos = corpo.key?(:steps) ? corpo[:steps] : automacao&.steps&.map(&:attributes)
    ligada?(corpo, :enabled, automacao&.enabled) && com_decisor?(passos, :action_type)
  end

  # Mudando um passo sem dizer o tipo (só o `decisor_id` ou a `chave_que_segue`), vale o tipo gravado.
  def passo_em_etapa_ligada?(acao, dados)
    automacao = @account.crm_stage_automations.find_by(id: caminho(dados)[:stage_automation_id])
    return false unless automacao&.enabled?

    passo = corpo(dados, :step)
    gravado = acao.start_with?('POST') || passo.key?(:action_type) ? nil : automacao.steps.find_by(id: caminho(dados)[:id])
    com_decisor?([gravado ? passo.merge(action_type: gravado.action_type) : passo], :action_type)
  end

  # Sem o campo no corpo, vale o que já está gravado; criando, nasce ligada.
  def ligada?(corpo, campo, atual)
    return ActiveModel::Type::Boolean.new.cast(corpo[campo]) == true if corpo.key?(campo)

    atual.nil? || atual
  end

  def com_decisor?(passos, campo)
    Array(passos).any? { |passo| passo.to_h.with_indifferent_access[campo] == ::Autonomia::Decisores::PASSO }
  end

  # O controller do CRM aceita o corpo com ou sem a chave raiz (`parameter_set`).
  def corpo(dados, raiz = nil)
    corpo = (dados[:corpo] || {}).to_h.with_indifferent_access
    raiz && corpo[raiz].is_a?(Hash) ? corpo[raiz].with_indifferent_access : corpo
  end

  def caminho(dados)
    (dados[:caminho] || {}).to_h.with_indifferent_access
  end
end
