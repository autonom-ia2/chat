# Seus posts (#2302): o que a pessoa vê da caixa de um perfil (parecer da sessão Funções, 27/10; mesma regra do painel
# de desempenho #2254, "os números são do que a pessoa vê"). Perfil de caixa que a pessoa não vê não aparece
# (SeusPosts::Leitura). A contagem de conversas é só das que ela vê (Conversations::PermissionFilterService); quem não vê
# a caixa recebe contagem nula, nunca zero. Na aba de Anúncios (#2199), o id da caixa vai só para quem vê a caixa ou pode
# reautorizá-la (integration_manage).
class SeusPosts::Caixa
  # viewer: o pundit_user do controller ({ user:, account:, account_user: }).
  def initialize(inbox:, viewer:)
    @inbox = inbox
    @viewer = viewer
  end

  def conversas(intervalo)
    return unless ve?

    Conversations::PermissionFilterService.new(@inbox.account.conversations, @viewer[:user], @inbox.account, for_reading: true).perform
                                          .where(inbox_id: @inbox.id, created_at: intervalo).count
  end

  def id_para_quem_age
    @inbox.id if ve? || @viewer[:account_user]&.permission_granted?('integration_manage')
  end

  def ve?
    Pundit.policy!(@viewer, @inbox).show?
  end
end
