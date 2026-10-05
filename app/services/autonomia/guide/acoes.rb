# O Guia que faz a plataforma inteira (issues #536, #547 e #855).
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
# 1. **O que não tem volta pede confirmação; o resto tem desfazer.** Desde a
#    #855 o Guia executa direto e anota tudo para desfazer por 5 dias
#    (`Diario`, `Desfazer`). As ações de `SEM_DESFAZER` continuam passando por
#    `descrever` e pelo clique em Confirmar.
# 2. **A proposta nasce só do que a pessoa escreveu.** Nome de contato, de funil
#    ou texto de conversa que o Guia leu na conta entram como dado e nunca viram
#    ordem — a montagem do pedido é feita em EscolhaDaAcao, a partir da mensagem.
# 3. **Nada é executado por HTTP para nós mesmos.** O pedido roda na mesma
#    thread, pela pilha do Rails: ver `ChamadaInterna`, e o porquê lá.
class Autonomia::Guide::Acoes
  class Recusada < StandardError; end
  # O corpo não bate com o formato da ação (#900). É uma Recusada, então todo
  # caminho que já trata recusa trata esta; as ferramentas só não juntam as
  # ações vizinhas, porque a ação está certa e o que falta corrigir é o corpo.
  CorpoForaDoFormato = Class.new(Recusada)

  VERBOS = %w[POST PATCH PUT DELETE].freeze
  DESTRUTIVO = 'DELETE'.freeze

  # NÃO existe lista de áreas bloqueadas, por decisão do Rodrigo em 20/09/2026:
  # o administrador pode pedir tudo que ele mesmo pode fazer na conta dele.
  # Dinheiro da conta na plataforma (plano, cobrança, créditos) nem entra no
  # catálogo: mora em /enterprise/api/v1/accounts, fora de `Rotas.recurso`.
  #
  # O que protege:
  # - a execução vai com o token da pessoa, então a plataforma aplica a permissão real;
  # - o caminho é montado com o id da conta dela, sempre;
  # - tudo o que muda no banco fica anotado para desfazer por 5 dias (#855).
  #
  # A lista abaixo é o que o desfazer NÃO alcança, decidido com o Rodrigo em
  # 02/10/2026: o que sai da plataforma (mensagem, ligação, campanha — inclusive
  # o WhatsApp oficial, que a Meta cobra do cliente), o que troca credencial em
  # uso e o que grava em lote fora da requisição (importação, ação em massa,
  # macro), onde o caderno não chega. Apagar caixa, empresa, contato, conversa,
  # time, portal, SLA ou etiqueta também entra: a plataforma termina essas
  # exclusões num job (`DeleteObjectJob`, `dependent: :destroy_async`,
  # `Labels::RemoveAssociationsJob`), e o desfazer só traria de volta metade.
  # Para estas, a pessoa confirma antes.
  SEM_DESFAZER = [
    'POST conversations',
    'POST conversations/:conversation_id/messages',
    'POST conversations/:conversation_id/messages/:id/retry',
    'POST conversations/:conversation_id/contact_info_request',
    'POST contacts/:id/call',
    'POST whatsapp_calls/initiate',
    'POST campaigns',
    'POST whatsapp_api_campaigns',
    'POST whatsapp_api_campaigns/:id/resume',
    'POST email_campaigns/campaigns/:id/send_now',
    'POST email_campaigns/campaigns/:id/schedule',
    'POST email_campaigns/campaigns/:id/resume',
    'POST portals/:id/send_instructions',
    'POST crm/integration_tokens/:id/rotate',
    'POST agent_bots/:id/reset_access_token',
    'POST agent_bots/:id/reset_secret',
    'POST inboxes/:id/reset_secret',
    'POST inboxes/:id/rotate_hmac_token',
    'PUT inboxes/:id/whatsapp_business_management_token',
    'POST contacts/import',
    'POST data_imports/:id/start',
    'POST campaign_imports/:id/confirm', 'POST contact_imports/:id/confirm',
    'POST bulk_actions',
    'POST captain/bulk_actions',
    'POST macros/:id/execute',
    'DELETE inboxes/:id',
    'DELETE companies/:id',
    'DELETE contacts/:id',
    'DELETE conversations/:id',
    'DELETE teams/:id',
    'DELETE portals/:id',
    'DELETE sla_policies/:id',
    # #858 — resolver um caso parado do Decisor retoma a automação num job, que pode mandar mensagem
    # ou mover card fora do caderno. (A conversa com o Guia saiu do catálogo: D3, #933.)
    # #936 — começar e seguir uma tarefa longa soltam lotes em centenas de registros: só a pessoa autoriza.
    'DELETE labels/:id', 'POST autonomia/decisoes/:id/resolver', 'POST autonomia/tarefas/:id/comecar', 'POST autonomia/tarefas/:id/seguir'
  ].freeze

  # `mensagem` é para a pessoa (a tela do clique mostra); `dica` e `aviso` são
  # para o modelo: o formato do que a plataforma recusou e o que ela pode ter
  # descartado (#900).
  Resultado = Struct.new(:ok, :mensagem, :registro, :corpo, :dica, :aviso, keyword_init: true)

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

      recurso = ::Autonomia::Guide::Rotas.recurso(rota.path.spec.to_s.sub('(.:format)', ''))
      "#{verbo} #{recurso}" if recurso
    end.uniq.sort
  end

  # O que a execução DIRETA (sem clique) recusa — ação fora do catálogo, quem
  # não administra, identificador faltando e o que não tem volta — recusado
  # ANTES de abrir a execução, para a lista "Feito pelo Guia" não ganhar um turno
  # vazio. O que não tem volta fica aqui, e não só na ferramenta (#856): qualquer
  # caminho que execute pelo turno passa por este ponto, e a confirmação não
  # pode depender de quem chamou lembrar dela.
  def conferir!(acao, dados)
    garantir_permitida!(acao)
    raise Recusada, traduzir('needs_confirmation') unless desfazivel?(acao, dados)

    montar_caminho(acao, dados)
    conferir_corpo!(acao, dados)
  end

  # Tem desfazer? Então o Guia executa direto; se não, a pessoa confirma. Sem `dados`, responde pela
  # ação só (o formato da ação não tem corpo); com eles, também pelo que o corpo faz.
  # O corpo também conta pelo esquema: o que cai num nó `x-sem-volta` (regra que manda mensagem) confirma.
  def desfazivel?(acao, dados = nil)
    SEM_DESFAZER.exclude?(acao.to_s) && !::Autonomia::Guide::RegraComDecisor.new(@account).fica_ligada?(acao.to_s, dados) &&
      !(dados && conferencia(acao, dados).sem_volta?)
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
    conferencia = conferir_corpo!(acao, dados)

    # Sem frase não há confirmação informada. O esquema deixa a descrição
    # anulável, e cair no verbo com a rota traria "POST crm/pipelines" de volta
    # para a tela — o mesmo jargão, pela porta dos fundos. Melhor recusar.
    raise Recusada, traduzir('no_description') if dados[:descricao].blank?

    { frase: dados[:descricao],
      detalhe: valores_legiveis(dados, conferencia),
      aviso: (verbo_de(acao) == DESTRUTIVO ? traduzir('irreversible') : nil) }
  end

  # Executa pela API da conta, como o usuário: se a
  # plataforma não deixa ele fazer, não deixa o Guia fazer.
  def executar(acao, dados)
    garantir_permitida!(acao)
    caminho = montar_caminho(acao, dados)
    conferencia = conferir_corpo!(acao, dados)
    resposta = requisitar(verbo_de(acao), caminho, conferencia.corpo)

    return concluida(acao, dados, resposta, conferencia) if sucesso?(resposta)

    Resultado.new(ok: false, mensagem: recusa_da_plataforma(resposta) || traduzir('failed'),
                  dica: ::Autonomia::Guide::Formatos::Retorno.new(acao, resposta).dica)
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

  def concluida(acao, dados, resposta, conferencia)
    registro = identificador(resposta)
    auditar(acao, dados, registro)
    Resultado.new(ok: true, mensagem: traduzir('done'), registro: registro, corpo: resposta.corpo,
                  aviso: ::Autonomia::Guide::Formatos::Retorno.new(acao, resposta).descartadas(conferencia))
  end

  # Confere o corpo contra o formato da ação ANTES de chamar a plataforma, e
  # devolve a conferência com o corpo no envelope certo (#900).
  def conferir_corpo!(acao, dados) = conferencia(acao, dados).conferida!
  def conferencia(acao, dados) = ::Autonomia::Guide::Formatos::Conferencia.new(acao, corpo_de(dados), conta: @account)

  def garantir_permitida!(acao)
    raise Recusada, traduzir('unknown_action') unless catalogo.include?(acao.to_s)
    raise Recusada, traduzir('admin_only') unless administrador?
  end

  def administrador?
    @account_user&.role.to_s == 'administrator'
  end

  def verbo_de(acao) = acao.to_s.split(' ', 2).first

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

    ::Autonomia::Guide::Rotas.caminho(@account.id, segmentos)
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
  def valores_legiveis(dados, conferencia)
    alvo = (dados[:caminho] || {}).to_h.transform_keys(&:to_s)
    campos = alvo.merge(conferencia.valores)
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

  AUDITORIA = 'guide_action'.freeze

  # Quem fez, o quê, quando — e que foi PELO GUIA (#536). Vai para a mesma trilha
  # da tela de Auditoria da conta, não para um lugar novo.
  #
  # Antes isto era só uma linha de log. Em 21/09/2026 apareceu na conta 16 uma
  # etiqueta criada às 06:01 e ninguém conseguiu saber por quem: o log morava na
  # máquina que o deploy trocou. A auditoria mora no banco.
  #
  # A trilha que o `audited` monta sozinho não servia: ela só cobre alguns models
  # (caixa, time, automação…) e deixa de fora justamente o que o Guia mais cria —
  # etiqueta, funil do CRM. Aqui o registro vale para as 468 ações.
  #
  # A ação JÁ ACONTECEU quando isto roda. Se gravar a auditoria falhar, a pessoa
  # não pode ouvir que não deu certo — deu. O erro vai inteiro para o log.
  def auditar(acao, dados, registro)
    Audited.audit_class.create!(
      auditable: @account, user: @user, action: AUDITORIA,
      comment: dados[:descricao].to_s,
      audited_changes: { 'acao' => acao.to_s, 'frase' => dados[:descricao].to_s, 'registro' => registro }
    )
  rescue StandardError => e
    Rails.logger.error(
      "[autonomia][guide][auditoria] account=#{@account&.id} user=#{@user&.id} acao=#{acao} " \
      "#{e.class}: #{e.message}"
    )
  end

  # O erro que volta é o da própria plataforma: é ele que diz a verdade sobre o
  # que faltou ou o que não foi permitido. Quando não há motivo legível, devolve
  # nulo — quem chama troca por uma frase traduzida, em vez de mostrar um número
  # de status HTTP para quem está tentando trabalhar.
  def recusa_da_plataforma(resposta)
    dados = JSON.parse(resposta.corpo.to_s)
    return unless dados.is_a?(Hash)

    motivo = dados['message'] || dados['error'] || Array(dados['errors']).join(', ')
    motivo.presence
  rescue JSON::ParserError
    nil
  end

  # Algumas ações devolvem uma LISTA (POST teams/:id/team_members devolve os membros). Ler a lista
  # como registro quebrava aqui, DEPOIS de a plataforma ter gravado, e o Guia dizia que não tinha
  # conseguido o que tinha feito (bateria do #900, C19). Lista não tem um id só: o registro fica nil.
  def identificador(resposta)
    dados = JSON.parse(resposta.corpo.to_s)
    dados = dados['payload'] if dados.is_a?(Hash) && dados['payload'].is_a?(Hash)
    dados.is_a?(Hash) ? dados['id'] : nil
  rescue JSON::ParserError
    nil
  end
end
