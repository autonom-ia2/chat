# O Guia que faz a plataforma inteira, com confirmação (issues #536 e #547).
#
# A primeira versão tinha três ações escritas à mão. Três ações nunca viram a
# plataforma, do mesmo jeito que cinco assuntos nunca viraram cobertura de
# leitura. Aqui o catálogo é DERIVADO das rotas de escrita da API da conta — as
# mesmas que a interface usa quando você clica.
#
# O que sustenta isso não é uma lista minha, é o critério do Rodrigo: **o que a
# pessoa pode fazer na tela, a IA pode fazer por ela; o que ela não pode, a IA
# não pode.** A execução sai com o token de quem pediu, pelo mesmo endpoint da
# interface, e herda Pundit, papel, funções personalizadas e isolamento de conta.
# Nada de permissão reimplementada aqui.
#
# Três coisas que este arquivo não negocia:
#
# 1. **Nada executa sem confirmação.** `descrever` e `executar` são separados, e
#    a descrição mostra o pedido literal antes de qualquer clique.
# 2. **A proposta nasce só do que a pessoa escreveu.** Nome de contato, de funil
#    ou texto de conversa que o Guia leu na conta entram como dado e nunca viram
#    ordem — a montagem do pedido é feita em EscolhaDaAcao, a partir da mensagem.
# 3. **Fora do alcance, por decisão do Rodrigo (20/09/2026):** nada que fale com
#    cliente, mexa em dinheiro ou toque em acesso e credencial.
class Autonomia::Guide::Acoes
  class Recusada < StandardError; end

  PREFIXO = '/api/v1/accounts/'.freeze
  VERBOS = %w[POST PATCH PUT DELETE].freeze
  DESTRUTIVO = 'DELETE'.freeze

  # NÃO existe lista de áreas bloqueadas, por decisão do Rodrigo em 20/09/2026:
  # o administrador pode pedir tudo que ele mesmo pode fazer na conta dele.
  #
  # O que protege não é uma lista minha:
  # - a pessoa lê o pedido literal e confirma antes de qualquer execução;
  # - a execução vai com o token dela, então a plataforma aplica a permissão real;
  # - o caminho é montado com o id da conta dela, sempre.
  #
  # Isto inclui disparar campanha (mensagem para cliente de verdade) e rotacionar
  # credencial (pode derrubar integração em produção). Não há desfazer para
  # nenhum dos dois: a tela de confirmação é a proteção.

  Resultado = Struct.new(:ok, :mensagem, :registro, keyword_init: true)

  def initialize(account:, user:, account_user: nil)
    @account = account
    @user = user
    @account_user = account_user || account&.account_users&.find_by(user_id: user&.id)
  end

  # O que o Guia pode fazer, em linguagem de rota: 'POST crm/pipelines',
  # 'PATCH inboxes/:id', 'DELETE labels/:id'. Deriva do roteador, então nasce
  # completo e cresce junto com a plataforma.
  def catalogo
    @catalogo ||= Rails.application.routes.routes.filter_map do |rota|
      verbo = rota.verb.to_s
      next unless VERBOS.include?(verbo)

      caminho = rota.path.spec.to_s.sub('(.:format)', '')
      next unless caminho.start_with?(PREFIXO)

      recurso = caminho.sub("#{PREFIXO}:account_id/", '')
      next if recurso.blank?

      "#{verbo} #{recurso}"
    end.uniq.sort
  end

  # O texto que a pessoa lê ANTES de confirmar. Sem isso não há confirmação
  # informada — e confirmação no escuro não é confirmação.
  #
  # A frase em português vem de quem entendeu o pedido; o pedido literal vem
  # daqui. As duas coisas aparecem, porque a frase pode suavizar e o literal não.
  # A pessoa precisa ver O QUE VAI ACONTECER, com os valores — não a rota HTTP.
  # A primeira versão mostrava "POST /api/v1/accounts/16/crm/pipelines" na tela:
  # lixo técnico para quem usa o produto, e estrutura interna exposta à toa.
  #
  # `montar_caminho` continua sendo chamado aqui de propósito: é ele que recusa
  # ação sem o identificador, e essa recusa tem que acontecer ANTES do botão
  # aparecer, não depois do clique.
  def descrever(acao, dados)
    garantir_permitida!(acao)
    montar_caminho(acao, dados)

    # Sem frase não há confirmação informada. O esquema deixa a descrição
    # anulável, e cair no verbo com a rota traria "POST crm/pipelines" de volta
    # para a tela — o mesmo jargão, pela porta dos fundos. Melhor recusar.
    raise Recusada, 'Não consegui explicar o que ia fazer, então não vou fazer.' if dados[:descricao].blank?

    { frase: dados[:descricao],
      detalhe: valores_legiveis(corpo_de(dados)),
      aviso: (verbo_de(acao) == DESTRUTIVO ? 'Isto apaga o registro e não tem volta.' : nil) }
  end

  # Só roda depois da confirmação. Vai pela API da conta, como o usuário: se a
  # plataforma não deixa ele fazer, não deixa o Guia fazer.
  def executar(acao, dados)
    garantir_permitida!(acao)
    resposta = requisitar(verbo_de(acao), montar_caminho(acao, dados), corpo_de(dados))

    return Resultado.new(ok: true, mensagem: 'Pronto, feito.', registro: identificador(resposta)) if sucesso?(resposta)

    Resultado.new(ok: false, mensagem: recusa_da_plataforma(resposta))
  rescue Recusada
    raise
  rescue StandardError => e
    Rails.logger.error("[autonomia][guide][acao] account=#{@account&.id} #{e.class}")
    Resultado.new(ok: false, mensagem: 'Não consegui executar agora.')
  end

  private

  def garantir_permitida!(acao)
    raise Recusada, 'Isto o Guia não faz.' unless catalogo.include?(acao.to_s)
    raise Recusada, 'Só o administrador da conta faz isso.' unless administrador?
  end

  def administrador?
    @account_user&.role.to_s == 'administrator'
  end

  def verbo_de(acao)
    acao.to_s.split(' ', 2).first
  end

  def recurso_de(acao)
    acao.to_s.split(' ', 2).last
  end

  # Troca cada `:id` pelo valor que veio no pedido. Sem valor, não executa: uma
  # rota com parâmetro em branco atingiria o registro errado ou nenhum.
  def montar_caminho(acao, dados)
    valores = (dados[:caminho] || {}).transform_keys(&:to_s)

    segmentos = recurso_de(acao).split('/').map do |segmento|
      next segmento unless segmento.start_with?(':')

      chave = segmento.delete_prefix(':')
      valor = valores[chave].to_s.strip
      raise Recusada, "Faltou dizer qual #{chave}." if valor.blank?

      CGI.escape(valor)
    end

    "#{PREFIXO}#{@account.id}/#{segmentos.join('/')}"
  end

  def corpo_de(dados)
    (dados[:corpo] || {}).to_h
  end

  # Os valores que vão mudar, em linguagem de gente: "Nome: Comercial". Sem isso
  # a confirmação seria só a frase do modelo, que pode suavizar ou errar um valor
  # — e a pessoa confirmaria sem ver o que de fato vai ser gravado.
  def valores_legiveis(corpo)
    return nil if corpo.blank?

    corpo.filter_map do |campo, valor|
      texto = valor.is_a?(Array) ? valor.join(', ') : valor.to_s
      next if texto.blank?

      "#{rotulo(campo)}: #{texto}"
    end.join(' · ').presence
  end

  # Nome de campo da API vira etiqueta legível. Campo que não estiver aqui
  # aparece com o próprio nome, sem underline — melhor do que esconder o valor.
  ROTULOS = { 'name' => 'Nome', 'title' => 'Nome', 'description' => 'Descrição',
              'email' => 'E-mail', 'phone_number' => 'Telefone', 'color' => 'Cor' }.freeze

  def rotulo(campo)
    ROTULOS[campo.to_s] || campo.to_s.tr('_', ' ').capitalize
  end

  def requisitar(verbo, caminho, corpo)
    uri = URI.parse("http://127.0.0.1:#{porta}#{caminho}")
    classe = { 'POST' => Net::HTTP::Post, 'PATCH' => Net::HTTP::Patch,
               'PUT' => Net::HTTP::Put, 'DELETE' => Net::HTTP::Delete }.fetch(verbo)

    requisicao = classe.new(uri)
    requisicao['api_access_token'] = @user.access_token.token
    requisicao['Content-Type'] = 'application/json'
    requisicao.body = JSON.generate(corpo) if corpo.present?

    Net::HTTP.start(uri.hostname, uri.port, open_timeout: 2, read_timeout: 15) { |http| http.request(requisicao) }
  end

  def porta
    ENV.fetch('PORT', 3000)
  end

  def sucesso?(resposta)
    resposta.code.to_i.between?(200, 299)
  end

  # O erro que volta é o da própria plataforma, em vez de um texto meu: é ele que
  # diz a verdade sobre o que faltou ou o que não foi permitido.
  def recusa_da_plataforma(resposta)
    dados = JSON.parse(resposta.body.to_s)
    motivo = dados['message'] || dados['error'] || Array(dados['errors']).join(', ')
    motivo.presence || "A plataforma respondeu #{resposta.code}."
  rescue JSON::ParserError
    "A plataforma respondeu #{resposta.code}."
  end

  def identificador(resposta)
    dados = JSON.parse(resposta.body.to_s)
    dados = dados['payload'] || dados
    dados.is_a?(Hash) ? dados['id'] : nil
  rescue JSON::ParserError
    nil
  end
end
