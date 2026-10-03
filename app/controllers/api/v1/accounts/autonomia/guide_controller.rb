# Guia da Plataforma — onboarding, suporte e ações na conta. NÃO admin-only (qualquer perfil da conta
# usa). Gated pela elegibilidade Autonomia (ENV master + chave de IA do Kanban por conta) — o mesmo
# gate que faz o Guia nascer sozinho.
#
# Ele responde, orienta, lê a conta e muda a conta (#855): o que tem desfazer ele faz no próprio
# turno, anotado em `Autonomia::Guide::Execucao`; o que não tem volta ele propõe, e só `executar_acao`
# grava, depois do clique em confirmar na tela.
class Api::V1::Accounts::Autonomia::GuideController < Api::V1::Accounts::BaseController
  before_action :ensure_guide_enabled

  # #572 — a pergunta NÃO é respondida aqui. Esta ação abre o pedido, põe o
  # Guia para trabalhar num job e devolve na hora; a tela busca a resposta em
  # `resposta`.
  #
  # Antes a resposta saía desta requisição, e o `rack-timeout` de produção mata
  # qualquer requisição aos 15 segundos: em 21/09/2026 uma pergunta que exigiu
  # duas leituras morreu aos 15,2s com erro 500.
  def chat
    pedido = ::Autonomia::Guide::Pedido.abrir(account: Current.account, user: Current.user)
    ::Autonomia::Guide::ChatJob.perform_later(
      pedido,
      { 'account_id' => Current.account.id, 'user_id' => Current.user.id,
        'mensagem' => params[:message].to_s, 'historico' => history_param,
        'tela' => params[:route_context].to_s, 'locale' => I18n.locale.to_s,
        'arquivos' => Array(params[:arquivos]).map(&:to_s).first(::Autonomia::Guide::Arquivos::MAX_POR_TURNO) }
    )

    render json: { id: pedido, status: ::Autonomia::Guide::Pedido::PENDENTE }, status: :accepted
  end

  # O estado do pedido e, quando pronto, a resposta — com os mesmos campos que a
  # tela sempre recebeu: text, navigation, grounded, confidence, available,
  # escalate, acao, retido e artigo (o artigo da Central que o Guia leu, para o
  # botão "Ler o artigo completo").
  #
  # Pedido de outra pessoa responde 404, igual a pedido que não existe: a
  # resposta foi montada com a permissão de quem perguntou.
  def resposta
    pedido = ::Autonomia::Guide::Pedido.ler(params[:id], account: Current.account, user: Current.user)
    return head :not_found if pedido.nil?

    render json: pedido
  end

  # #536 — o Guia PREPARA a ação e devolve o texto que a pessoa lê antes de
  # confirmar. Nada acontece aqui.
  def preparar_acao
    descricao = acoes.descrever(params[:acao], dados_do_pedido)
    render json: { acao: params[:acao], descricao: descricao }
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # Só chega aqui depois da confirmação explícita na tela.
  def executar_acao
    resultado = acoes.executar(params[:acao], dados_do_pedido)
    registrar(resultado)
    return render json: { error: resultado.mensagem }, status: :unprocessable_entity unless resultado.ok

    render json: { mensagem: resultado.mensagem }
  rescue ::Autonomia::Guide::Acoes::Recusada => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # #857 — um arquivo que a pessoa anexou na conversa. Sobe aqui e volta como signed_id; quem lê é o
  # job da pergunta, pelos extratores da base de conhecimento. O tipo sai do CONTEÚDO (Marcel), não
  # do nome nem do header do navegador.
  def arquivo
    file = params[:file]
    return render json: { error: I18n.t('autonomia.guide.file.required') }, status: :unprocessable_entity if file.blank?

    content_type = Marcel::MimeType.for(file.tempfile, name: file.original_filename).to_s
    erro = erro_do_arquivo(file, content_type)
    return render json: { error: erro }, status: :unprocessable_entity if erro

    file.tempfile.rewind
    blob = ActiveStorage::Blob.create_and_upload!(
      io: file.tempfile, filename: file.original_filename, content_type: content_type, identify: false,
      metadata: ::Autonomia::Guide::Arquivos.metadata(Current.account)
    )
    render json: { signed_id: ::Autonomia::Guide::Arquivos.assinar(blob), nome: blob.filename.to_s }
  end

  # #855 — o que o Guia fez para esta pessoa nesta conta, ainda dentro do prazo
  # de desfazer. É daqui que a pessoa desfaz depois de recarregar a tela.
  def execucoes
    lista = ::Autonomia::Guide::Execucao.de(Current.account, Current.user).vigentes
                                        .order(created_at: :desc).limit(LIMITE_DE_EXECUCOES)
    render json: { execucoes: lista.map(&:resumo) }
  end

  # Só quem pediu desfaz: a execução saiu com a permissão dela. De outra pessoa
  # responde 404, igual a uma que não existe.
  def desfazer
    execucao = ::Autonomia::Guide::Execucao.de(Current.account, Current.user).find_by(id: params[:id])
    return head :not_found if execucao.nil?

    ::Autonomia::Guide::Desfazer.new(execucao: execucao, user: Current.user).perform
    render json: { execucao: execucao.reload.resumo }
  rescue ::Autonomia::Guide::Desfazer::Recusado => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def erro_do_arquivo(file, content_type)
    return I18n.t('autonomia.guide.file.invalid_type') if ::Autonomia::Guide::Arquivos.formato(content_type).nil?

    I18n.t('autonomia.guide.file.too_large') if file.size > ::Autonomia::Guide::Arquivos::MAX_BYTES
  end

  LIMITE_DE_EXECUCOES = 50

  # O corpo da ação é conteúdo livre (os campos do recurso), então não cabe strong
  # params por campo: quem autoriza é o endpoint real, chamado com o token de quem
  # pediu. Aqui só tiramos o invólucro do Rails.
  def dados_do_pedido
    bruto = params[:dados]
    return {} if bruto.blank?

    bruto.respond_to?(:to_unsafe_h) ? bruto.to_unsafe_h.deep_symbolize_keys : bruto.to_h.deep_symbolize_keys
  end

  def acoes
    ::Autonomia::Guide::Acoes.new(account: Current.account, user: Current.user,
                                  account_user: Current.account_user)
  end

  # Quem pediu, o que mudou e quando — para uma ação feita pelo Guia nunca virar
  # mudança sem dono.
  def registrar(resultado)
    Rails.logger.info(
      "[autonomia][guide][acao] account=#{Current.account.id} user=#{Current.user.id} " \
      "acao=#{params[:acao]} ok=#{resultado.ok} registro=#{resultado.registro}"
    )
  end

  def ensure_guide_enabled
    head :not_found unless ::Autonomia::Guide::Seed.eligible?(Current.account)
  end

  # Robusto: aceita só itens hash/params (string/símbolo); um item malformado (ex.: "x") não derruba
  # o endpoint com TypeError antes do rescue do serviço.
  def history_param
    Array(params[:history]).filter_map do |h|
      next unless h.is_a?(Hash) || h.is_a?(ActionController::Parameters)

      { role: h[:role].to_s, content: h[:content].to_s }
    end
  end
end
