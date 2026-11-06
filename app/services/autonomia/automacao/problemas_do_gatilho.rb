# O que a Receita confere no gatilho de card e no de tempo (#2499): a flag da F6 (o de card pede também o CRM; o de
# reunião, G12, também as reuniões da instalação, com frase própria) e que a
# etapa, o funil e o campo de data escolhidos são da conta. O esquema já conferiu os tipos e quais parâmetros cada
# gatilho traz; aqui fica o que só o banco responde.
#
# No recorrente (#2635, G7), a seleção: pelo menos uma condição (sem nenhuma, a automação pegaria a conta inteira por
# engano), só as condições do alvo (card ou contato) e funil, etapa, responsável, etiqueta e atributo da conta. O da
# conta não tem seleção (o esquema recusa).
#
# No card atualizado (G27, #2661), a mudança: o campo personalizado é do card, desta conta, e a condição numérica
# (maior que, passou de) tem número para comparar.
class Autonomia::Automacao::ProblemasDoGatilho
  Gatilhos = ::Autonomia::Automacao::Gatilhos
  MudancaDoCard = ::Autonomia::Automacao::MudancaDoCard

  def initialize(gatilho, conta)
    @gatilho = gatilho
    @tipo = gatilho['tipo']
    @conta = conta
  end

  # Frases para a pessoa corrigir; vazio = pode salvar.
  def problemas
    return [] unless Gatilhos.do_card?(@tipo) || Gatilhos.de_tempo?(@tipo)

    desligado = Gatilhos.desligado(@tipo, @conta)
    return [texto(desligado)] if desligado

    return [] if Gatilhos.da_conta?(@tipo)
    return selecao if Gatilhos.recorrente?(@tipo)

    [*etapa_de_fora, *funil_de_fora, *parado_sem_dias, *campo_de_fora, *da_mudanca]
  end

  private

  def etapa_de_fora
    etapa = @gatilho['etapa_id']
    etapa && !@conta.crm_pipeline_stages.exists?(id: etapa) ? [texto(:etapa_de_fora, id: etapa)] : []
  end

  def funil_de_fora
    funil = @gatilho['funil_id']
    funil && !@conta.crm_pipelines.exists?(id: funil) ? [texto(:funil_de_fora, id: funil)] : []
  end

  def parado_sem_dias
    @tipo == 'card.parado' && @gatilho['dias'].to_i < 1 ? [texto(:parado_sem_dias)] : []
  end

  # O campo do card.data e do contato.data é um atributo personalizado de tipo data, do card ou do contato.
  def campo_de_fora
    campo = @gatilho['campo']
    return [] if campo.nil?

    modelo = Gatilhos.do_card?(@tipo) ? :card_attribute : :contact_attribute
    return [] if @conta.custom_attribute_definitions.exists?(attribute_key: campo, attribute_model: modelo, attribute_display_type: :date)

    [texto(:campo_de_fora, campo: campo)]
  end

  def da_mudanca
    mudanca = @gatilho['mudanca']
    return [] if mudanca.nil?

    [*campo_do_card_de_fora(mudanca['chave']),
     *(texto(:mudanca_sem_numero) if mudanca_numerica?(mudanca) && !MudancaDoCard.numero?(mudanca['valor']))]
  end

  def campo_do_card_de_fora(chave)
    return [] if chave.nil? || @conta.custom_attribute_definitions.exists?(attribute_key: chave, attribute_model: :card_attribute)

    [texto(:campo_do_card_de_fora, campo: chave)]
  end

  # O valor de venda é número em qualquer condição com valor; o campo personalizado, só em maior que e passou de.
  def mudanca_numerica?(mudanca)
    mudanca.key?('valor') && (mudanca['campo'] == MudancaDoCard::VALOR || MudancaDoCard::NUMERICAS.include?(mudanca['condicao']))
  end

  def selecao
    escolha = ::Autonomia::Automacao::Tempo::Selecao.new(@conta, @gatilho)
    return [texto(:selecao_vazia)] if escolha.condicoes.empty?

    outras = @gatilho['selecao'].to_h.keys - escolha.condicoes.keys
    return [texto(:selecao_de_outro_alvo, condicoes: outras.join(', '))] if outras.any?

    da_selecao_de_fora(@gatilho['selecao'])
  end

  def da_selecao_de_fora(selecao)
    [*(texto(:funil_de_fora, id: selecao['funil_id']) if selecao['funil_id'] && !@conta.crm_pipelines.exists?(id: selecao['funil_id'])),
     *(texto(:etapa_de_fora, id: selecao['etapa_id']) if selecao['etapa_id'] && !@conta.crm_pipeline_stages.exists?(id: selecao['etapa_id'])),
     *(texto(:responsavel_de_fora) if selecao['responsavel_id'] && !@conta.account_users.exists?(user_id: selecao['responsavel_id'])),
     *etiquetas_de_fora(selecao), *atributo_de_fora(selecao['atributo']), *faixa_invertida(selecao['fechado_entre_dias'])]
  end

  # "Fechado entre 360 e 330 dias" não pega ninguém, nunca: a pessoa trocou as pontas.
  def faixa_invertida(faixa)
    faixa && faixa['de'].to_i > faixa['ate'].to_i ? [texto(:faixa_invertida, de: faixa['de'], ate: faixa['ate'])] : []
  end

  def etiquetas_de_fora(selecao)
    selecao.values_at('etiqueta', 'sem_etiqueta').compact.reject { |nome| @conta.labels.exists?(title: nome) }
           .map { |nome| texto(:etiqueta_de_fora, etiqueta: nome) }
  end

  # A chave do atributo é de um atributo personalizado do contato, desta conta. O valor nunca entra na frase.
  def atributo_de_fora(atributo)
    return [] if atributo.nil? || @conta.custom_attribute_definitions.exists?(attribute_key: atributo['chave'], attribute_model: :contact_attribute)

    [texto(:atributo_de_fora, campo: atributo['chave'])]
  end

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
