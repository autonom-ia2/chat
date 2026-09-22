# O VEÍCULO ANTES DA CONFERÊNCIA — entrega 2 do Agente de Cotação, termos 5 e 10.
#
# Separado da ferramenta pelo mesmo motivo de `Declaracao`, `Recusas` e `Envio`: é outro assunto
# (o que identifica o veículo e o que a consulta de placa acrescenta), e a classe já passava do
# teto de linhas ao ganhá-lo.
module Autonomia::Agents::Tools::Native::InsuranceQuote::Veiculo
  extend ActiveSupport::Concern

  PLACA = 'vehicle.plate'.freeze
  ZERO_KM = 'vehicle.isZeroKm'.freeze
  # O motivo que o modelo lê para o campo que a busca do segurado não achou (`segurado_nao_achado`). Sem valor nenhum.
  NAO_ACHADO = 'não foi achado pelo documento informado; pergunte ao cliente.'.freeze
  DIGITOS_DE_CNPJ = 14
  IDENTIFICADORES_DO_VEICULO = %w[plate chassis fipeCode].freeze

  private

  # A entrada COM O QUE O PORTAL SABE DO VEÍCULO (entrega 2, termo 5): havendo placa, a consulta —
  # gratuita — diz se é carro, moto ou caminhão e o ano do modelo, e É ELA QUE VALE. O tipo liga as
  # regras de moto e caminhão na conferência; o que o modelo escreveu é palpite sobre o mesmo
  # veículo que o portal conhece pela placa. A regra vale POR CONSTRUÇÃO — sempre que há placa —,
  # não por obediência do modelo: "aceita qualquer tipo presente" não era garantia nenhuma (Codex,
  # 10/09/2026). Falha ou ausência da consulta não barra: a entrada segue com o que o modelo
  # escreveu, e o que sobra é a conferência tardia do próprio envio, que consulta de novo.
  def entrada
    @entrada ||= com_veiculo(quote_input.to_h)
  end

  # Auto sem placa, chassi nem FIPE: não há veículo para cotar (termo 10).
  def sem_veiculo?
    return false unless quote_input.auto?

    veiculo = quote_input.to_h['vehicle'].to_h
    IDENTIFICADORES_DO_VEICULO.none? { |campo| veiculo[campo].present? }
  end

  # AUTO SEM FORMULÁRIO NÃO É FALTA DE DADO DO CLIENTE. Os parâmetros de auto nascem do schema que
  # a conexão guarda (`Declaracao.params_for`); sem ele, o modelo recebeu a ferramenta sem o bloco
  # `vehicle` e não tinha onde escrever a placa. Recusar por `sem_veiculo` aqui mandaria pedir ao
  # cliente o que a ferramenta é que não pôde receber. `schema_da_conexao` tenta buscar de novo
  # antes de desistir: só é indisponível o que segue indisponível.
  # -> a conexão com o portal está fora e não volta sozinha? Aí toda cotação morre no envio (chat#585). Os estados
  # de passagem (o healthcheck sondando o portal, a sincronização) duram segundos e não recusam: o envio tenta de
  # novo (revisão da chat#587).
  CONEXAO_FORA_DO_AR = %w[not_configured auth_required human_required offline].freeze
  def conexao_fora?
    ::Autonomia::Insurance::Connection.for_account(account).all? { |conexao| CONEXAO_FORA_DO_AR.include?(conexao.status) }
  end

  def sem_formulario?
    quote_input.auto? && self.class.schema_da_conexao(connection).blank?
  end

  # ZERO-QUILÔMETRO AMBÍGUO É DADO FALTANDO (entrega 3, Codex): o manual manda cotar direto com o
  # mínimo em mãos, e a consulta de placa diz o ano do modelo — mas não diz se o carro é zero. Ano do
  # modelo anterior ao atual é usado, e ninguém pergunta. Ano atual ou seguinte sem `isZeroKm`
  # escrito é ambíguo: cotado assim sai como usado (o schema do adapter documenta), com preço errado
  # de cara certa. Entra na conferência como um problema a mais, no formato do adapter
  # (`campo`/`severidade`/`motivo`): o código compara o ano com o calendário; quem pergunta é o modelo.
  # -> lista de problemas, vazia quando não há.
  # A BUSCA DO SEGURADO ANTES DA PROMESSA (chat#585). Nome, nascimento e sexo (a razão social, em empresa) são
  # buscados pelo documento só no envio, depois de o especialista dizer que cotou; quando a busca não acha a pessoa,
  # a cotação voltava pedindo o que tinha sido dado por resolvido (versão 7 da prova de 21/09/2026). A conferência
  # faz a mesma busca (`quote/enrich`) e o que ela não achou vira pergunta, antes.
  #
  # SÓ `not_found` É USADO (LGPD, revisão da adapters#75; o adapter escreve `notFound`, e o `Connector::Http`
  # normaliza para snake_case): o que a busca achou nunca volta ao modelo — quem digitasse
  # o CPF de outra pessoa ouviria o nome e o nascimento dela. O envio busca de novo, no adapter, e esse é o custo de
  # uma consulta a mais quando o modelo não trouxe os três. Conferência, não portão: falha aqui é nada a perguntar.
  # -> problemas no formato da validação, um por campo não achado.
  def segurado_nao_achado
    return [] unless busca_do_segurado?

    resposta = connector.quote_enrich(provider: connection.provider, product: produto, input: entrada)
    do_segurado = Array(resposta.to_h['not_found']).map(&:to_s).select { |campo| campo.start_with?('insured.') }
    do_segurado.map { |campo| { 'campo' => campo, 'severidade' => 'erro', 'motivo' => NAO_ACHADO } }
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] busca do segurado indisponivel account=#{account.id} #{e.class}")
    []
  end

  # Consulta paga só quando falta algo que ela resolve: com documento, e sem os campos que ela busca.
  def busca_do_segurado?
    return false unless quote_input.auto?

    segurado = entrada['insured'].to_h
    documento = segurado['document'].to_s.delete('^0-9')
    return false if documento.empty?

    campos = documento.length == DIGITOS_DE_CNPJ ? %w[name] : %w[name birthDate gender]
    campos.any? { |campo| segurado[campo].blank? }
  end

  def problemas_locais
    [problema_de_zero_km].compact
  end

  def problema_de_zero_km
    return unless quote_input.auto?

    veiculo = entrada['vehicle'].to_h
    return unless veiculo['isZeroKm'].nil? && veiculo['modelYear'].to_i >= Date.current.year

    { 'campo' => ZERO_KM, 'severidade' => 'erro',
      'motivo' => "o ano do modelo (#{veiculo['modelYear']}) é o atual ou o seguinte e ninguém disse se o veículo " \
                  "(#{@modelo_lido || 'modelo não informado pelo portal'}) é zero-quilômetro; cotado assim sai como " \
                  'usado, com preço errado. Pergunte ao cliente, pelo nome do carro, se é zero ou se já está rodando ' \
                  'com ele, e reenvie.' }
  end

  def com_veiculo(dados)
    return dados unless quote_input.auto?

    veiculo = dados['vehicle'].to_h
    return dados if veiculo['plate'].blank?

    dados.merge('vehicle' => veiculo.merge(lido_da_placa(veiculo['plate'])))
  rescue StandardError => e
    Rails.logger.warn("[autonomia][insurance] consulta de placa indisponivel account=#{account.id} #{e.class}")
    dados
  end

  # O que a consulta acrescenta, POR CIMA do que o modelo escreveu: tipo e ano do modelo. Vazio
  # quando não houve consulta — no turno sem sessão viva.
  # O nome do carro fica guardado para o texto do zero-km — não vai na entrada (o adapter não tem
  # esse campo; o nome ele mesmo resolve pela placa).
  def lido_da_placa(placa)
    consulta = consultar_placa(placa)
    return sem_sessao_viva if consulta.nil?

    @modelo_lido = consulta['model'].presence
    { 'vehicleType' => consulta['vehicle_type'], 'modelYear' => consulta['model_year'] }.compact
  end

  # ONDE ESTA INSTÂNCIA RODA decide com que sessão consultar. `delivery` é o contexto do turno
  # (`Native::Base`): presente, é a conferência com o modelo esperando — só serve a sessão que já
  # está viva, porque abrir uma é login com o teto de 60 s do conector. Ausente, é o job do envio,
  # que tem tempo e renova a sessão como as demais operações dele.
  def consultar_placa(placa)
    consulta = ->(session) { connector.vehicle_lookup(provider: connection.provider, session: session, plate: placa) }
    delivery.present? ? sessions.with_live_session(&consulta) : sessions.with_fresh_session(&consulta)
  end

  def sem_sessao_viva
    Rails.logger.info("[autonomia][insurance] consulta de placa pulada no turno: sem sessao viva account=#{account.id}")
    {}
  end
end
