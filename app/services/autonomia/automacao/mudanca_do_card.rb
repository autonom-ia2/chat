# O gatilho "card atualizado" (G27, #2661): qual campo do card mudou e como. A pessoa escolhe na `mudanca` do gatilho o
# campo (o valor de venda, ou um campo personalizado do card pela `chave`) e a condição:
#   mudou      — mudou, para qualquer valor;
#   igual      — passou a valer exatamente `valor` ("documentos completos" = true);
#   maior_que  — mudou e agora está acima de `valor`;
#   passou_de  — estava em `valor` ou abaixo e agora está acima ("o valor passou de R$ 50 mil"): uma vez só, na subida.
# No valor de venda, `valor` é em reais; o card guarda centavos.
#
# De onde vem o que mudou: o próprio card (Crm::CardAvisaAutomacao), o único caminho da Automação livre para "o card
# mudou", venha da tela, da API, do upsert, da IA, do lote ou de um passo. Cada gravação soma o par [antes, agora] do
# valor e de cada campo personalizado (`somar`, no after_save); no commit, o que de fato mudou (`do_commit`) vira um
# evento só. O card criado conta como tudo vindo do vazio: o que já nasce com R$ 80 mil "passou de R$ 50 mil". Número
# que não é número (texto num campo, condição sem valor) não casa: nada dispara por engano.
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

  # O "card atualizado" no valor de venda só dispara se quem ligou vê os valores (#2597): o disparo diria a quem não vê
  # que o card passou do limite. Os outros gatilhos e o campo personalizado passam.
  def quem_ligou_le?(definicao)
    gatilho = definicao.versao_ativa.receita['gatilho'].to_h
    return true unless gatilho.dig('mudanca', 'campo') == VALOR

    quem = AccountUser.find_by(account_id: definicao.account_id, user_id: definicao.ligada_por_id)
    ::Autonomia::Automacao::Valores.pode_ler?('card.valor', quem)
  end

  # No after_save do card: a soma das gravações da transação, com o `antes` da primeira e o `agora` da última, em
  # centavos no valor. Devolve uma soma nova; a anterior fica como estava.
  def somar(acumulado, saved_changes)
    pares_lidos(saved_changes).each_with_object(acumulado.to_h.dup) do |(chave, (antes, agora)), soma|
      soma[chave] = [soma.key?(chave) ? soma[chave].first : antes, agora]
    end
  end

  def pares_lidos(saved_changes)
    pares = {}
    pares[VALOR] = saved_changes['value_cents'] if saved_changes.key?('value_cents')
    return pares unless saved_changes.key?('custom_attributes')

    velho, novo = saved_changes['custom_attributes'].map(&:to_h)
    (velho.keys | novo.keys).each { |nome| pares["#{ATRIBUTO}:#{nome}"] = [velho[nome], novo[nome]] }
    pares
  end

  # No commit: só o que de fato mudou (gravar e voltar ao mesmo valor não é mudança). No card criado, só o que nasceu
  # preenchido: valor acima de zero e campo não vazio.
  def do_commit(soma, criado:)
    soma.to_h.reject do |chave, (antes, agora)|
      antes == agora || (criado && (chave == VALOR ? agora.to_i <= 0 : agora.to_s.empty?))
    end
  end

  # No job: o par do valor em reais, como a condição compara.
  def em_reais(mudancas)
    mudancas.to_h.to_h { |chave, (antes, agora)| [chave, chave == VALOR ? [reais(antes), reais(agora)] : [antes, agora]] }
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
