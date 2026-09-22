# O RESUMO, EM PORTUGUÊS, DA ENTRADA COM QUE UMA COTAÇÃO FOI PEDIDA (#515).
#
# POR QUE EXISTE. Em 19/09/2026 o cliente perguntou "o bônus da apólice foi considerado?". A cotação
# tinha saído com a classe de bônus 9 lida da apólice dele, e a Lia escalou: a
# `ver_resultado_da_cotacao` devolvia preços e desfechos, e nada sobre a ENTRADA. No mesmo dia, a
# mesma coisa com cobertura e assistência.
#
# O QUE ENTRA, e só isto: o punhado de campos que o CLIENTE pergunta. O formulário do especialista
# tem ~90 campos, e despejá-los faria a Lia recitar cadastro em vez de responder.
#
# O QUE NÃO ENTRA: valor em reais. Quem escreve preço ao cliente é a Lia, a partir dos preços da
# cotação, e a fala dela é conferida contra o texto da ferramenta (`Agents::ConferenciaDePrecos`) —
# um valor em reais aqui entraria na lista do que ela pode escrever como se fosse preço. Nome de
# campo do formulário também não: em 08/09/2026 um cliente leu `insured.document` no WhatsApp.
#
# NADA É INVENTADO. Campo que a entrada não tem entra como ausente, com todos os outros, e o texto
# diz ao modelo o que fazer com ele. Código de lista (franquia 2, seguradora anterior 657) nunca sai
# cru: o nome vem do MESMO schema do adapter que montou o formulário, como `VehicleLookup` já faz
# com o tipo do veículo. Sem o nome, a linha diz que uma opção foi enviada e manda não descrevê-la.
#
# A ENTRADA É A DO ENVIO, montada aqui pelo `QuoteInput` — a mesma classe que montou a que foi ao
# portal. É o que faz o CEP escrito no parâmetro solto (`cep`) aparecer no endereço, como apareceu lá.
class Autonomia::Insurance::EntradaDaCotacao
  AUTO = 'auto'.freeze

  ABERTURA = 'Com que dados esta cotação foi pedida. Use para responder o que o cliente perguntar ' \
             'sobre isso, com as suas palavras; não recite a lista inteira a ele. Sem travessão.'.freeze
  AUSENCIA = 'Onde está "sem informação nesta cotação", o dado não foi enviado: diga que ele não ' \
             'foi informado, e nunca afirme que foi considerado.'.freeze
  SEM_INFORMACAO = 'sem informação nesta cotação.'.freeze
  SEM_NOME = 'uma opção foi enviada nesta cotação, e o nome dela não está aqui; não diga qual.'.freeze
  RENOVACAO = 'Tipo de seguro: renovação de apólice anterior.'.freeze
  SEGURO_NOVO = 'Tipo de seguro: seguro novo, sem marcar renovação.'.freeze

  # O CAMINHO NA ENTRADA, O RÓTULO QUE O CLIENTE RECONHECE E COMO O VALOR VIRA TEXTO. Os rótulos
  # seguem os de `InsuranceQuote::Recusas::ROTULOS`: sem artigo, no vocabulário de quem pergunta.
  # `:lista` é o campo cujo valor é um código, e o nome dele vem do schema.
  CAMPOS = [
    ['quotation.bonusClass', 'Classe de bônus', :numero],
    ['quotation.previousInsurerCode', 'Seguradora anterior', :lista],
    ['quotation.previousClaimsCount', 'Sinistros na vigência anterior', :numero],
    ['vehicle.overnightZipCode', 'CEP onde o veículo dorme', :numero],
    ['address.zipCode', 'CEP do endereço do segurado', :numero],
    ['vehicle.youngDriver', 'Condutor jovem', :sim_nao],
    ['coverage.deductibleType', 'Franquia', :lista],
    ['coverage.rentalCarType', 'Carro reserva', :lista],
    ['coverage.glassCoverage', 'Vidros', :lista],
    ['coverage.assistance24h', 'Assistência 24 horas', :lista]
  ].freeze

  # RESIDENCIAL (chat#323, 22/09/2026): o que o cliente pergunta sobre o imóvel cotado. Com os dados mínimos, quase
  # tudo aqui vale o padrão quando ele não disse, e a linha diz qual (`padrao` do schema), em vez de "sem
  # informação": o padrão foi enviado. FICAM DE FORA o valor a segurar e as coberturas, que são reais (ver acima), e
  # a construção, que o adapter deduz do tipo quando o cliente não disse, e cujo padrão do schema não é o enviado.
  CAMPOS_DE_RESIDENCIAL = [
    ['segurado.cep', 'CEP do imóvel', :numero],
    ['configuracoes.imovelNumero', 'Número do imóvel', :numero],
    ['configuracoes.imovelTipoResidencia', 'Tipo do imóvel', :lista],
    ['configuracoes.imovelObjetoSegurado', 'O que o seguro protege', :lista],
    ['configuracoes.imovelUso', 'Uso do imóvel', :lista],
    ['configuracoes.seguradoProprietario', 'Dono do imóvel', :sim_nao],
    ['configuracoes.zonaRural', 'Zona rural', :sim_nao],
    ['configuracoes.areaRisco', 'Área de risco', :sim_nao]
  ].freeze
  RESIDENCIAL = 'residencial'.freeze
  CAMPOS_POR_PRODUTO = { AUTO => CAMPOS, RESIDENCIAL => CAMPOS_DE_RESIDENCIAL }.freeze
  PADRAO = 'o padrão, porque o cliente não informou.'.freeze
  # O adapter monta o número do imóvel com o do segurado quando o do imóvel não vem (`enderecoDoImovel`); o resumo lê
  # do mesmo jeito, ou diria "padrão" para o número que o cliente deu (revisão da #605).
  ONDE_O_ADAPTER_TAMBEM_LE = { 'configuracoes.imovelNumero' => 'segurado.numero' }.freeze
  # Os grupos em que o formulário dos ramos põe o que o modelo escreveu, os mesmos que o adapter lê.
  GRUPOS_DOS_RAMOS = %w[segurado configuracoes].freeze

  # `argumentos` é o `ToolRun#arguments` da execução de `cotar_seguro`; `schema` é o que o adapter
  # entregou na sincronização da conexão (`Connection#quote_schema`), ou nil.
  def initialize(argumentos, schema: nil)
    @argumentos = argumentos.to_h.deep_stringify_keys
    @schema = schema.to_h
  end

  # -> o texto ao modelo, ou nil quando não há entrada para resumir (ramo sem lista de rótulos em
  # `CAMPOS_POR_PRODUTO`, ou execução sem argumentos).
  def texto
    return nil if entrada.nil?

    linhas = CAMPOS_POR_PRODUTO.fetch(produto).map { |caminho, rotulo, forma| linha(caminho, rotulo, forma) }
    [ABERTURA, (tipo_de_seguro if produto == AUTO), *linhas, AUSENCIA].compact.join("\n")
  end

  private

  def entrada
    return @entrada if defined?(@entrada)
    return @entrada = nil if @argumentos.blank?

    return @entrada = nil unless CAMPOS_POR_PRODUTO.key?(produto)

    # Nos ramos, o que o modelo mandou em `dados` (texto JSON) conta como no envio.
    input = ::Autonomia::Insurance::QuoteInput.new(produto: produto, params: @argumentos, dados: dados,
                                                   commission_percent: nil, grupos_do_ramo: GRUPOS_DOS_RAMOS)
    @entrada = input.to_h
  end

  # `produto` em branco é auto, como em `InsuranceQuote#produto`: sem isto, a cotação de auto que o
  # modelo pediu sem nomear o produto ficaria sem resumo (achado da revisão da PR #518).
  def produto
    @argumentos['produto'].to_s.strip.presence || ::Autonomia::Insurance::ResultadoDaCotacao.cotacao::AUTO
  end

  def dados
    return {} if produto == AUTO

    valor = @argumentos['dados']
    valor.is_a?(String) ? JSON.parse(valor) : valor.to_h
  rescue JSON::ParserError
    {}
  end

  # A AUSÊNCIA AQUI TEM SIGNIFICADO, e é o que o cliente pergunta primeiro: sem `isRenewal` o pedido
  # foi ao portal como seguro novo. Por isso esta linha nunca diz "sem informação".
  def tipo_de_seguro
    ::Autonomia::Insurance::AutoRenewal.new(entrada).renovacao? ? RENOVACAO : SEGURO_NOVO
  end

  def linha(caminho, rotulo, forma)
    valor = em(caminho)
    return "#{rotulo}: #{escrito(forma, caminho, valor)}" unless valor.nil? || valor == ''

    padrao = padrao_de(caminho)
    return "#{rotulo}: #{SEM_INFORMACAO}" if padrao.nil?

    "#{rotulo}: #{escrito(forma, caminho, padrao).delete_suffix('.')}, #{PADRAO}"
  end

  # O padrão do schema, só nos ramos: em auto a ausência tem o significado de sempre ("sem informação").
  def padrao_de(caminho)
    return nil if produto == AUTO

    Array(@schema['campos']).find { |c| c.to_h['campo'] == caminho }.to_h['padrao']
  end

  def escrito(forma, caminho, valor)
    case forma
    when :sim_nao then ActiveModel::Type::Boolean.new.cast(valor) ? 'sim.' : 'não.'
    when :lista then nome_da_opcao(caminho, valor) || SEM_NOME
    else "#{valor}."
    end
  end

  # O nome que o adapter deu ao código, ou nil — e aí o código não sai.
  def nome_da_opcao(caminho, valor)
    campo = Array(@schema['campos']).find { |c| c.to_h['campo'] == caminho }
    nome = campo.to_h['valores'].to_h[valor.to_s].presence
    nome && "#{nome}."
  end

  def em(caminho)
    grupo, campo = caminho.split('.')
    valor = entrada[grupo].to_h[campo]
    return valor unless valor.nil? || valor == ''

    alternativo = ONDE_O_ADAPTER_TAMBEM_LE[caminho]
    alternativo && em(alternativo)
  end
end
