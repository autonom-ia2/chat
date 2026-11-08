# O que a Receita confere no gatilho de card e no de tempo (#2499): a flag da F6 (o de card pede também o CRM; o de
# reunião, G12, também as reuniões da instalação, com frase própria) e que a
# etapa, o funil e o campo de data escolhidos são da conta. O esquema já conferiu os tipos e quais parâmetros cada
# gatilho traz; aqui fica o que só o banco responde.
class Autonomia::Automacao::ProblemasDoGatilho
  Gatilhos = ::Autonomia::Automacao::Gatilhos

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

    [*etapa_de_fora, *funil_de_fora, *parado_sem_dias, *campo_de_fora]
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

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end
