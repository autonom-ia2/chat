# Os seguros da conta que entram em renovação hoje (E5, #2898): ainda valem, terminam dentro dos dias que a conta
# escolheu e ainda não têm card. Fica de fora o cancelado, o que já tem desfecho (renovou ou não renovou) e o que já
# teve card de renovação nesta vigência. O dia de hoje é o da conta (Carteira::Selo.hoje).
#
# Um card por vigência, e a vigência é a linha: a renovação é outra apólice, que nasce sem nada disto e ganha o card
# dela. O card que saiu do quadro não volta, por nenhum dos dois caminhos do CRM:
# - arquivado ("apagar" no card e no lote, Crm::Cards::Archiver): o evento do card chega ao seguro e grava
#   `renovacao_card_removido_em` (Carteira::Renovacao::Desfecho);
# - excluído de vez (Crm::Cards::Excluidor, sozinho, com o funil ou com o contato): o banco anula `crm_card_id` sem
#   passar pelo app, e nada daqui é avisado. Quem conta é a história do seguro: o passo "card nasceu" fica, e seguro
#   com esse passo e sem card é seguro cujo card foi excluído. Vale para qualquer caminho que apague o card, inclusive
#   os que ainda não existem, sem tocar no CRM.
#
# É a idempotência da rotina: quem já tem card não entra de novo, então rodar duas vezes no mesmo dia não cria card
# repetido. A leitura usa o índice [account_id, fim_vigencia] e anda em lotes pelo id, para a carteira grande não ir
# inteira para a memória.
class Carteira::Renovacao::EntramHoje
  LOTE = 500
  SEM_RENOVACAO = { cancelado_em: nil, crm_card_id: nil, renovacao_card_removido_em: nil, renovado_em: nil, nao_renovou_em: nil }.freeze
  DO_SEGURO = 'carteira_apolice_eventos.apolice_id = carteira_apolices.id'.freeze

  def initialize(account, dias_antes:)
    @account = account
    @dias_antes = dias_antes
  end

  def seguros
    hoje = Carteira::Selo.hoje(@account)
    Carteira::Apolice.where(account_id: @account.id, fim_vigencia: hoje..(hoje + @dias_antes)).where(SEM_RENOVACAO)
                     .where(self.class.cards_que_nasceram.where(DO_SEGURO).arel.exists.not)
  end

  def cada(&)
    seguros.find_each(batch_size: LOTE, &)
  end

  # O seguro, relido sob a trava, ainda entra? (CriarCard confere de novo antes de criar.)
  def self.entra?(apolice)
    SEM_RENOVACAO.keys.all? { |coluna| apolice[coluna].nil? } && !cards_que_nasceram.exists?(apolice_id: apolice.id)
  end

  # Os passos "card nasceu" da história: um por card de renovação criado (Carteira::Renovacao::CriarCard).
  def self.cards_que_nasceram
    Carteira::ApoliceEvento.where(tipo: Carteira::Renovacao::CriarCard::NASCEU)
  end
end
