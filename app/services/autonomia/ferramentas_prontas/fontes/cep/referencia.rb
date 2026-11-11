# O CEP DE REFERÊNCIA DA CIDADE (#2858, regra "QI 70" do Rodrigo, 11/11/2026): "se a API pede o CEP só para saber a
# cidade, usar o CEP padrão da cidade". Para a fonte cujo dado é por cidade e que pede um CEP (a criminalidade da F7):
# a plataforma acha um CEP da cidade sozinha, e o agente não pergunta ao cliente.
#
# CONTRATO COM QUEM CHAMA (a F7): aqui não há contador, acesso nem flag. Quem chama já passou pela própria `Execucao` (ou
# equivalente) e é ele quem confere o acesso da conta e a flag e conta o uso no limite do dia (`Uso.reservar!`). Aqui
# valem só o teto global do ViaCEP (`TetoDoProvedor`, pela `conta`) e o cache da fonte CEP.
#
# INTERFACE ESTÁVEL (a F7 usa). O método que a F7 chama é `Autonomia::FerramentasProntas::Premium::Endereco.cep(cidade:,
# uf:, rua: nil, bairro: nil, numero: nil)`, que devolve `{'cep'=>…}`, `{'candidatos'=>[…], 'falta'=>…}` ou nil; ele
# só precisa delegar a:
#   Autonomia::FerramentasProntas::Fontes::Cep::Referencia.cep(cidade:, uf: nil, rua: nil, bairro: nil, numero: nil, conta: nil)
#   - sem rua: `{'cep' => cep_da_cidade(...)}`, ou nil;
#   - com rua: TODOS os CEPs da rua no ViaCEP (até 50, os da própria cidade pelo código IBGE), guardados 30 dias numa
#     chave própria. Não a consulta `por_endereco`: ela corta em `Cep::MAX_CEPS` com os especiais de prédio por último,
#     e o corte escondia o CEP do prédio (Rua Augusta, nº 1260: o 01304-971 ficava fora e a faixa 01304-001 ganhava;
#     revisor, lote 3). Na ordem do `Cep.em_ordem` (a rua mais parecida primeiro, o especial depois). Então:
#       1. o bairro, quando vem, filtra (todas as palavras, sem acento); se esvaziar a lista ("Jardim America" contra
#          "Jd America"), vale a lista sem ele;
#       2. o número, quando vem, escolhe pela faixa do `complemento` (`Cep::Faixa`): os que cobrem o número (entre eles,
#          na mesma rua e no mesmo bairro, o do prédio cujo complemento é o próprio número); senão os sem faixa (a rua
#          inteira); se nada no bairro dito cobre o número, a rua inteira de novo, pelo número;
#       3. sem número, com todos da mesma rua e do mesmo bairro: o CEP de faixa vale mais que o especial de prédio
#          (sufixo 900+, `Cep.especial?`), se sobrar um só. Com número e todos da mesma rua e do mesmo bairro (faixas
#          que se sobrepõem): o primeiro, porque todos cobrem o número.
#     Um só -> `{'cep' => '01311-000'}`; vários -> `{'candidatos' => [{ 'nome', 'cep', 'logradouro', 'complemento',
#     'bairro' }] (até `Cep::MAX_CEPS`), 'falta' => 'bairro' | 'numero'}`. Com o número dito, sempre o bairro: pedir o
#     número de novo era laço (revisor, lote 3). Sem o número: o bairro só quando ele não veio e os CEPs estão em bairros
#     diferentes; senão o número (C15c/C15d do testador: com o bairro já dito, pedir o bairro de novo era laço). Nenhum,
#     cidade que não existe, homônima sem UF ou UF errada, fonte fora -> nil.
# E o CEP de referência sozinho:
#   Autonomia::FerramentasProntas::Fontes::Cep::Referencia.cep_da_cidade(cidade: 'Uberlândia', uf: nil, conta: 42)
#   -> "38400-263" (String, com traço), ou nil.
#   - `cidade`: o nome, como o cliente disse; `uf`: opcional (a cidade única no Brasil basta; a homônima sem UF dá nil);
#   - `conta`: o id da conta, para a fatia dela no teto global do ViaCEP;
#   - nil quando a cidade não existe, é homônima sem UF, ou o ViaCEP não respondeu: quem chama decide (perguntar a cidade,
#     ou dizer que não conseguiu).
# Não levanta por fonte fora nem por cache fora do ar (erro de conexão do Redis, logado com a classe).
#
# COMO (escolhido com evidência, 11/11/2026): não há API pública e gratuita de "CEP da cidade". O DNE dos Correios é pago,
# o IBGE não tem CEP, e a BrasilAPI só vai do CEP para o endereço. O ViaCEP busca pela rua (`/ws/UF/cidade/rua/json/`):
#   - cidade com CEP por rua: a busca pela palavra "Rua" devolve até 50 ruas da cidade (Uberlândia: 50, a primeira
#     38400-263); vale o MENOR CEP comum (o especial de prédio ou órgão, sufixo 900 a 999, só se não houver outro) entre
#     os que a consulta `por_endereco` guarda, conferidos pelo código IBGE, para a escolha ser estável;
#   - cidade de CEP único (as pequenas): a mesma busca devolve o registro da localidade sem rua, com o CEP geral (Serra
#     da Saudade/MG: 35617-000), que é o "CEP padrão" da cidade.
# Uma chamada por cidade, guardada por 30 dias (o CEP de uma cidade não muda).
module Autonomia::FerramentasProntas::Fontes::Cep::Referencia
  RUA = 'Rua'.freeze
  PRAZO = 4
  VALIDADE = 30.days
  CHAVE = 'autonomia:prontas:v1:cep_referencia'.freeze
  ERROS_DO_CACHE = Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS

  module_function

  def cep_da_cidade(cidade:, uf: nil, conta: nil) # rubocop:disable Naming/MethodParameterName
    municipio = Autonomia::FerramentasProntas::Municipios.buscar(uf, cidade)
    return if municipio.nil?

    guardado = ler(municipio)
    return guardado if guardado

    da_fonte(municipio, conta).tap { |cep| gravar(municipio, cep) if cep }
  end

  def cep(cidade:, uf: nil, rua: nil, bairro: nil, numero: nil, conta: nil) # rubocop:disable Naming/MethodParameterName,Metrics/ParameterLists
    return cep_da_cidade(cidade: cidade, uf: uf, conta: conta)&.then { |achado| { 'cep' => achado } } if rua.blank?

    ceps = escolher(todos_da_rua(cidade, uf, rua, conta), bairro, numero)
    return if ceps.empty?

    escolhido = unico(ceps, numero)
    return { 'cep' => escolhido['cep'] } if escolhido

    candidatos = ceps.first(Autonomia::FerramentasProntas::Fontes::Cep::MAX_CEPS)
    { 'candidatos' => candidatos.map { |item| Autonomia::FerramentasProntas::Fontes::Cep.com_nome(item) }, 'falta' => falta(ceps, bairro, numero) }
  end

  # Pelo bairro e pelo número; nada no bairro dito cobre o número: a rua inteira, pelo número; nem assim: a rua inteira.
  def escolher(todos, bairro, numero)
    no_bairro = do_bairro(todos, bairro)
    return no_bairro if numero.blank?

    do_numero(no_bairro, numero) || do_numero(todos, numero) || todos
  end

  # Os CEPs que podem ter o número: os cuja faixa o cobre (`certos`) e os sem faixa (`possiveis`: a rua inteira, ou texto
  # que não é faixa). Os certos sozinhos só quando os possíveis são da mesma rua e do mesmo bairro (o prédio "189" contra
  # a Rua Sete de Setembro inteira, na Vila Industrial); com um possível noutro bairro (outra Rua Augusta da cidade), os
  # dois ficam, e o bairro decide. Nenhum dos dois: nil.
  def do_numero(ceps, numero)
    return ceps if ceps.size < 2

    cobertura = ceps.group_by { |item| Autonomia::FerramentasProntas::Fontes::Cep::Faixa.cobre?(item['complemento'], numero) }
    pelo_numero(do_predio(cobertura.fetch(true, []), numero), cobertura.fetch(nil, [])).presence
  end

  def pelo_numero(certos, possiveis)
    return certos if certos.any? && (possiveis.empty? || mesma_rua_e_bairro?(certos + possiveis))

    certos + possiveis
  end

  # Vários cobrem o número na mesma rua e no mesmo bairro (a faixa "de 700 a 1680 - lado par" e o prédio "1260"): o do
  # prédio, se houver um só.
  def do_predio(certos, numero)
    return certos if certos.size < 2 || !mesma_rua_e_bairro?(certos)

    predio = certos.select { |item| Autonomia::FerramentasProntas::Fontes::Cep::Faixa.exato?(item['complemento'], numero) }
    predio.one? ? predio : certos
  end

  # Um só; ou, todos da mesma rua e do mesmo bairro: com o número, o primeiro (todos o cobrem); sem ele, o único CEP de
  # faixa entre os especiais de prédio.
  def unico(ceps, numero)
    return ceps.first if ceps.one?
    return unless mesma_rua_e_bairro?(ceps)
    return ceps.first if numero.present?

    da_rua = ceps.reject { |item| Autonomia::FerramentasProntas::Fontes::Cep.especial?(item['cep']) }
    da_rua.first if da_rua.one?
  end

  def mesma_rua_e_bairro?(ceps)
    ceps.map { |item| [comparavel(item['logradouro']), comparavel(item['bairro'])] }.uniq.one?
  end

  # Com o número dito, o bairro (nunca o número de novo). Sem ele: o bairro só quando o cliente não o disse e os CEPs
  # estão em bairros diferentes; no resto, o número.
  def falta(ceps, bairro, numero)
    return 'bairro' if numero.present?

    bairro.blank? && ceps.map { |item| comparavel(item['bairro']) }.uniq.size > 1 ? 'bairro' : 'numero'
  end

  def comparavel(texto)
    Autonomia::FerramentasProntas::Lista.comparavel(texto)
  end

  # O filtro do bairro que esvazia a lista não vale: o bairro do cliente pode estar escrito de outro jeito.
  def do_bairro(ceps, bairro)
    filtrados = Autonomia::FerramentasProntas::Lista.filtrar(ceps, bairro) { |item| item['bairro'].to_s }
    filtrados.presence || ceps
  end

  # Os CEPs da rua pela consulta `por_endereco` (cortada em `Cep::MAX_CEPS`): basta para o CEP de referência da
  # cidade, o menor dos que ela mostra. -> lista (vazia quando a cidade não serve, a rua não tem CEP ou a fonte não
  # respondeu).
  def da_rua(cidade, uf, rua, conta) # rubocop:disable Naming/MethodParameterName
    fonte = Autonomia::FerramentasProntas::Fontes::Cep::FONTE
    params, falta = fonte.consulta('por_endereco').conferir('logradouro' => rua, 'cidade' => cidade, 'uf' => uf)
    return [] if falta

    Array(Autonomia::FerramentasProntas::Apoio.new(fonte, cliente(conta)).dados('por_endereco', params)&.dig('ceps'))
  rescue Autonomia::FerramentasProntas::Apoio::SemResposta => e
    Rails.logger.warn("[autonomia][pronta] cep da rua sem resposta motivos=#{e.motivos.join(',')}")
    []
  end

  # TODOS os CEPs da rua, sem o corte da `por_endereco`, em ordem. -> lista (vazia quando a cidade não serve, a rua não
  # tem CEP ou o ViaCEP não respondeu).
  def todos_da_rua(cidade, uf, rua, conta) # rubocop:disable Naming/MethodParameterName
    municipio = Autonomia::FerramentasProntas::Municipios.buscar(uf, cidade)
    logradouro = Autonomia::FerramentasProntas::Fontes::Cep.logradouro(rua)
    return [] if municipio.nil? || logradouro.nil?

    chave = "#{CHAVE}:rua:#{municipio.codigo}:#{Digest::SHA256.hexdigest(comparavel(logradouro))}"
    guardados = ler_chave(chave)
    return guardados if guardados

    do_via_cep(municipio, logradouro, conta)&.tap { |ceps| gravar_chave(chave, ceps) } || []
  end

  def do_via_cep(municipio, logradouro, conta)
    via_cep = Autonomia::FerramentasProntas::Fontes::Cep::ViaCep.new(cliente(conta), prazo: PRAZO)
    Autonomia::FerramentasProntas::Fontes::Cep.em_ordem(via_cep.ceps_da_rua(municipio, logradouro), logradouro)
  rescue Autonomia::FerramentasProntas::Provedor::Falha => e
    Rails.logger.warn("[autonomia][pronta] cep da rua sem resposta motivos=viacep.#{e.motivo}")
    nil
  end

  def cliente(conta)
    Autonomia::FerramentasProntas::ClienteHttp.new(
      hosts: [Autonomia::FerramentasProntas::Fontes::Cep::ViaCep.host],
      prazo_final: Autonomia::FerramentasProntas::ClienteHttp.agora + PRAZO, conta: conta
    )
  end

  def da_fonte(municipio, conta)
    ceps = da_rua(municipio.nome, municipio.uf, RUA, conta).pluck('cep')
    comuns = ceps.reject { |cep| Autonomia::FerramentasProntas::Fontes::Cep.especial?(cep) }
    (comuns.presence || ceps).min
  end

  def ler(municipio)
    ler_chave("#{CHAVE}:#{municipio.codigo}")
  end

  def gravar(municipio, cep)
    gravar_chave("#{CHAVE}:#{municipio.codigo}", cep)
  end

  def ler_chave(chave)
    Rails.cache.read(chave)
  rescue *ERROS_DO_CACHE => e
    Rails.logger.warn("[autonomia][pronta] cache do cep de referencia falhou na leitura #{e.class}")
    nil
  end

  def gravar_chave(chave, valor)
    Rails.cache.write(chave, valor, expires_in: VALIDADE)
  rescue *ERROS_DO_CACHE => e
    Rails.logger.warn("[autonomia][pronta] cache do cep de referencia falhou na escrita #{e.class}")
  end
end
