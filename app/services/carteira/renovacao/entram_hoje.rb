# Os seguros da conta que entram em renovação hoje (E5, #2898): ainda valem, terminam dentro dos dias que a conta
# escolheu e ainda não têm card. Fica de fora o cancelado, o que já tem desfecho (renovou ou não renovou) e o que já
# teve card de renovação nesta vigência. O dia de hoje é o da conta (Carteira::Selo.hoje).
#
# Um card por vigência, e a vigência é a linha: a renovação é outra apólice, que nasce sem nada disto e ganha o card
# dela. O card que saiu do quadro não volta, por nenhum dos dois caminhos do CRM:
# - arquivado ("apagar" no card e no lote, Crm::Cards::Archiver): o evento do card chega ao seguro e grava
#   `renovacao_card_removido_em` (Carteira::Renovacao::Desfecho);
# - excluído de vez (Crm::Cards::Excluidor): o banco anula `crm_card_id` sem passar pelo app, e nada daqui é avisado.
#   Quem conta é a história do seguro: o passo "card de renovação nasceu" fica, e seguro com esse passo e sem card é
#   seguro cujo card foi excluído. Vale para qualquer caminho que apague o card, sem tocar no CRM.
#
# O passo só impede enquanto o funil em que o card nasceu existir (`valores.funil`). Excluir um card é escolha de quem
# excluiu; o card que saiu junto com o funil apagado é efeito colateral, e a conta que escolhe outro funil vê as
# renovações em andamento nascerem nele. O funil arquivado continua existindo (pode ser restaurado) e não libera. O
# passo sem o funil guardado impede sempre.
#
# É a idempotência da rotina: quem já tem card não entra de novo, então rodar duas vezes no mesmo dia não cria card
# repetido. A leitura usa o índice [account_id, fim_vigencia] e anda em lotes pelo id, para a carteira grande não ir
# inteira para a memória.
class Carteira::Renovacao::EntramHoje
  LOTE = 500
  SEM_RENOVACAO = { cancelado_em: nil, crm_card_id: nil, renovacao_card_removido_em: nil, renovado_em: nil, nao_renovou_em: nil }.freeze
  DO_SEGURO = 'carteira_apolice_eventos.apolice_id = carteira_apolices.id'.freeze
  COM_O_FUNIL_DE_PE = "carteira_apolice_eventos.valores->>'funil' IS NULL OR EXISTS (SELECT 1 FROM crm_pipelines " \
                      "WHERE crm_pipelines.id = CAST(carteira_apolice_eventos.valores->>'funil' AS bigint))".freeze

  def initialize(account, dias_antes:)
    @account = account
    @dias_antes = dias_antes
  end

  def seguros
    hoje = Carteira::Selo.hoje(@account)
    Carteira::Apolice.where(account_id: @account.id, fim_vigencia: hoje..(hoje + @dias_antes)).where(SEM_RENOVACAO)
                     .where(self.class.cards_que_impedem.where(DO_SEGURO).arel.exists.not)
  end

  def cada(&)
    seguros.find_each(batch_size: LOTE, &)
  end

  # O seguro, relido sob a trava, ainda entra? (CriarCard confere de novo antes de criar.)
  def self.entra?(apolice)
    SEM_RENOVACAO.keys.all? { |coluna| apolice[coluna].nil? } && !cards_que_impedem.exists?(apolice_id: apolice.id)
  end

  # Os passos "card de renovação nasceu" (um por card criado, Carteira::Renovacao::CriarCard) que ainda impedem outro
  # card: os do funil que continua existindo.
  def self.cards_que_impedem
    Carteira::ApoliceEvento.where(tipo: Carteira::Renovacao::CriarCard::NASCEU).where(COM_O_FUNIL_DE_PE)
  end
end
