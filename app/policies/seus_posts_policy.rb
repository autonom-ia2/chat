# Seus posts (#2302): ver a página, os números do perfil e os posts é administrador ou `posts_view`; responder,
# esconder e mandar no privado é `posts_manage`, que também vê (manage implica view, Enterprise::AccountUser).
# Módulo comum, delegável (parecer da sessão Funções, 27/10). Os comentários (quem escreveu) e as ações sobre eles
# pedem também ver a caixa (InboxPolicy#show?), conferido em cada caixa.
class SeusPostsPolicy < ApplicationPolicy
  def index?
    granted?('posts_view')
  end

  def manage?
    granted?('posts_manage')
  end

  private

  # No OSS, permission_granted? é administrator?; o EE soma as chaves da função personalizada.
  def granted?(key)
    account_user&.permission_granted?(key) || false
  end
end
