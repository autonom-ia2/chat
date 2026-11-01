# A receita de uma automação (#2414 F3, ADR-001 2.1 e 2.3). O formato mora no esquema
# (lib/operator_guide/automacao-receita.schema.json), que o Versao confere pelo JsonSchemaValidator. Aqui fica o que o
# esquema não sabe dizer, conferido ao salvar:
# - o id de cada passo é único na receita inteira (o cursor da execução aponta para ele);
# - a ação está na lista de permitidas (F3.2) e tem todo parâmetro do caminho;
# - o corpo bate com o formato da ação, como no Guia, e traz o que a automação exige (F3.10);
# - todo `$valor` é um caminho que a automação sabe ler.
class Autonomia::Automacao::Receita
  ESQUEMA = JSON.parse(Rails.root.join('lib/operator_guide/automacao-receita.schema.json').read).freeze
  RAMOS = %w[entao senao se_vencer].freeze

  # O JsonSchemaValidator põe o erro na chave de dentro (`gatilho`), não em `receita`; quem segue para a conferência
  # do código pergunta aqui.
  def self.no_esquema?(receita)
    JSONSchemer.schema(ESQUEMA).valid?(JSON.parse(receita.to_json))
  end

  def initialize(receita, conta:)
    @receita = receita
    @conta = conta
  end

  # Frases para a pessoa (ou o Guia) corrigir. Vazio = pode salvar. Só roda com a receita já no esquema.
  def problemas
    [*ids_repetidos, *filtros_do_gatilho, *passos.flat_map { |passo| problemas_do_passo(passo) }]
  end

  # Todos os passos, inclusive os de dentro dos ramos, na ordem em que aparecem.
  def passos(lista = @receita['passos'])
    Array(lista).flat_map { |passo| [passo, *RAMOS.flat_map { |ramo| passos(passo[ramo]) }] }
  end

  private

  def ids_repetidos
    passos.pluck('id').tally.select { |_id, vezes| vezes > 1 }.keys.map { |id| texto(:id_repetido, passo: id) }
  end

  def filtros_do_gatilho
    Array(@receita.dig('gatilho', 'filtros')).flat_map { |condicao| caminhos_desconhecidos('gatilho', condicao) }
  end

  def problemas_do_passo(passo)
    return caminhos_desconhecidos(passo['id'], passo['condicao']) if passo.key?('condicao')
    return [] unless passo['tipo'] == 'acao'

    problemas_da_acao(passo)
  end

  def caminhos_desconhecidos(id, condicao)
    ::Autonomia::Automacao::Condicao.caminhos(condicao).reject { |caminho| ::Autonomia::Automacao::Valores.caminho_valido?(caminho) }
                                    .map { |caminho| texto(:valor_desconhecido, passo: id, caminho: caminho) }
  end

  def problemas_da_acao(passo)
    acao = passo['acao']
    return [texto(:acao_fora, passo: passo['id'], acao: acao)] unless ::Autonomia::Automacao::AcoesPermitidas.permitida?(acao)

    [*caminho_da_acao(passo), *corpo_da_acao(passo)]
  end

  def caminho_da_acao(passo)
    valores = passo['caminho'].to_h
    faltando = parametros(passo['acao']).reject { |nome| valores[nome].present? }
                                        .map { |nome| texto(:caminho_faltando, passo: passo['id'], campo: nome) }
    lidos = valores.values.filter_map { |valor| valor['$valor'] if valor.is_a?(Hash) }
    faltando + lidos.reject { |caminho| ::Autonomia::Automacao::Valores.caminho_valido?(caminho) }
                    .map { |caminho| texto(:valor_desconhecido, passo: passo['id'], caminho: caminho) }
  end

  def corpo_da_acao(passo)
    conferencia = ::Autonomia::Guide::Formatos::Conferencia.new(passo['acao'], passo['corpo'].to_h, conta: @conta)
    exigidos = ::Autonomia::Automacao::AcoesPermitidas.exige(passo['acao']).select { |campo| conferencia.valores[campo].blank? }

    conferencia.problemas_em_texto.map { |problema| texto(:corpo, passo: passo['id'], problema: problema) } +
      exigidos.map { |campo| texto(:exige, passo: passo['id'], campo: campo) }
  end

  def parametros(acao)
    acao.split(' ', 2).last.split('/').filter_map { |segmento| segmento.delete_prefix(':') if segmento.start_with?(':') }
  end

  def texto(chave, **valores)
    I18n.t("autonomia.automacao.receita.#{chave}", **valores)
  end
end
