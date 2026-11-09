# O que a Receita confere no gatilho de card e no de tempo (#2499): a flag da F6 (o de card pede também o CRM; o de
# reunião, G12, também as reuniões da instalação, com frase própria) e que a
# etapa, o funil, a página de agendamento (G32) e o campo de data escolhidos são da conta. O esquema já conferiu os tipos e quais parâmetros cada
# gatilho traz; aqui fica o que só o banco responde.
#
# No recorrente (#2635, G7), a seleção: pelo menos uma condição (sem nenhuma, a automação pegaria a conta inteira por
# engano), só as condições do alvo (card ou contato) e funil, etapa, responsável, etiqueta e atributo da conta. O da
# conta não tem seleção (o esquema recusa) e roda sem conversa, card ou contato: só ficam o esperar, o disparar de
# campanha (G14), que escolhe o público pela etiqueta, e o buscar empresas da prospecção (G21, #2706), que cria os
# cards. Recusar ao salvar é o que impede o passo de quebrar sem alvo ao rodar. Na data única (G39, #2681), a data que
# já passou.
#
# No card atualizado (G27, #2661), a mudança: o campo personalizado é do card, desta conta, e a condição numérica
# (maior que, passou de) tem número para comparar.
class Autonomia::Automacao::ProblemasDoGatilho
  Gatilhos = ::Autonomia::Automacao::Gatilhos
  MudancaDoCard = ::Autonomia::Automacao::MudancaDoCard

  # `passos`: todos os passos da receita, inclusive os dos ramos (Receita#passos). `account_user`: quem salva, para o
  # valor de venda na mudança.
  def initialize(gatilho, conta, passos: [], account_user: nil)
    @gatilho = gatilho
    @tipo = gatilho['tipo']
    @conta = conta
    @passos = passos
    @account_user = account_user
  end

  # Frases para a pessoa corrigir; vazio = pode salvar.
  def problemas
    return [] unless Gatilhos.do_card?(@tipo) || Gatilhos.de_tempo?(@tipo)

    desligado = Gatilhos.desligado(@tipo, @conta)
    return [texto(desligado)] if desligado

    return [*data_passada, *passos_que_pedem_alvo] if Gatilhos.da_conta?(@tipo)
    return [*data_passada, *selecao] if Gatilhos.recorrente?(@tipo)

    [*etapa_de_fora, *funil_de_fora, *pagina_de_fora, *parado_sem_dias, *campo_de_fora, *da_mudanca]
  end

  private

  def passos_que_pedem_alvo
    @passos.reject { |passo| sem_alvo?(passo) }.map { |passo| texto(:passo_pede_alvo, passo: passo['id']) }
  end

  # O `faz` de cada passo que roda sem alvo; `nil` = o passo inteiro.
  SEM_ALVO = { 'esperar' => nil, 'campanha' => 'disparar', 'prospeccao' => 'buscar' }.freeze

  def sem_alvo?(passo)
    return false unless SEM_ALVO.key?(passo['tipo'])

    SEM_ALVO[passo['tipo']].nil? || SEM_ALVO[passo['tipo']] == passo['faz']
  end

  # A data única (G39, #2681) que já passou nunca roda: salvar assim é engano, não escolha.
  def data_passada
    return [] unless @gatilho['frequencia'] == 'uma_vez'

    fuso = ::Autonomia::Automacao::Tempo.fuso(@conta)
    dia = Date.iso8601(@gatilho['data'])
    instante = fuso.local(dia.year, dia.month, dia.day, @gatilho['hora'].to_i)
    instante > Time.current ? [] : [texto(:data_passada, data: I18n.l(dia))]
  end

  def etapa_de_fora
    etapa = @gatilho['etapa_id']
    etapa && !@conta.crm_pipeline_stages.exists?(id: etapa) ? [texto(:etapa_de_fora, id: etapa)] : []
  end

  def funil_de_fora
    funil = @gatilho['funil_id']
    funil && !@conta.crm_pipelines.exists?(id: funil) ? [texto(:funil_de_fora, id: funil)] : []
  end

  # G32: a página de agendamento do gatilho de reunião, das novas (as que o editor lista).
  def pagina_de_fora
    pagina = @gatilho['pagina_id']
    pagina && !@conta.crm_agent_booking_profiles.new_pages.exists?(id: pagina) ? [texto(:pagina_de_fora, id: pagina)] : []
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

    [*campo_do_card_de_fora(mudanca['chave']), *valor_de_venda_escondido(mudanca),
     *(texto(:mudanca_sem_numero) if mudanca_numerica?(mudanca) && !MudancaDoCard.numero?(mudanca['valor']))]
  end

  # "O valor passou de R$ 50 mil" lê o valor de venda, com a mesma permissão do `card.valor` (#2597): quem não vê os
  # valores não monta um gatilho que descobre o valor dos cards pelo disparo.
  def valor_de_venda_escondido(mudanca)
    return [] unless mudanca['campo'] == MudancaDoCard::VALOR
    return [] unless ::Autonomia::Automacao::Valores.problema_de_leitura('card.valor', conta: @conta, account_user: @account_user)

    [texto(:gatilho_valor_de_venda)]
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
