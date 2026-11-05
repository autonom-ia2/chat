# As condições de uma regra antiga (`automation_rules.conditions`) no formato do motor novo (#2568, F9).
#
# No antigo, o `query_operator` de cada condição liga ela à próxima, e o filtro vira SQL na ordem em que estão: o AND
# pesa mais que o OR (`a AND b OR c` = `(a e b) ou c`). Por isso a lista é cortada no OR em grupos de AND:
# `alguma[todas[a, b], todas[c]]`. Uma condição com vários valores (`inbox_id` igual a [1, 2]) vale qualquer um deles.
#
# O `not_equal_to` antigo vira `NOT IN` no SQL, e o campo vazio (NULL) não casa: "time diferente de 3" numa conversa
# sem time não dispara. O `diferente` novo casa com o vazio; por isso, nos campos da conversa e do contato, ele vai
# junto com `preenchido`. Nas etiquetas não (o antigo usa NOT EXISTS), nem no card (o antigo dá verdadeiro sem card).
#
# Atributo personalizado: o antigo compara texto em minúsculas e só com o 1º valor; o novo compara como está, então o
# texto vira falta até a F9.0. O `not_equal_to` antigo monta SQL quebrado (`custom_attribute_filter_helper.rb`); a
# conversão corrige (Automação, 05/11): diferente, com o atributo vazio contando como diferente, que era a intenção do
# `OR ... IS NULL` antigo.
class Autonomia::Automacao::Conversao::Condicoes
  Mapa = Autonomia::Automacao::Conversao::Mapa

  attr_reader :faltas, :ressalvas

  # O antigo compara em minúsculas os atributos destes tipos (FilterService::ATTRIBUTE_TYPES → 'text').
  TIPOS_DE_TEXTO = %w[text link list].freeze

  def initialize(condicoes, gatilho:, conta:)
    @condicoes = Array(condicoes)
    @gatilho = gatilho
    @conta = conta
    @faltas = []
    @ressalvas = []
  end

  # A condição única do filtro do gatilho, ou nil quando a regra não tem condição.
  def filtro
    condicoes = @condicoes.filter_map { |condicao| condicao.is_a?(Hash) ? condicao.stringify_keys : falta('formato_desconhecido', condicao) }
    return if condicoes.empty?

    grupos = grupos_por_ou(condicoes).filter_map { |grupo| juntar('todas', grupo.filter_map { |condicao| converter(condicao) }) }
    juntar('alguma', grupos)
  end

  private

  def grupos_por_ou(condicoes)
    condicoes.each_with_object([[]]) do |condicao, grupos|
      grupos.last << condicao
      grupos << [] if condicao['query_operator'].to_s.casecmp?('or')
    end.reject(&:empty?)
  end

  def juntar(chave, lista)
    return if lista.empty?

    lista.one? ? lista.first : { chave => lista }
  end

  def converter(condicao)
    campo = campo(condicao)
    operador = campo && operador(condicao)
    return unless operador
    return { 'campo' => { '$valor' => campo }, 'op' => operador } if %w[vazio preenchido].include?(operador)

    valores = Array(condicao['values']).map { |valor| valor_novo(condicao, valor) }
    return falta('condicao_sem_valor', condicao['attribute_key']) if valores.empty?

    comparacoes(campo, operador, valores.map { |valor| { 'campo' => { '$valor' => campo }, 'op' => operador, 'valor' => valor } })
  end

  def comparacoes(campo, operador, lista)
    return juntar('alguma', lista) unless %w[diferente nao_contem].include?(operador)
    return juntar('todas', lista) unless operador == 'diferente' && com_preenchido?(campo)

    juntar('todas', [{ 'campo' => { '$valor' => campo }, 'op' => 'preenchido' }, *lista])
  end

  # Só nos campos da plataforma na conversa e no contato; o atributo personalizado (`contato.atributos.x`) e o card não.
  def com_preenchido?(campo) = Mapa::CAMPO.value?(campo) && campo.start_with?('conversa.', 'contato.')

  def campo(condicao)
    chave = condicao['attribute_key'].to_s
    return campo_da_plataforma(chave) if Mapa::CAMPO.key?(chave)

    base = Mapa::BASE_DO_ATRIBUTO[condicao['custom_attribute_type'].to_s]
    return falta('campo_sem_valor', chave) unless base
    return falta('atributo_sem_maiusculas', chave) if %w[equal_to not_equal_to].include?(condicao['filter_operator']) && texto?(condicao)

    if condicao['filter_operator'] == 'not_equal_to'
      @ressalvas << "diferente_corrigido: #{chave}: o antigo não disparava ou escapava da precedência; o novo dispara"
    end
    "#{base}.#{chave}"
  end

  # Pelo tipo do atributo na conta, como o antigo decide, e não pela classe do valor ("3" num atributo numérico).
  def texto?(condicao)
    definicao = @conta.custom_attribute_definitions.find_by(attribute_key: condicao['attribute_key'],
                                                            attribute_model: condicao['custom_attribute_type'])
    TIPOS_DE_TEXTO.include?(definicao&.attribute_display_type)
  end

  # `mensagem.*` só existe no gatilho mensagem.criada (o esquema recusa nos outros).
  def campo_da_plataforma(chave)
    return falta('campo_sem_valor', chave) if Mapa::CAMPO[chave].start_with?('mensagem.') && @gatilho != 'mensagem.criada'

    Mapa::CAMPO[chave]
  end

  def operador(condicao)
    nome = condicao['filter_operator'].to_s
    return falta('condicao_mudou', condicao['attribute_key']) if nome == 'attribute_changed'

    tabela = Mapa::CAMPOS_EM_LISTA.include?(condicao['attribute_key']) ? Mapa::OPERADOR_EM_LISTA : Mapa::OPERADOR
    tabela[nome] || falta('operador_texto', "#{condicao['attribute_key']} #{nome}")
  end

  def valor_novo(condicao, valor)
    return valor unless condicao['attribute_key'] == 'message_type'

    Mapa::TIPO_DE_MENSAGEM.fetch(valor.to_s) { falta('campo_sem_valor', "message_type #{valor}") || valor.to_s }
  end

  def falta(chave, detalhe)
    @faltas << { chave: chave, fase: Mapa::FALTA.fetch(chave), detalhe: detalhe.to_s }
    nil
  end
end
