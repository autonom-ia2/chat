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
# 3. **Nada é executado por HTTP para nós mesmos.** O pedido roda na mesma
#    thread, pela pilha do Rails: ver `ChamadaInterna`, e o porquê lá.
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
    raise Recusada, traduzir('no_description') if dados[:descricao].blank?

    { frase: dados[:descricao],
      detalhe: valores_legiveis(dados),
      aviso: (verbo_de(acao) == DESTRUTIVO ? traduzir('irreversible') : nil) }
  end

  # Só roda depois da confirmação. Vai pela API da conta, como o usuário: se a
  # plataforma não deixa ele fazer, não deixa o Guia fazer.
  def executar(acao, dados)
    garantir_permitida!(acao)
    resposta = requisitar(verbo_de(acao), montar_caminho(acao, dados), corpo_de(dados))

    return Resultado.new(ok: true, mensagem: traduzir('done'), registro: identificador(resposta)) if sucesso?(resposta)

    Resultado.new(ok: false, mensagem: recusa_da_plataforma(resposta) || traduzir('failed'))
  rescue Recusada
    raise
  rescue StandardError => e
    # O erro inteiro vai para o log, com backtrace: sem isso, um NoMethodError a
    # cinco quadros de profundidade vira "undefined method for nil" e ninguém
    # descobre onde foi sem reproduzir.
    Rails.logger.error(
      "[autonomia][guide][acao] account=#{@account&.id} acao=#{acao} #{e.class}: #{e.message}\n" \
      "#{Array(e.backtrace).first(5).join("\n")}"
    )
    Resultado.new(ok: false, mensagem: traduzir('failed'))
  end

  private

  def garantir_permitida!(acao)
    raise Recusada, traduzir('unknown_action') unless catalogo.include?(acao.to_s)
    raise Recusada, traduzir('admin_only') unless administrador?
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
      raise Recusada, traduzir('missing_param', campo: chave) if valor.blank?

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
  #
  # O identificador da rota entra junto, e isso importa mais do que parece: num
  # DELETE o corpo é sempre vazio, então a tela mostrava a frase e o aviso de que
  # não tem volta — e NADA sobre qual registro ia sumir. Se o modelo errasse o
  # id, a pessoa não tinha como perceber antes de clicar.
  def valores_legiveis(dados)
    alvo = (dados[:caminho] || {}).to_h
    campos = alvo.merge(corpo_de(dados))
    return nil if campos.blank?

    campos.filter_map do |campo, valor|
      texto = valor.is_a?(Array) ? valor.join(', ') : valor.to_s
      next if texto.blank?

      "#{rotulo(campo)}: #{texto}"
    end.join(' · ').presence
  end

  # Nome de campo da API vira etiqueta legível, no idioma de quem está olhando.
  # Campo sem tradução aparece com o próprio nome, sem underline: melhor mostrar
  # um nome feio do que esconder o valor que vai ser gravado.
  def rotulo(campo)
    chave = "autonomia.guide.fields.#{campo}"
    return I18n.t(chave) if I18n.exists?(chave)

    campo.to_s.tr('_', ' ').capitalize
  end

  def traduzir(chave, **valores)
    I18n.t("autonomia.guide.#{chave}", **valores)
  end

  def requisitar(verbo, caminho, corpo)
    ::Autonomia::Guide::ChamadaInterna.new(user: @user).chamar(verbo, caminho, corpo: corpo)
  end

  def sucesso?(resposta)
    resposta.codigo.to_i.between?(200, 299)
  end

  # O erro que volta é o da própria plataforma: é ele que diz a verdade sobre o
  # que faltou ou o que não foi permitido. Quando não há motivo legível, devolve
  # nulo — quem chama troca por uma frase traduzida, em vez de mostrar um número
  # de status HTTP para quem está tentando trabalhar.
  def recusa_da_plataforma(resposta)
    dados = JSON.parse(resposta.corpo.to_s)
    motivo = dados['message'] || dados['error'] || Array(dados['errors']).join(', ')
    motivo.presence
  rescue JSON::ParserError
    nil
  end

  def identificador(resposta)
    dados = JSON.parse(resposta.corpo.to_s)
    dados = dados['payload'] || dados
    dados.is_a?(Hash) ? dados['id'] : nil
  rescue JSON::ParserError
    nil
  end
end
