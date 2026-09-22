# O Guia consultando a plataforma inteira, como quem perguntou (issue #533, 2ª volta).
#
# A primeira versão tinha cinco assuntos escritos à mão, e cobertura de cinco
# assuntos nunca vira cobertura da plataforma. Aqui o catálogo é DERIVADO das
# rotas de leitura da API da conta — as mesmas 268 que a interface usa — do mesmo
# jeito que o mapa do Guia passou a sair do roteador.
#
# O que sustenta isso com segurança não é uma lista minha, é o critério do
# Rodrigo: **o que a pessoa vê na tela, a IA vê; o que ela não vê, a IA não vê.**
# Por isso a consulta roda como o usuário, pelo mesmo caminho da interface, e
# herda Pundit, papel, funções personalizadas e isolamento de conta. Chave de
# integração continua fora porque a própria API a devolve mascarada.
#
# Só leitura: escrever é outra fatia, com confirmação (#536).
class Autonomia::Guide::Consulta
  class Recusada < StandardError; end

  PREFIXO = '/api/v1/accounts/'.freeze

  # Rotas que pedem identificador que o Guia não tem como adivinhar ficam fora do
  # catálogo oferecido ao modelo: sem o id, a chamada só produziria erro. O
  # parâmetro no roteador começa com dois pontos — basta procurar o caractere.
  PARAMETRO = ':'.freeze

  # Quanto cabe numa leitura, quando o chamador não diz. Quem lê por ferramenta
  # passa um teto bem menor, porque a saída de uma ferramenta tem limite próprio.
  # O número e o porquê dele moram no `Resumo`, que é quem corta.
  TETO_PADRAO = ::Autonomia::Guide::Resumo::MAX_TEXTO

  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || account&.account_users&.find_by(user_id: user&.id)
  end

  # O que o modelo pode pedir, em linguagem de rota: 'inboxes', 'labels',
  # 'crm/pipelines'. Deriva do roteador, então nasce completo e cresce sozinho.
  def catalogo
    @catalogo ||= Rails.application.routes.routes.filter_map do |rota|
      next unless rota.verb.to_s == 'GET'

      caminho = rota.path.spec.to_s.sub('(.:format)', '')
      next unless caminho.start_with?(PREFIXO)

      recurso = caminho.sub("#{PREFIXO}:account_id/", '')
      next if recurso.blank?

      recurso
    end.uniq.sort
  end

  # Executa a leitura como o usuário e devolve o corpo já enxuto, pronto para
  # virar contexto. Nunca levanta para o chamador: erro vira recusa explicada.
  #
  # `parametros` preenche o `:id` de rotas como 'contacts/:id'. Antes essas rotas
  # ficavam fora do catálogo, e isso tirava 145 das 270 leituras da plataforma: o
  # Guia listava suas caixas e não conseguia abrir nenhuma.
  # `campos` é a lista de campos que quem chamou quer de cada item — sem ela, a
  # lista vem enxuta por forma. Existe porque o Guia passou a ler por
  # FERRAMENTA (#568): quem não sabe o que quer recebe uma amostra e o catálogo
  # de campos, e pede de novo dizendo o que quer. Antes eu adivinhava aqui
  # dentro, e adivinhar errado custou a resposta "pelo menos 6 conversas" para
  # quem tem 47.
  #
  # `teto` é o orçamento DESTA chamada. Ele é do chamador porque a saída de uma
  # ferramenta tem um limite próprio (`Tools::Bound::MAX_OUTPUT_CHARS`), e
  # estourar esse limite corta JSON no meio.
  def ler(recurso, parametros = {}, filtros = {}, campos: nil, teto: TETO_PADRAO)
    caminho = montar_caminho(recurso, parametros)
    resposta = requisitar(caminho, filtros, sobras(recurso, parametros))

    return indisponivel(recurso, resposta.codigo) unless resposta.codigo.to_i == 200

    ::Autonomia::Guide::Resumo.new(corpo: resposta.corpo, campos: campos, teto: teto).texto
  rescue Recusada => e
    e.message
  rescue StandardError => e
    # A mensagem e o começo da pilha vão junto de propósito. Em 21/09/2026 este
    # log registrou só a classe, e um `NoMethodError` de uma linha — `each_key`
    # num Array — derrubou a leitura de conversas inteira disfarçado de "não
    # consegui ler agora". Custou uma rodada inteira de revisão para achar.
    Rails.logger.error(
      "[autonomia][guide][consulta] account=#{@account&.id} recurso=#{recurso} #{e.class}: #{e.message}\n" \
      "#{Array(e.backtrace).first(5).join("\n")}"
    )
    "Não consegui ler #{recurso} agora."
  end

  private

  # Isto vira texto que o modelo repassa para a pessoa, então não pode ser um
  # número de status HTTP. 404 e 403 aqui quase sempre significam a mesma coisa
  # para quem está perguntando: o recurso não está ligado nesta conta, ou o
  # perfil dela não alcança. Os outros são falha nossa, e o número fica no log.
  def indisponivel(recurso, codigo)
    Rails.logger.warn("[autonomia][guide][consulta] account=#{@account&.id} recurso=#{recurso} http=#{codigo}")

    case codigo.to_s
    # Recurso desligado na conta.
    when '404' then "Isto não está disponível nesta conta: #{recurso}."
    # Ligado, mas fora do alcance do perfil de quem perguntou. Dizer que "não
    # está disponível" faria a pessoa achar que precisa contratar o que já tem.
    #
    # 401 está aqui porque é o que esta aplicação devolve quando o Pundit nega:
    # `render_unauthorized` responde `:unauthorized`. Eu tinha tratado só o 403,
    # que nunca chega — e negativa de permissão caía no genérico, fazendo quem
    # não tem acesso ouvir "deu erro, tente de novo".
    when '401', '403' then "O perfil de quem perguntou não tem acesso a isto: #{recurso}."
    else "Não consegui ler #{recurso} agora."
    end
  end

  # O caminho é sempre montado com o id DESTA conta, e cada `:id` vira um
  # segmento escapado — valor vindo do modelo nunca entra como pedaço de rota.
  def montar_caminho(recurso, parametros)
    limpo = recurso.to_s.strip.delete_prefix('/')
    raise Recusada, 'Não sei consultar isso.' unless catalogo.include?(limpo)

    valores = (parametros || {}).transform_keys(&:to_s)
    segmentos = limpo.split('/').map do |segmento|
      next segmento unless segmento.start_with?(PARAMETRO)

      chave = segmento.delete_prefix(PARAMETRO)
      valor = valores[chave].to_s.strip
      raise Recusada, "Para isso eu preciso saber qual #{chave}." if valor.blank?

      CGI.escape(valor)
    end

    "#{PREFIXO}#{@account.id}/#{segmentos.join('/')}"
  end

  # A chamada sai com o token do próprio usuário: é o mecanismo oficial da API e
  # é o que garante que a resposta seja exatamente a que ele receberia na tela.
  # O token nunca é registrado em log.
  def requisitar(caminho, filtros, sobras)
    ::Autonomia::Guide::ChamadaInterna.new(user: @user)
                                      .chamar(:get, caminho, filtros: sobras.merge(filtros.slice(*%w[status page sort]).compact))
  end

  # O parâmetro que não preenche um `:` do caminho segue como filtro da leitura,
  # do jeito que o painel manda: o kanban lê `?pipeline_id=`. Antes ele era
  # jogado fora calado (#593) — o Guia pediu o kanban do funil 10, recebeu o do
  # funil 8, e não tinha como saber. Só valor simples; o caminho continua
  # sendo montado com o id desta conta.
  def sobras(recurso, parametros)
    (parametros || {}).transform_keys(&:to_s).except(*do_caminho(recurso))
                      .select { |_chave, valor| valor.is_a?(String) || valor.is_a?(Integer) }
                      .transform_values(&:to_s)
  end

  def do_caminho(recurso)
    recurso.to_s.split('/').select { |segmento| segmento.start_with?(PARAMETRO) }
           .map { |segmento| segmento.delete_prefix(PARAMETRO) }
  end
end
