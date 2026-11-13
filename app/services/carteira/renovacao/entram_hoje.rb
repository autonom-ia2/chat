# Os seguros da conta que entram em renovação hoje (E5, #2898): ainda valem, terminam dentro dos dias que a conta
# escolheu e ainda não têm card. Fica de fora o cancelado, o que já tem desfecho (renovou ou não renovou) e o que teve o
# card apagado de propósito nesta vigência. O dia de hoje é o da conta (Carteira::Selo.hoje).
#
# É a idempotência da rotina: quem já tem card não entra de novo, então rodar duas vezes no mesmo dia não cria card
# repetido. A leitura usa o índice [account_id, fim_vigencia] e anda em lotes pelo id, para a carteira grande não ir
# inteira para a memória.
class Carteira::Renovacao::EntramHoje
  LOTE = 500
  SEM_RENOVACAO = { cancelado_em: nil, crm_card_id: nil, renovacao_card_removido_em: nil, renovado_em: nil, nao_renovou_em: nil }.freeze

  def initialize(account, dias_antes:)
    @account = account
    @dias_antes = dias_antes
  end

  def seguros
    hoje = Carteira::Selo.hoje(@account)
    Carteira::Apolice.where(account_id: @account.id, fim_vigencia: hoje..(hoje + @dias_antes)).where(SEM_RENOVACAO)
  end

  def cada(&)
    seguros.find_each(batch_size: LOTE, &)
  end

  # O seguro, relido sob a trava, ainda entra? (CriarCard confere de novo antes de criar.)
  def self.entra?(apolice)
    SEM_RENOVACAO.keys.all? { |coluna| apolice[coluna].nil? }
  end
end
