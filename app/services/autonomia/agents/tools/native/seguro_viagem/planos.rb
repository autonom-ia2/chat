# OS PLANOS DE UMA COTAÇÃO do Seguro Viagem (#3211): transforma a resposta do `POST /v1/Cotacao` da Universal na
# lista que a cotação guarda, o PDF imprime e a proposta lê.
#
# LISTA BRANCA (R2): cada plano é montado campo a campo; o produto cru nunca é copiado. Comissão, markup, ranking,
# `quotationPorcentagem*` e `valorSemDesconto*` ficam na resposta e não chegam ao modelo, ao PDF nem ao banco.
#
# FILTRO: só entra plano com despesas médicas e hospitalares (`IDS_DMH`) e que aceita a idade de todos os viajantes.
# O filtro de despesas médicas só vale quando o catálogo da resposta conhece algum id de `IDS_DMH`: num destino com
# ids que ainda não conhecemos ele não zera a lista; deixa um aviso no log com os ids do catálogo para acharmos o novo.
#
# Os valores de cobertura (`principais`, `coberturas`) são o texto que a Universal escreve ("R$ 100.000"), sem prefixo
# nosso. O preço vai em texto decimal (`'360.0'`): quem formata em reais é `Dinheiro.brl`.
#
# PLANOS ANUAIS (#3223): a cotação de viagem única também traz os anuais multiviagem (`multiviagem: true`), e eles
# entram, como no fluxo antigo do n8n. Cada plano guarda `multiviagem` e os dias de cada viagem do ano
# (`dias_por_viagem`); quem separa os anuais é quem mostra (o PDF e a instrução).
module Autonomia::Agents::Tools::Native::SeguroViagem::Planos
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  # Despesas médicas e hospitalares, vistas na API: 2898 na viagem nacional, 2899 na internacional (#3223).
  IDS_DMH = [2898, 2899].freeze
  IDS_BAGAGEM = [2595].freeze
  IDS_CANCELAMENTO = [2601].freeze

  module_function

  # -> Array<Hash> com chaves em texto, `codigo` "P1", "P2"... na ordem da Universal depois do filtro.
  def de(resposta, idades:)
    para_idades(candidatos(resposta), idades)
  end

  # Os planos com despesas médicas, ainda sem o filtro de idade e sem código. Quem precisa saber se o vazio é da idade
  # (a cotação) monta uma vez e filtra com `para_idades`.
  def candidatos(resposta)
    catalogo = catalogo_de(resposta)
    produtos = com_despesas_medicas(Array(resposta['produtos']).grep(Hash), catalogo)
    produtos.map { |produto| plano(produto, catalogo, resposta['valorDoCambio']) }
  end

  # Os candidatos que aceitam a idade de todos os viajantes (`Faixas.dentro_do_limite?`), com o código "P1", "P2"...
  # na ordem depois do filtro.
  def para_idades(candidatos, idades)
    candidatos.select { |plano| idades.all? { |idade| SeguroViagem::Faixas.dentro_do_limite?(plano, idade) } }
              .each_with_index.map { |plano, indice| { 'codigo' => "P#{indice + 1}" }.merge(plano) }
  end

  # O que o modelo lê: o código, o nome, o preço em reais, as parcelas, as três coberturas principais e se o plano é
  # anual (com os dias de cada viagem).
  def resumo(planos)
    planos.map do |plano|
      { 'codigo' => plano['codigo'], 'nome' => plano['nome'],
        'preco_total' => plano['preco_total'].nil? ? nil : SeguroViagem::Dinheiro.brl(plano['preco_total']),
        'max_parcelas' => plano['max_parcelas'], 'principais' => plano['principais'], 'anual' => anual?(plano),
        'dias_por_viagem' => plano['dias_por_viagem'] }
    end
  end

  # Cotação guardada antes do #3223 não tem a chave: é de viagem única.
  def anual?(plano)
    plano['multiviagem'] == true
  end

  # { id_beneficio => benefício do catálogo da resposta }
  def catalogo_de(resposta)
    Array(resposta['beneficios']).grep(Hash).each_with_object({}) do |beneficio, catalogo|
      id = id_de(beneficio)
      catalogo[id] ||= beneficio unless id.nil?
    end
  end

  def com_despesas_medicas(produtos, catalogo)
    unless catalogo.keys.intersect?(IDS_DMH)
      Rails.logger.warn("[seguro_viagem] catálogo sem id conhecido de despesas médicas ids=#{catalogo.keys.join(',')}")
      return produtos
    end

    produtos.select { |produto| beneficios(produto).any? { |beneficio| IDS_DMH.include?(id_de(beneficio)) } }
  end

  def plano(produto, catalogo, cambio_da_resposta)
    tarifa = produto['tarifa'].is_a?(Hash) ? produto['tarifa'] : {}
    {
      'id_produto' => produto['idProduto'], 'id_produto_acordo' => produto['idProdutoAcordo'],
      'nome' => produto['descricao'].to_s.strip, 'descricao_adicional' => produto['descricaoAdicional'],
      'preco_total' => decimal(tarifa['valor']), 'valor_moeda' => decimal(tarifa['valorMoeda']),
      'moeda' => produto['simboloMoeda'], 'cambio' => cambio_da_resposta.nil? ? tarifa['cambio'] : cambio_da_resposta,
      'max_parcelas' => produto['maxParcelas'], 'idade_minima' => produto['idadeMinima'],
      'idade_maxima' => produto['idadeMaxima'], 'regra_cancelamento' => regra_cancelamento(produto),
      'faixas' => faixas(tarifa), 'coberturas' => coberturas(produto, catalogo), 'principais' => principais(produto),
      'multiviagem' => produto['multiviagem'] == true, 'dias_por_viagem' => dias_por_viagem(produto)
    }
  end

  # Os dias de cada viagem do plano anual, do campo que vier preenchido; viagem única, nil.
  def dias_por_viagem(produto)
    return nil unless produto['multiviagem'] == true

    dias = [produto['diasMultiviagem'], produto['quantidadeDiasMultiviagem']].map { |valor| Integer(valor, exception: false) }
    dias.find { |valor| valor.to_i.positive? }
  end

  # Lista branca também aqui (R2): só as quatro chaves da regra, nunca o que mais a Universal puser.
  def regra_cancelamento(produto)
    Array(produto['regraCancelamento']).grep(Hash).map { |regra| regra.slice('de', 'ate', 'geraCredito', 'multa') }
  end

  def faixas(tarifa)
    Array(tarifa['tarifaIdade']).grep(Hash).map do |faixa|
      { 'de' => faixa['de'], 'ate' => faixa['ate'], 'valor' => decimal(faixa['valor']),
        'valor_moeda' => decimal(faixa['valorMoeda']) }
    end
  end

  def coberturas(produto, catalogo)
    beneficios(produto).map do |beneficio|
      item = catalogo[id_de(beneficio)].to_h
      { 'id_beneficio' => id_de(beneficio), 'nome' => item['descricao'], 'descricao_completa' => item['descricaoCompleta'],
        'valor' => beneficio['valor'], 'moeda' => beneficio['tipoMoeda'] }
    end
  end

  def principais(produto)
    { 'despesas_medicas' => principal(produto, IDS_DMH), 'bagagem' => principal(produto, IDS_BAGAGEM),
      'cancelamento' => principal(produto, IDS_CANCELAMENTO) }
  end

  # O texto `valor` como a Universal entrega; em branco, a moeda e o valor em dinheiro; sem o benefício, nil.
  def principal(produto, ids)
    beneficio = beneficios(produto).find { |item| ids.include?(id_de(item)) }
    return nil if beneficio.nil?

    beneficio['valor'].to_s.strip.presence || "#{beneficio['tipoMoeda']} #{beneficio['valorEmDinheiro']}".strip.presence
  end

  def beneficios(produto)
    Array(produto['beneficios']).grep(Hash)
  end

  def id_de(beneficio)
    Integer(beneficio['idBeneficio'], exception: false)
  end

  # `360` -> `'360.0'`; nil fica nil.
  def decimal(valor)
    valor.nil? ? nil : BigDecimal(valor.to_s).to_s('F')
  end

  private_class_method :catalogo_de, :com_despesas_medicas, :plano, :dias_por_viagem, :regra_cancelamento, :faixas,
                       :coberturas, :principais, :principal, :beneficios, :id_de, :decimal
end
