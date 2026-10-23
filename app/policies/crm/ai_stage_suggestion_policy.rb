class Crm::AiStageSuggestionPolicy < ApplicationPolicy
  # Ler a sugestão de etapa sem um card na mão (Crm::SugestaoDeEtapa, #2150): no OSS, como aceitar e dispensar, quem vê o
  # card. O Enterprise pede crm_manage_ai.
  def read?
    account_user.present?
  end

  def show?
    card_visible?
  end

  def accept?
    card_visible?
  end

  def dismiss?
    card_visible?
  end

  def evaluate?
    card_visible?
  end

  private

  def card_visible?
    Pundit.policy!(user_context, record.card).show?
  end
end

Crm::AiStageSuggestionPolicy.prepend_mod_with('Crm::AiStageSuggestionPolicy')
