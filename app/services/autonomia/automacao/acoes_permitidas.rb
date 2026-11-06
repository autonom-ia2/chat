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

  # Ação de funil (crm/) pede também a chave de funis, ao salvar e a cada execução (D2, #2633). O recurso sai da própria
  # lista, não do catálogo: ação permitida sempre tem recurso, e a pergunta é a mesma no salvar e no motor.
  def de_funil?(acao)
    lista['passo'].any? { |recurso, bloco| recurso.start_with?('crm/') && bloco['acoes'].key?(acao.to_s) }
  end

  # Campos que a receita tem de preencher além do que a plataforma pede (F3.10: descrição).
  def exige(acao)
    Array(acoes.dig(acao.to_s, 'exige'))
  end

  # Campos que a receita manda sempre com este valor: { 'merge' => true }.
  def fixos(acao)
    acoes.dig(acao.to_s, 'fixos').to_h
  end

  # Campos que a receita tem de mandar com um destes valores: { 'result' => ['won', 'lost'] }.
  def um_de(acao)
    acoes.dig(acao.to_s, 'um_de').to_h
  end

  # Campos que a receita não pode mandar.
  def proibe(acao)
    Array(acoes.dig(acao.to_s, 'proibe'))
  end

  # O que o corpo da ação fere nas regras da lista, na ordem exige, fixos, proíbe e um_de:
  # [[chave da frase em autonomia.automacao.receita, { campo:, ... }], ...]. A Receita monta a frase.
  def fora_da_lista(acao, valores)
    faltando(acao, valores) + trocados(acao, valores) + proibidos(acao, valores) + fora_das_opcoes(acao, valores)
  end

  def faltando(acao, valores) = exige(acao).select { |campo| valores[campo].blank? }.map { |campo| [:exige, { campo: campo }] }

  def trocados(acao, valores)
    fixos(acao).reject { |campo, valor| valores[campo] == valor }.map { |campo, valor| [:fixo, { campo: campo, valor: valor }] }
  end

  def proibidos(acao, valores)
    proibe(acao).select { |campo| mandado?(valores, campo.split('.')) }.map { |campo| [:proibido, { campo: campo }] }
  end

  def fora_das_opcoes(acao, valores)
    um_de(acao).reject { |campo, opcoes| opcoes.include?(valores[campo]) }
               .map { |campo, opcoes| [:um_de, { campo: campo, opcoes: opcoes.join(', ') }] }
  end

  def mandado?(valores, partes)
    return valores.key?(partes.first) if partes.one?

    valores[partes.first].is_a?(Hash) && mandado?(valores[partes.first], partes.drop(1))
  end

  # Os recursos que nunca viram passo (ADR-001 2.1), para o CI cobrar.
  def sempre_fora
    lista['fora'].select { |grupo| grupo['sempre'] }.flat_map { |grupo| grupo['recursos'] }
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
