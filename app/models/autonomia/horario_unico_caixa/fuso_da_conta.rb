# Com a flag `horario_unico_caixa`, a caixa segue o fuso da conta (#1619, decisão 2). Devolve o nome IANA, porque
# Inbox valida `timezone` contra TZInfo e a conta aceita também os nomes do Rails ("Brasilia"). Sem fuso válido na
# conta, vale a coluna. Conta em 'UTC' devolve 'Etc/UTC', o equivalente IANA (aceito na validação da caixa).
module Autonomia::HorarioUnicoCaixa::FusoDaConta
  def timezone
    return super unless Autonomia::HorarioUnicoCaixa.ligado?(account)

    account_zone = ActiveSupport::TimeZone[account.reporting_timezone.to_s]
    account_zone ? account_zone.tzinfo.name : super
  end
end
