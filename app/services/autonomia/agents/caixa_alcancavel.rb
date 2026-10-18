# Regra G das funções personalizadas (#1784, lote 1 #1788): pôr ou tirar agente de IA de uma caixa exige alcançar a
# caixa — ser membro dela ou ter inbox_manage. O administrador sempre alcança (permission_granted? responde
# administrator? no OSS; o EE soma as chaves da função). Leitor único da regra: canais, "Onde atende" e Caixas no CRM.
class Autonomia::Agents::CaixaAlcancavel
  def initialize(account_user:)
    @account_user = account_user
  end

  def alcanca?(inbox)
    alcanca_id?(inbox.id)
  end

  def alcanca_id?(inbox_id)
    todas? || ids_das_caixas_dela.include?(inbox_id)
  end

  def filtrar(inboxes)
    todas? ? inboxes : inboxes.where(id: ids_das_caixas_dela.to_a)
  end

  private

  def todas?
    return @todas if defined?(@todas)

    @todas = @account_user.present? && @account_user.permission_granted?('inbox_manage')
  end

  def ids_das_caixas_dela
    @ids_das_caixas_dela ||= InboxMember.where(user_id: @account_user&.user_id)
                                        .joins(:inbox).where(inboxes: { account_id: @account_user&.account_id })
                                        .pluck(:inbox_id).to_set
  end
end
