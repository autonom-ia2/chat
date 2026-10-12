# Redator de mensagens com IA (#1354), compartilhado com a fase E da sessão Modelos WhatsApp (#1333, "Criar/Melhorar
# com IA"). Primeiro consumidor: o texto dos avisos do agendamento. A IA propõe; o código confere a estrutura de cada
# opção (`Canais::<canal>.validar`) e DESCARTA a que quebrar regra, nunca corrige em silêncio. Nada é salvo aqui.
#
#   Ai::Redacao::Escrever.call(
#     account:, feature: 'aviso_redacao', canal: 'whatsapp_texto', proposito: 'lembrete 1 dia antes do horário',
#     limites: { max_chars: 500 }, tom: 'simpatico',
#     chaves: { permitidas: %w[cliente.primeiro_nome horario.data_hora horario.link_gestao], obrigatorias: %w[horario.link_gestao] },
#     contexto: { pagina: 'Consulta de 45 min' }
#   )
#   # => { status: 'ok', opcoes: [{ texto:, chaves_usadas:, categoria_prevista:, motivo_categoria:, o_que_mudou: }],
#   #      pergunta: nil, sugestoes: [], descartadas: 0 }
#
# Entrada para o modelo: só o que o chamador passa e o catálogo (rótulo, tipo e exemplo FICTÍCIO de cada chave), nunca
# dado de cliente. `base` (texto atual) e `pedido` (`{ melhorias: [...], observacao:, recusa_meta: }`, modo melhorar)
# vão como DADO no JSON. Pela chave de IA da conta (`Crm::Ai::CredentialResolver`), com a `feature` do chamador na
# Gestão IA. Roda na requisição do painel: uma tentativa, 11 s, sem retry (o rack-timeout de produção corta aos 15 s).
class Ai::Redacao::Escrever
  class Indisponivel < StandardError; end

  MODELO = Crm::Ai::Config::MODEL_FOLLOWUP
  ESFORCO = 'low'.freeze
  TIMEOUT = 11
  OPCOES_PADRAO = 2
  ERROS_DA_FRONTEIRA = [Crm::Ai::ResponsesClient::Error, JSON::ParserError, TypeError, SystemCallError, SocketError,
                        OpenSSL::SSL::SSLError, Timeout::Error, Net::HTTPBadResponse, Net::ProtocolError].freeze
  # Exemplos fictícios por chave (nunca valor real), e por tipo para as demais chaves do catálogo.
  EXEMPLOS = {
    'cliente.primeiro_nome' => 'Ana', 'cliente.nome' => 'Ana Souza', 'horario.data_hora' => '14/10 às 15:00',
    'horario.link_gestao' => 'https://exemplo.com.br/b/AB3K9QXZ', 'minha_empresa.nome' => 'Studio Exemplo'
  }.freeze
  EXEMPLOS_POR_TIPO = { 'texto' => 'Exemplo', 'data' => '14/10/2026', 'hora' => '15:00', 'moeda' => 'R$ 1.250,00',
                        'link' => 'https://exemplo.com.br' }.freeze

  def self.call(**)
    new(**).call
  end

  # rubocop:disable Metrics/ParameterLists
  def initialize(account:, feature:, proposito:, canal:, limites:, chaves:, tom: nil, base: nil, pedido: nil,
                 opcoes: OPCOES_PADRAO, contexto: {}, modelo: nil)
    @account = account
    @feature = feature
    @proposito = proposito
    @canal = Ai::Redacao::Canais.para(canal)
    @limites = limites.to_h.symbolize_keys
    @chaves = { permitidas: Array(chaves[:permitidas]).map(&:to_s), obrigatorias: Array(chaves[:obrigatorias]).map(&:to_s) }
    @tom = tom
    @base = base
    @pedido = pedido
    @opcoes = opcoes.to_i.clamp(1, Ai::Redacao::Canais::Base::MAX_OPCOES)
    @contexto = contexto.to_h
    @modelo = modelo.presence || MODELO
    conferir_chaves!
  end
  # rubocop:enable Metrics/ParameterLists

  def call
    saida = @canal.normalizar(perguntar)
    validas, descartadas = saida[:opcoes].partition { |opcao| motivo_do_descarte(opcao).nil? }
    saida.merge(opcoes: validas.first(@opcoes).map { |opcao| @canal.normalizar_opcao(opcao) }, descartadas: descartadas.size)
  end

  private

  def conferir_chaves!
    desconhecidas = @chaves[:permitidas].reject { |chave| TemplateFields::Catalog.known?(chave) }
    raise ArgumentError, "chaves fora do catálogo: #{desconhecidas.join(', ')}" if desconhecidas.any?
    raise ArgumentError, 'obrigatória fora das permitidas' unless (@chaves[:obrigatorias] - @chaves[:permitidas]).empty?
    raise ArgumentError, 'limites.max_chars é do chamador' if @limites[:max_chars].to_i <= 0
  end

  def motivo_do_descarte(opcao)
    motivo = @canal.validar(opcao, chaves: @chaves, limites: @limites)
    Rails.logger.info("[ai][redacao] opcao_descartada canal=#{@canal.nome} feature=#{@feature} motivo=#{motivo}") if motivo
    motivo
  end

  def perguntar
    resposta = cliente.create(model: @modelo, instructions: @canal.prompt, input: entrada.to_json,
                              schema: @canal.schema(permitidas: @chaves[:permitidas], opcoes: @opcoes),
                              reasoning_effort: ESFORCO, timeout: TIMEOUT)
    saida = JSON.parse(resposta[:text])
    raise Indisponivel, 'resposta_fora_do_formato' unless saida.is_a?(Hash)

    saida
  rescue *ERROS_DA_FRONTEIRA => e
    # Fronteira com a IA: erro do cliente, da rede (SSL, host fora, tempo) ou JSON quebrado vira Indisponivel com a
    # classe do erro (nunca o texto), e quem chama mostra a frase simples. Erro de programação não entra aqui: estoura.
    Rails.logger.warn("[ai][redacao] indisponivel canal=#{@canal.nome} feature=#{@feature} erro=#{e.class.name}")
    raise Indisponivel, e.class.name
  end

  def cliente
    raise Indisponivel, 'ai_disabled' unless Crm::Ai::Config.enabled?

    credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve
    raise Indisponivel, 'ai_not_configured' if credencial.blank?

    Crm::Ai::ResponsesClient.new(credential: credencial, feature: @feature, account: @account, max_retries: 0, cache_key_scope: :feature)
  end

  # O JSON da mensagem do usuário (formato do `comum.md`). O kit da marca ainda não tem "jeito de falar" (BrandKit só
  # guarda cores, fontes, logo e rodapé): `tom.kit` vai nulo até existir, e vale a escolha da pessoa.
  def entrada
    {
      canal: @canal.nome, proposito: @proposito, pedido: @pedido, base: @base,
      tom: { kit: nil, escolha: @tom.presence },
      limites: @limites.slice(:max_chars, :categoria_desejada, :sem_midia),
      chaves: { permitidas: @chaves[:permitidas].map { |chave| campo(chave) }, obrigatorias: @chaves[:obrigatorias] },
      opcoes: @opcoes, contexto: @contexto
    }
  end

  def campo(chave)
    tipo = TemplateFields::Catalog.type(chave)
    { chave: chave, rotulo: TemplateFields::Catalog.label(chave, locale: :pt_BR), tipo: tipo,
      exemplo: EXEMPLOS[chave] || EXEMPLOS_POR_TIPO.fetch(tipo, EXEMPLOS_POR_TIPO['texto']) }
  end
end
