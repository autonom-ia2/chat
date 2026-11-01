# As ações da plataforma que viram passo da Automação livre (#2414 F3.2, ADR-001 2.1, D3 e D13).
#
# A lista mora em lib/operator_guide/automacao-recursos.yml, recurso a recurso, com o motivo. O recurso é o controller
# da ação no catálogo do Guia (formatos-das-acoes.json), sem o prefixo da conta. "Fora" é o padrão: só as ações
# listadas em `passo` são permitidas. A receita é recusada ao salvar com ação fora daqui, e o motor confere de novo na
# hora de rodar.
module Autonomia::Automacao::AcoesPermitidas
  ARQUIVO = Rails.root.join('lib/operator_guide/automacao-recursos.yml')
  PREFIXO_DA_CONTA = 'api/v1/accounts/'.freeze

  # Apagar estrutura fica só no Guia, com confirmação (D13, F3.11): a automação roda sem ninguém olhando, e um erro de
  # montagem que apaga repetidamente é defeito, não uso. O spec do CI cobra que nenhum DELETE destes vire passo.
  ESTRUTURA = %w[crm/pipelines crm/stages inboxes agents labels custom_attribute_definitions].freeze

  module_function

  def permitida?(acao)
    acoes.key?(acao.to_s)
  end

  # Campos que a receita tem de preencher além do que a plataforma pede (F3.10: descrição).
  def exige(acao)
    Array(acoes.dig(acao.to_s, 'exige'))
  end

  # { 'POST labels' => { 'exige' => ['description'] }, ... }
  def acoes
    @acoes ||= lista['passo'].values.reduce({}) { |todas, bloco| todas.merge(bloco['acoes']) }.freeze
  end

  def recurso_de(acao)
    ::Autonomia::Guide::Formatos.para(acao)&.fetch('controller')&.split('#')&.first&.delete_prefix(PREFIXO_DA_CONTA)
  end

  def classificados
    lista['passo'].keys + lista['fora'].flat_map { |grupo| grupo['recursos'] }
  end

  def lista
    @lista ||= YAML.safe_load_file(ARQUIVO).freeze
  end
end
