# Rascunho da "Nova campanha" (#1898). Ver e abrir: quem vê campanhas. Montar e mudar: quem gerencia campanhas.
# Apagar: o autor que ainda gerencia campanhas, ou quem dispara campanhas (`campaign_send`, chave do lote 8 do #1784,
# a entrar em CustomRole::PERMISSIONS; no OSS e antes dela, só o administrador).
class CampaignJourneyDraftPolicy < ApplicationPolicy
  def index?
    @account_user.permission_granted?('campaign_view')
  end

  def show?
    index?
  end

  def create?
    @account_user.permission_granted?('campaign_manage')
  end

  def update?
    create?
  end

  def destroy?
    (author? && create?) || @account_user.permission_granted?('campaign_send')
  end

  private

  def author?
    @record.is_a?(CampaignJourneyDraft) && @record.user_id.present? && @record.user_id == @user.id
  end
end
