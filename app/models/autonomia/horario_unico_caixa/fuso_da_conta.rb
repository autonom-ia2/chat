# Com a flag `horario_unico_caixa`, a caixa segue o fuso da conta (#1619, decisão 2). O fuso da conta é o mesmo que o
# CRM e o painel usam: `reporting_timezone` válido (que `Account#sync_reporting_timezone` copia de
# custom_attributes['timezone']), senão o padrão `Crm::Timezone::Resolver.default_timezone`, o mesmo valor que o
# painel recebe em CRM_DEFAULT_TIMEZONE. Nunca a coluna da caixa, para o painel e o servidor não divergirem numa conta
# sem fuso. Devolve o nome IANA, porque Inbox valida `timezone` contra TZInfo e a conta aceita também os nomes do Rails
# ("Brasilia"); conta em 'UTC' devolve 'Etc/UTC', o equivalente IANA (aceito na validação da caixa).
module Autonomia::HorarioUnicoCaixa::FusoDaConta
  def timezone
    return super unless Autonomia::HorarioUnicoCaixa.ligado?(account)

    ActiveSupport::TimeZone[Crm::Timezone::Resolver.new(account: account).name_or_default].tzinfo.name
  end
end
