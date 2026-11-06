# O gatilho "card atualizado" (G27, #2661): qual campo do card mudou e como. A pessoa escolhe na `mudanca` do gatilho o
# campo (o valor de venda, ou um campo personalizado do card pela `chave`) e a condição:
#   mudou      — mudou, para qualquer valor;
#   igual      — passou a valer exatamente `valor` ("documentos completos" = true);
#   maior_que  — mudou e agora está acima de `valor`;
#   passou_de  — estava em `valor` ou abaixo e agora está acima ("o valor passou de R$ 50 mil"): uma vez só, na subida.
# No valor de venda, `valor` é em reais; o card guarda centavos.
#
# De onde vem o que mudou: a atividade do card. A edição ('update') traz o novo e, no `antes`, o anterior só dos campos
# que mudaram (Crm::Cards::Antes); o card criado ('create') conta como tudo vindo do vazio: o card que já nasce com
# R$ 80 mil "passou de R$ 50 mil". Número que não é número (texto num campo, condição sem valor) não casa: nada dispara
# por engano.
module Autonomia::Automacao::MudancaDoCard
  CONDICOES = %w[mudou igual maior_que passou_de].freeze
  NUMERICAS = %w[maior_que passou_de].freeze
  VALOR = 'valor'.freeze
  ATRIBUTO = 'atributo'.freeze
  CENTAVOS = 100

  module_function

  # mudanca: a `mudanca` do gatilho. mudancas: { 'valor' => [antes, agora], 'atributo:<chave>' => [antes, agora] }.
  def casa?(mudanca, mudancas)
    par = mudancas.to_h[chave(mudanca)]
    return false if par.nil?

    antes, agora = par
    alvo = mudanca['valor']
    case mudanca['condicao']
    when 'mudou' then true
    when 'igual' then igual?(agora, alvo, numerico: mudanca['campo'] == VALOR)
    when 'maior_que' then maior?(agora, alvo)
    when 'passou_de' then maior?(agora, alvo) && !maior?(antes, alvo, vazio_conta_como_zero: true)
    else false
    end
  end

  # O que a atividade diz que mudou. criado: o card acabou de nascer (o payload não traz os campos; vêm do card, como
  # estavam na criação).
  def da_atividade(payload, card, criado:, atividade_id: nil)
    return do_card_novo(card, atividade_id) if criado

    antes = payload['antes'].to_h
    mudancas = {}
    mudancas[VALOR] = [reais(antes['value_cents']), reais(payload['value_cents'])] if antes.key?('value_cents')
    novos = payload['custom_attributes'].to_h
    antes['custom_attributes'].to_h.each { |nome, velho| mudancas["#{ATRIBUTO}:#{nome}"] = [velho, novos[nome]] }
    mudancas
  end

  def do_card_novo(card, atividade_id)
    valor, campos = como_nasceu(card, atividade_id)
    mudancas = {}
    mudancas[VALOR] = [nil, reais(valor)] if valor.to_i.positive?
    campos.each { |nome, atual| mudancas["#{ATRIBUTO}:#{nome}"] = [nil, atual] unless atual.to_s.empty? }
    mudancas
  end

  # O card como nasceu: o de agora, desfeitas as edições depois da criação (o `antes` de cada uma, da mais nova para a
  # mais velha). Sem isso, o card criado com R$ 10 mil e editado para R$ 80 mil antes do job dispararia "passou de" na
  # criação e de novo na edição.
  def como_nasceu(card, atividade_id)
    valor = card.value_cents
    campos = card.custom_attributes.to_h.dup
    depois = ::Crm::Activity.where(card_id: card.id, event_type: 'update')
    depois = depois.where('id > ?', atividade_id) if atividade_id
    depois.order(id: :desc).pluck(:payload).each do |payload|
      antes = payload.to_h['antes'].to_h
      valor = antes['value_cents'] if antes.key?('value_cents')
      campos.merge!(antes['custom_attributes'].to_h)
    end
    [valor, campos]
  end

  def chave(mudanca)
    mudanca['campo'] == VALOR ? VALOR : "#{ATRIBUTO}:#{mudanca['chave']}"
  end

  # Para a Receita: o `valor` que a condição numérica pede é número?
  def numero?(valor) = !numero(valor).nil?

  # No valor de venda, "igual a 5000" compara número (o card guarda 500000 centavos); no campo, o texto.
  def igual?(agora, alvo, numerico:)
    return texto(agora) == texto(alvo) unless numerico

    atual = numero(agora)
    !atual.nil? && atual == numero(alvo)
  end

  def maior?(valor, limite, vazio_conta_como_zero: false)
    limite = numero(limite)
    atual = valor.nil? && vazio_conta_como_zero ? 0 : numero(valor)
    !limite.nil? && !atual.nil? && atual > limite
  end

  # O número como o banco guarda ou como a pessoa digita com ponto decimal ("50000", "50000.5"). "50.000,50" não vira
  # número: é ambíguo, e a Receita recusa antes de salvar.
  def numero(valor)
    lido = valor.is_a?(Numeric) ? valor : BigDecimal(valor.to_s.strip)
    lido if lido.finite?
  rescue ArgumentError, TypeError
    nil
  end

  # Centavos que não são número (pedido malformado) ficam vazios: não derrubam as outras automações do evento.
  def reais(centavos)
    lido = numero(centavos)
    lido.nil? ? nil : lido / CENTAVOS
  end

  def texto(valor) = valor.to_s.strip
end
