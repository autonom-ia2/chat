# O VEÍCULO PELA PLACA OU PELO CHASSI (#2993), numa fonte parceira, com o cadastro da PLATAFORMA (um só, de todas as
# contas). O agente manda a placa (ou o chassi) e recebe a placa, o chassi, a marca, o modelo, os anos e as versões na
# tabela FIPE (até 5; as 2 primeiras com o valor do mês); o cliente deixa de ditar marca, modelo e ano. O que o agente
# faz com o dado (guardar para a equipe, na venda; responder a quem perguntou, na consulta) é da instrução dele.
#
# QUEM É A FONTE NÃO FICA NO CÓDIGO. Os endereços e o cadastro vêm de UMA variável de ambiente (`CADASTRO`, só o nome
# dela fica aqui), em JSON de uma linha:
#   { "passe": "<endereço do passe>", "entrada": "<endereço da entrada>", "placa": "<endereço da consulta pela placa,
#     terminado em />", "chassi": "<o mesmo, pelo chassi>", "corpo": { <os campos do cadastro que a entrada pede> } }
# Os quatro endereços são HTTPS. Faltando a variável, um endereço ou o corpo, a consulta nem é oferecida
# (`configurado?`).
#
# Três idas, nenhuma pelo IP próprio da conta (`ClienteHttp#pelo_servidor!`):
#   1. o passe: GET no endereço `passe`, que devolve o bilhete;
#   2. a entrada: POST do bilhete com o `corpo` do cadastro, que devolve o acesso. O acesso vale 1 hora na fonte e fica
#      50 minutos na memória do processo (`ACESSOS`); o 401 apaga o acesso recusado (não o que outra consulta já
#      renovou) e entra de novo, uma vez;
#   3. a consulta: pela placa, ou pelo chassi (que devolve a placa, e a placa devolve o resto, na mesma ida do agente).
# Os endereços vêm do ambiente: cada host passa pela conferência de rede interna do cliente (`permitir_host!`).
#
# A placa e o chassi vão os dois na resposta, venha o pedido por um ou pelo outro (decisão do Rodrigo, 13/11/2026: a
# cotação de seguro usa os dois).
# O VALOR: a fonte devolve um valor por versão, mas não é o da tabela do mês (conferido em 13/11/2026: 170.086 lá,
# 163.320 na FIPE de novembro, para o mesmo código e ano). Por isso o valor sai da consulta `preco` desta fonte, pelo
# código e pelo ano-modelo (`Apoio`, com o cache dela). A FIPE fora do ar não derruba a consulta: o veículo vai sem o
# valor, e a resposta em que faltou o valor de alguma das versões que o teriam não fica no cache.
# O TIPO sai do primeiro dígito do código FIPE, conferido na tabela pública em 13/11/2026 (0 carro, 5 caminhão, 8
# moto). Código com outro começo (há carro com 3) vai sem o tipo; o valor é procurado como carro.
# Erros da fonte: placa que ela não acha, 400; chassi que ela não acha, 450. Os dois viram "não encontrado".
# Cadastro, bilhete, acesso, placa e chassi nunca vão a log nem a erro.
class Autonomia::FerramentasProntas::Fontes::Fipe::PelaPlaca < Autonomia::FerramentasProntas::Provedor
  Fipe = Autonomia::FerramentasProntas::Fontes::Fipe
  ClienteHttp = Autonomia::FerramentasProntas::ClienteHttp

  NOME = 'veiculo_pela_placa'.freeze
  CADASTRO = 'PRONTAS_VEICULO_FONTE'.freeze
  ENDERECOS = %w[passe entrada placa chassi].freeze
  NAO_ACHOU = [400, 450].freeze
  ACESSO_VENCIDO = 401
  VALIDADE_DO_ACESSO = 50.minutes
  # Quantas versões vão ao agente; só as `Fipe::MAX_VERSOES` primeiras ganham o valor do mês (cada valor é uma consulta
  # à FIPE).
  MAX_VERSOES_NA_LISTA = 5
  TIPO_PELO_CODIGO = { '0' => 'carros', '5' => 'caminhoes', '8' => 'motos' }.freeze
  TIPO_DO_VALOR = 'carros'.freeze
  VARIAS_VERSOES = 'A placa aponta para mais de uma versão do modelo. Cada versão tem o seu valor: não trate um deles ' \
                   'como o valor do veículo.'.freeze

  ACESSOS = Autonomia::FerramentasProntas::Premium::Tokens.new

  class << self
    def configurado?
      cadastro.present?
    end

    # O host da consulta, para o teto e para o desligar sem deploy. Sem o cadastro, nenhum.
    def host
      cadastro&.dig('placa')&.host
    end

    # -> os quatro endereços (URI) e o corpo da entrada, ou nil quando falta algo ou a variável não é o JSON esperado.
    def cadastro
      dado = JSON.parse(chave_do_ambiente(CADASTRO).to_s)
      return unless dado.is_a?(Hash) && dado['corpo'].is_a?(Hash) && dado['corpo'].present?

      enderecos = ENDERECOS.index_with { |nome| endereco(dado[nome]) }
      enderecos.merge('corpo' => dado['corpo']) if enderecos.values.all?
    rescue JSON::ParserError
      nil
    end

    # Só HTTPS, com host. Fora disso, o provedor fica sem o cadastro.
    def endereco(valor)
      endereco = URI.parse(valor.to_s)
      endereco if endereco.is_a?(URI::HTTPS) && endereco.host.present?
    rescue URI::InvalidURIError
      nil
    end

    def esquecer_acesso!
      ACESSOS.write(nil)
    end

    # O veículo em que faltou o valor do mês de alguma das versões que o teriam (a FIPE não respondeu, ou o prazo
    # acabou no meio) não vai ao cache: a próxima consulta tenta de novo.
    def validade_da_resposta(dados)
      com_valor = dados['versoes'].first(Fipe::MAX_VERSOES)
      com_valor.any? && com_valor.all? { |versao| versao['valor'] } ? validade : 0
    end
  end

  def consultar(_consulta, params)
    @cadastro = self.class.cadastro
    raise Falha, 'nao_configurada' if @cadastro.nil?

    hosts = ENDERECOS.map { |nome| @cadastro[nome].host }.uniq
    hosts.each { |host| @cliente.permitir_host!(host) }
    @cliente.pelo_servidor!(*hosts)
    com_valor(veiculo(params['placa'] ? pela_placa(params['placa']) : pelo_chassi(params['chassi'])))
  end

  private

  def pela_placa(placa)
    objeto!(ler(@cadastro['placa'], placa))
  end

  # A lista do chassi traz o resumo e a placa. Com a placa, vem o veículo inteiro; sem ela (o carro que ainda não foi
  # emplacado), vale o resumo, com o chassi que foi pedido.
  def pelo_chassi(chassi)
    resumo = lista!(ler(@cadastro['chassi'], chassi)).find { |item| item.is_a?(Hash) }
    raise NaoEncontrado, 'nao_encontrado' if resumo.nil?

    placa = Fipe::PLACA.normalizar(resumo['plate'])
    placa ? pela_placa(placa) : resumo.merge('chassi' => chassi)
  end

  # `valor`: a placa ou o chassi já normalizados (só letras e dígitos), colados no fim do endereço da consulta.
  def ler(endereco, valor)
    @cliente.get_json(endereco.host, "#{endereco.request_uri}#{valor}", prazo: @prazo, cabecalhos: { 'Authorization' => "Bearer #{acesso}" })
  rescue Falha => e
    raise NaoEncontrado, 'nao_encontrado' if NAO_ACHOU.include?(e.status)
    raise unless e.status == ACESSO_VENCIDO && !@entrou_de_novo

    @entrou_de_novo = true
    ACESSOS.forget(@usado)
    retry
  end

  # -> o acesso guardado, enquanto vale; senão, entra de novo e guarda. `@usado`: o que esta consulta usou, para o 401
  # apagar só ele.
  def acesso
    @usado = ACESSOS.read
    return @usado.first if @usado && ClienteHttp.agora < @usado.last

    @usado = [entrar, ClienteHttp.agora + VALIDADE_DO_ACESSO].freeze
    ACESSOS.write(@usado)
    @usado.first
  end

  # A falha da entrada sai sem o status e com o motivo próprio (`veiculo_pela_placa.entrada.pedido_recusado`): o cadastro recusado
  # (400) nunca é lido como "não achei o veículo", e quem olha o contador vê que foi a entrada.
  def entrar
    passe = @cadastro['passe']
    entrada = @cadastro['entrada']
    bilhete = exigir!(texto(objeto!(@cliente.get_json(passe.host, passe.request_uri, prazo: @prazo))['token']))
    corpo = @cadastro['corpo'].merge('token' => bilhete)
    exigir!(texto(objeto!(@cliente.post_json(entrada.host, entrada.request_uri, corpo, prazo: @prazo))['token']))
  rescue Falha, NaoEncontrado => e
    raise Falha, "entrada.#{e.message}"
  end

  # O que a equipe precisa do veículo para cotar.
  def veiculo(dado)
    marca = texto(dado['brand'])
    versoes = versoes_de(dado, marca)
    { 'placa' => Fipe::PLACA.normalizar(dado['plate']), 'chassi' => Fipe.chassi(dado['chassi']),
      'marca' => marca, 'modelo' => exigir!(sem_a_marca(dado['model'], marca)),
      'tipo' => TIPO_PELO_CODIGO[versoes.first&.dig('codigo_fipe').to_s[0]],
      'ano_fabricacao' => ano(dado['manufacturing_year']), 'ano_modelo' => ano(dado['model_year'] || dado['year']),
      'versoes' => versoes, 'observacao' => (VARIAS_VERSOES if versoes.size > 1) }.compact
  end

  # Pela placa, `fipes_info` (uma versão ou mais); pelo chassi sem placa, só o código em `fipe`.
  def versoes_de(dado, marca)
    itens = Array(dado['fipes_info']).select { |item| item.is_a?(Hash) }
    itens = [{ 'fipe_code' => dado['fipe'] }] if itens.empty?
    itens.first(MAX_VERSOES_NA_LISTA).filter_map do |item|
      codigo = Fipe::CODIGO_FIPE.normalizar(item['fipe_code'])
      { 'codigo_fipe' => codigo, 'descricao' => sem_a_marca(item['description'], marca) }.compact if codigo
    end
  end

  # "Toyota - YARIS Cross XRX" -> "YARIS Cross XRX": a fonte repete a marca na frente do modelo.
  def sem_a_marca(nome, marca)
    texto(texto(nome).to_s.delete_prefix("#{marca} - "))
  end

  def ano(valor)
    Autonomia::FerramentasProntas::Parametro.inteiro(valor, 1000..2100)
  end

  def com_valor(veiculo)
    versoes = veiculo['versoes'].each_with_index.map do |versao, indice|
      indice < Fipe::MAX_VERSOES ? versao.merge(valor_do_mes(versao['codigo_fipe'], veiculo['ano_modelo'])) : versao
    end
    com_preco = versoes.any? { |versao| versao['valor'] }
    veiculo.merge('versoes' => versoes).merge(com_preco ? { 'unidades' => Fipe::UNIDADES } : {})
  end

  # O valor do mês na tabela FIPE, pela consulta `preco` desta fonte (do cache dela, ou da BrasilAPI com a parallelum de
  # reserva). Sem o ano-modelo, ou com a FIPE fora, a versão vai sem o valor.
  def valor_do_mes(codigo, ano_modelo)
    return {} if ano_modelo.nil?

    pedido = { 'tipo' => TIPO_PELO_CODIGO.fetch(codigo[0], TIPO_DO_VALOR), 'codigo_fipe' => codigo, 'ano' => ano_modelo }
    preco = Array(Autonomia::FerramentasProntas::Apoio.new(Fipe::FONTE, @cliente).dados('preco', pedido)&.dig('precos')).first
    preco ? preco.slice('valor', 'combustivel', 'mes_de_referencia') : {}
  rescue Autonomia::FerramentasProntas::Apoio::SemResposta
    {}
  end
end
