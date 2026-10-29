# Seus posts F2 (#2305): um post do perfil e os comentários dele. Atrás das flags `seus_posts` e
# `seus_posts_comentarios` (404 sem elas: nada aqui chama a Meta). Todos com ?perfil=<id> (SeusPosts::Perfil).
#
# GET    seus_posts/posts/:post_id                                         → { perfil, status, post, normal, comments, can_manage }
# GET    seus_posts/posts/:post_id/comments?after=                         → a página seguinte de comentários.
#        Ver: administrador ou `posts_view` (SeusPostsPolicy#index?).
# POST   seus_posts/posts/:post_id/comments/:comment_id/reply              content= → responder em público.
# POST   seus_posts/posts/:post_id/comments/:comment_id/private_reply      content= → mandar no privado (só Instagram).
# POST   seus_posts/posts/:post_id/comments/:comment_id/private_reply/release       → "Não foi enviado" (só Instagram).
# POST   seus_posts/posts/:post_id/comments/:comment_id/hide               hidden=  → esconder ou mostrar de novo.
# DELETE seus_posts/posts/:post_id/comments/:comment_id                             → apagar (a tela confirma antes).
#        Agir: administrador ou `posts_manage` (SeusPostsPolicy#manage?); senão 403.
#
# Ler e agir pedem também ver a caixa do perfil (InboxPolicy#show?; na Página, a caixa do Messenger dela). Sem ver:
# 403 `not_inbox_member`, antes de chamar a Meta (parecer da sessão Funções, 29/10). Perfil de outra conta, post que
# não é do perfil e comentário de outro post: 404. O texto vai só em `content`, que o log do Rails já filtra (#2103).
# Toda ação fica na Auditoria da conta com quem, o perfil, o post, o comentário e a ação, nunca o texto.
class Api::V1::Accounts::SeusPostsComentariosController < Api::V1::Accounts::BaseController
  AUDIT_ACTION = 'seus_posts_comment'.freeze
  FLAGS = %w[seus_posts seus_posts_comentarios].freeze
  NOT_FOUND = %w[post_not_found comment_not_found].freeze
  # Um id da Graph: dígitos, ou dígitos_dígitos (post e comentário da Página). Nada que vire outro caminho na chamada.
  ID_PARTS = (1..2)
  # Qualquer leitura do post serve: a lista dos posts não depende do período.
  DIAS = 30

  before_action :ensure_flags
  before_action :ensure_view
  before_action :ensure_manage, except: [:show, :index]
  before_action :ensure_ids
  before_action :load_canal
  before_action :ensure_inbox_member
  before_action :load_post, except: [:show]

  rescue_from ::Crm::MetaAds::InstagramPrivateReply::Error, ::Crm::MetaAds::FacebookComments::Error, with: :render_error

  def index
    render json: comentarios.payload(post_id, after: params[:after].presence&.to_s)
  end

  def show
    lido = leitura.post(post_id)
    return render_error_code('post_not_found') if lido.nil?

    base = { perfil: perfil, status: lido[:status], can_manage: manage? }
    return render json: base unless lido[:status] == 'ok'

    render json: base.merge(post: lido[:post], normal: lido[:normal], comments: comentarios.payload(post_id))
  end

  def reply
    result = comentarios.reply!(post_id, comment_id, content, user: Current.user)
    acted!('reply')
    render json: result
  end

  def private_reply
    return render_error_code('not_supported') unless instagram?

    result = comentarios.private_reply!(post_id, comment_id, content, user: Current.user)
    acted!('private_reply')
    render json: result
  end

  def release_private_reply
    return render_error_code('not_supported') unless instagram?

    result = comentarios.release_private_reply!(post_id, comment_id)
    acted!('private_reply_release')
    render json: result
  end

  def hide
    hidden = ActiveModel::Type::Boolean.new.cast(params[:hidden])
    return render_error_code('invalid_hidden') unless [true, false].include?(hidden)

    result = comentarios.hide!(post_id, comment_id, hidden: hidden, user: Current.user)
    acted!(hidden ? 'hide' : 'show')
    render json: result
  end

  def destroy
    result = comentarios.delete!(post_id, comment_id, user: Current.user)
    acted!('delete')
    render json: result
  end

  private

  def ensure_flags
    head :not_found unless FLAGS.all? { |flag| Current.account.feature_enabled?(flag) }
  end

  def ensure_view
    render json: { error: 'forbidden' }, status: :forbidden unless policy.index?
  end

  def ensure_manage
    render json: { error: 'forbidden' }, status: :forbidden unless manage?
  end

  def manage?
    policy.manage?
  end

  def policy
    @policy ||= Pundit.policy!(pundit_user, :seus_posts)
  end

  def ensure_ids
    ids = [post_id, (comment_id if params.key?(:comment_id))].compact
    render_error_code('post_not_found') unless ids.all? { |id| graph_id?(id) }
  end

  def graph_id?(value)
    parts = value.split('_', -1)
    ID_PARTS.cover?(parts.size) && parts.all? { |part| part.present? && part.each_char.all? { |char| char.between?('0', '9') } }
  end

  def load_canal
    @canal = SeusPosts::Perfil.achar(Current.account, params[:perfil].to_s)
    render json: { error: 'not_found' }, status: :not_found if @canal.nil?
  end

  def ensure_inbox_member
    return if SeusPosts::Caixa.new(inbox: @canal.inbox, viewer: pundit_user).ve?

    render json: { error: 'not_inbox_member' }, status: :forbidden
  end

  # Antes de cada ação e da página seguinte: o post tem de ser do perfil.
  def load_post
    lido = leitura.post(post_id)
    return render_error_code('post_not_found') if lido.nil?

    render_error_code(lido[:status] == 'needs_permission' ? 'needs_permission' : 'meta_unavailable') unless lido[:status] == 'ok'
  end

  def leitura
    SeusPosts::Leitura.new(account: Current.account, perfil: SeusPosts::Perfil.id_do(@canal), days: DIAS, viewer: pundit_user)
  end

  def comentarios
    @comentarios ||= if instagram?
                       SeusPosts::ComentariosInstagram.new(@canal, can_manage: manage?, conversation_access: method(:conversa_visivel?))
                     else
                       SeusPosts::ComentariosPagina.new(@canal, can_manage: manage?)
                     end
  end

  # "Ver conversa" do privado só para quem enxerga a conversa (em caixa com restrição, só as dela).
  def conversa_visivel?(conversation)
    Pundit.policy!(pundit_user, conversation).view?
  end

  def instagram?
    @canal.is_a?(Channel::Instagram)
  end

  def perfil
    { id: SeusPosts::Perfil.id_do(@canal), network: SeusPosts::Perfil.rede(@canal), inbox_id: @canal.inbox.id }
  end

  def post_id
    params[:post_id].to_s
  end

  def comment_id
    params[:comment_id].to_s
  end

  # Só texto: lista ou objeto em `content` virariam outro texto no `to_s` e iriam à Meta (#2327).
  def content
    value = params[:content]
    raise ::Crm::MetaAds::InstagramPrivateReply::Error, 'invalid_text' unless value.nil? || value.is_a?(String)

    value.to_s
  end

  def render_error(error)
    render_error_code(error.code)
  end

  def render_error_code(code)
    status = if NOT_FOUND.include?(code)
               :not_found
             elsif code == 'not_inbox_member'
               :forbidden
             else
               :unprocessable_content
             end
    render json: { error: code }, status: status
  end

  # A Meta já agiu quando isto roda: "esperando você" do perfil é lido de novo, e falha ao gravar a Auditoria vai para
  # o rastreador de erros, com a resposta dizendo a verdade (mesma regra dos comentários do anúncio, #2196).
  def acted!(action)
    SeusPosts::Leitura.esquecer_esperando(Current.account, @canal)
    Audited.audit_class.create!(
      auditable: Current.account, user: Current.user, action: AUDIT_ACTION,
      audited_changes: { 'network' => SeusPosts::Perfil.rede(@canal), 'perfil' => SeusPosts::Perfil.id_do(@canal), 'post_id' => post_id,
                         'comment_id' => comment_id, 'action' => action }
    )
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Current.account).capture_exception
  end
end
