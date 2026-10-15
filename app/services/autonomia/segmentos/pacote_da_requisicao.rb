# frozen_string_literal: true

# #1550 — requisição de conta (Api::V1::Accounts::BaseController) roda com o pacote de tradução da conta.
# Entra como o último around_action da base, depois de current_account e de switch_locale_using_account_locale.
module Autonomia::Segmentos::PacoteDaRequisicao
  def self.prepended(base)
    base.around_action :com_pacote_da_conta
  end

  private

  def com_pacote_da_conta(&)
    Autonomia::Segmentos::Pacotes.with(@current_account, &)
  end
end
