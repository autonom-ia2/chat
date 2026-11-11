# #2414 F1.3 (D2/D4): montar e ligar automação pelo Guia vale para quem tem a chave de automação, não só para quem
# administra a conta. Fora estas ações, o catálogo segue só para quem administra (Acoes#garantir_permitida!).
# As chaves de cada ação são as mesmas da policy do recurso (AutomationRulePolicy, Autonomia::DecisorPolicy e, na etapa
# do CRM, StageAutomationPolicy), para o Guia não propor o que a plataforma vai recusar. Quem decide no fim é a policy,
# pelo token da pessoa.
class Autonomia::Guide::PorteiroDaAutomacao
  REGRAS = [
    'POST automation_rules', 'PATCH automation_rules/:id', 'PUT automation_rules/:id', 'DELETE automation_rules/:id',
    'POST automation_rules/:automation_rule_id/clone',
    'POST autonomia/decisores', 'PATCH autonomia/decisores/:id', 'PUT autonomia/decisores/:id', 'DELETE autonomia/decisores/:id',
    'POST autonomia/decisores/:id/teste', 'POST autonomia/decisores/:id/exemplos', 'POST autonomia/decisoes/:id/resolver'
  ].freeze

  # #2889: as automações do motor novo, pelas mesmas chaves da Autonomia::Automacao::DefinicaoPolicy. Ligar não está
  # aqui: só a pessoa liga, na tela (Acoes::SO_NA_TELA). Não há rota de apagar. O passo de funil (chave de funis) quem
  # confere é o controller, que olha a receita inteira.
  MOTOR_NOVO = ['POST autonomia/automacoes', 'PATCH autonomia/automacoes/:id', 'PUT autonomia/automacoes/:id',
                'POST autonomia/automacoes/:id/desligar'].freeze
  ENSAIO = ['POST automation_rules/:id/ensaio', 'POST autonomia/automacoes/ensaio', 'POST autonomia/automacoes/:id/ensaio'].freeze

  ETAPA = [
    'POST crm/stages/:stage_id/stage_automations', 'PATCH crm/stage_automations/:id', 'PUT crm/stage_automations/:id',
    'DELETE crm/stage_automations/:id', 'POST crm/stage_automations/:stage_automation_id/steps',
    'PATCH crm/stage_automations/:stage_automation_id/steps/:id', 'PUT crm/stage_automations/:stage_automation_id/steps/:id',
    'DELETE crm/stage_automations/:stage_automation_id/steps/:id'
  ].freeze

  # Recusa (chave i18n) => o que a pessoa precisa ter: cada grupo é uma alternativa de chaves, e todos os grupos valem.
  # Na etapa do CRM, `crm_admin` vale por `crm_manage_pipelines`, como no CrmPermissions.
  EXIGENCIAS = {
    'automation_manage_only' => [%w[automation_manage]],
    'stage_automation_manage_only' => [%w[automation_manage], %w[crm_manage_pipelines crm_admin]],
    # O ensaio só lê: mostra o que a regra faria (#859).
    'automation_view_only' => [%w[automation_view]]
  }.freeze

  RECUSA_POR_ACAO = REGRAS.index_with('automation_manage_only')
                          .merge(MOTOR_NOVO.index_with('automation_manage_only'))
                          .merge(ETAPA.index_with('stage_automation_manage_only'))
                          .merge(ENSAIO.index_with('automation_view_only')).freeze

  # Criar e mudar regra: com ação ou condição de funil, pede também a chave de funis (RegraDoFunil). A cópia e a
  # mudança sem as ações no corpo ficam com o controller, que olha a regra gravada.
  REGRA_COM_CORPO = ['POST automation_rules', 'PATCH automation_rules/:id', 'PUT automation_rules/:id'].freeze

  # nil quando pode; senão a chave i18n da recusa. Sem a flag `automacao_fundacao`, o Guia segue só para quem administra.
  def self.recusa(acao, account_user, corpo = {})
    return 'admin_only' unless Autonomia::Automacao.fundacao?(account_user&.account)

    recusa = RECUSA_POR_ACAO[acao.to_s]
    return 'admin_only' if recusa.nil?
    return recusa if account_user.blank?
    return recusa unless cumpre?(recusa, account_user)

    'rule_funnel_manage_only' if mexe_no_funil_sem_chave?(acao, account_user, corpo)
  end

  def self.mexe_no_funil_sem_chave?(acao, account_user, corpo)
    return false unless REGRA_COM_CORPO.include?(acao.to_s)

    corpo = corpo.to_h.with_indifferent_access
    funil = Autonomia::Automacao::RegraDoFunil
    funil.mexe?(corpo[:actions], corpo[:conditions]) && !funil.pode?(account_user)
  end

  def self.cumpre?(recusa, account_user)
    EXIGENCIAS.fetch(recusa).all? { |alternativas| alternativas.any? { |chave| account_user.permission_granted?(chave) } }
  end
end
