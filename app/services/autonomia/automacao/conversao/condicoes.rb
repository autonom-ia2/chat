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
# Atributo personalizado de texto: o antigo compara em minúsculas e só com o 1º valor, e o `not_equal_to` dele monta
# SQL quebrado (`custom_attribute_filter_helper.rb`). O novo compara como está. Nada disso é traduzido em silêncio:
# vira falta.
class Autonomia::Automacao::Conversao::Condicoes
  Mapa = Autonomia::Automacao::Conversao::Mapa

  attr_reader :faltas, :ressalvas

  def initialize(condicoes, gatilho:)
    @condicoes = Array(condicoes)
    @gatilho = gatilho
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
    return juntar('todas', lista) unless operador == 'diferente' && campo.start_with?('conversa.', 'contato.')

    juntar('todas', [{ 'campo' => { '$valor' => campo }, 'op' => 'preenchido' }, *lista])
  end

  def campo(condicao)
    chave = condicao['attribute_key'].to_s
    return campo_da_plataforma(chave) if Mapa::CAMPO.key?(chave)

    base = Mapa::BASE_DO_ATRIBUTO[condicao['custom_attribute_type'].to_s]
    return falta('campo_sem_valor', chave) unless base
    return falta('diferente_de_atributo', chave) if condicao['filter_operator'] == 'not_equal_to'
    return falta('atributo_sem_maiusculas', chave) if condicao['filter_operator'] == 'equal_to' && texto?(condicao)

    "#{base}.#{chave}"
  end

  def texto?(condicao) = Array(condicao['values']).any?(String)

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
