# frozen_string_literal: true

# #1550 — e-mail (ApplicationMailer) sai com o pacote de tradução da conta. Entra depois do before_action que
# atribui Current.account e do around_action :switch_locale.
module Autonomia::Segmentos::PacoteDoEmail
  def self.prepended(base)
    base.around_action :com_pacote_da_conta
  end

  private

  def com_pacote_da_conta(&)
    Autonomia::Segmentos::Pacotes.with(Current.account, &)
  end
end
