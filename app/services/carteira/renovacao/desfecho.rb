# Como terminou a renovação, escrito no seguro (E5, #2898). É o único lugar que escreve `renovado_em`, `nao_renovou_em`
# e `renovacao_card_removido_em`: venha o desfecho do quadro (alguém fechou o card), da gaveta do seguro, da IA ou de
# uma automação, o caminho é o mesmo, pelo card (Carteira::RenovacaoListener).
#
# Não confia no nome do evento: lê como o card está agora e acerta o seguro por ele. Por isso rodar duas vezes, ou
# receber os eventos fora de ordem, dá no mesmo.
# - card ganho ou resolvido: o seguro renovou;
# - card perdido ou cancelado: não renovou (o motivo vem depois, de quem souber: #dizer_motivo);
# - card aberto de novo: o desfecho é desfeito e o seguro volta a "em renovação", com o passo `desfez_desfecho` na
#   história (quem desfez e, em `valores.anterior`, o que estava: `renovou` ou `nao_renovou`); o card restaurado do
#   arquivo volta a aparecer no seguro;
# - card arquivado sem desfecho: alguém tirou a renovação do quadro de propósito. O seguro guarda a data e a rotina não
#   cria outro card nesta vigência (Carteira::Renovacao::EntramHoje);
# - card arquivado depois de fechado: o desfecho que ele tinha continua valendo (Crm::Card.desfecho_de).
#
# O seguro fica travado e é relido sob a trava. O passo da história ("Renovou.", "Não renovou.") entra junto com a
# mudança, com quem fechou o card (nulo: a IA, uma automação ou o sistema).
class Carteira::Renovacao::Desfecho
  RENOVOU = %w[won resolved].freeze
  NAO_RENOVOU = %w[lost cancelled].freeze
  ABERTO = 'open'.freeze
  ARQUIVADO = 'archived'.freeze
  PASSO_RENOVOU = 'renovou'.freeze
  PASSO_NAO_RENOVOU = 'nao_renovou'.freeze
  PASSO_COM_MOTIVO_ESCRITO = 'nao_renovou_outro'.freeze
  PASSO_DESFEZ = 'desfez_desfecho'.freeze
  SEM_DESFECHO = { renovado_em: nil, nao_renovou_em: nil, motivo_nao_renovou: nil, motivo_escrito: nil,
                   renovacao_card_removido_em: nil }.freeze

  # O card mudou: acerta o seguro dele. Card que não é de seguro nenhum: nada.
  def self.do_card(card_id, user: nil)
    apolice = Carteira::Apolice.find_by(crm_card_id: card_id)
    new(apolice, user: user).acertar if apolice
  end

  def initialize(apolice, user: nil)
    @apolice = apolice
    @user = user
  end

  def acertar
    @apolice.with_lock do
      card = Crm::Card.find_by(id: @apolice.crm_card_id)
      acertar_pelo(Crm::Card.desfecho_de(card.status, card.desfecho_arquivado)) if card
    end
    @apolice
  end

  # O seguro que renovou sem card para fechar (a apólice nova chegou e ele não estava no quadro).
  def renovou_sem_card
    @apolice.with_lock { fechar(:renovado_em, PASSO_RENOVOU) }
    @apolice
  end

  # O motivo de não ter renovado, dito na gaveta: na hora de fechar ou depois, quando o card foi fechado no quadro sem
  # motivo. Fica no seguro e no passo "Não renovou" da história (o escrito à mão, com as palavras de quem escreveu).
  def dizer_motivo(motivo, escrito)
    @apolice.with_lock do
      next unless @apolice.nao_renovou_em

      @apolice.update!(motivo_nao_renovou: motivo, motivo_escrito: escrito)
      passo_de_nao_renovou&.update!(com_o_motivo(motivo, escrito))
    end
    @apolice
  end

  private

  def acertar_pelo(desfecho)
    if RENOVOU.include?(desfecho) then fechar(:renovado_em, PASSO_RENOVOU)
    elsif NAO_RENOVOU.include?(desfecho) then fechar(:nao_renovou_em, PASSO_NAO_RENOVOU)
    elsif desfecho == ABERTO then reabrir
    elsif desfecho == ARQUIVADO then tirar_do_quadro
    end
  end

  def fechar(coluna, passo)
    return if @apolice[coluna]

    agora = Time.current
    @apolice.update!(SEM_DESFECHO.merge(coluna => agora))
    @apolice.eventos.create!(tipo: passo, quando: agora, user: @user)
  end

  def passo_de_nao_renovou
    @apolice.eventos.where(tipo: [PASSO_NAO_RENOVOU, PASSO_COM_MOTIVO_ESCRITO]).order(quando: :desc, id: :desc).first
  end

  def com_o_motivo(motivo, escrito)
    return { tipo: PASSO_COM_MOTIVO_ESCRITO, valores: { texto: escrito } } if escrito

    { tipo: PASSO_NAO_RENOVOU, valores: { motivo: motivo }.compact }
  end

  def reabrir
    return if @apolice.slice(*SEM_DESFECHO.keys).values.all?(&:nil?)

    anterior = desfecho_de_agora
    @apolice.update!(SEM_DESFECHO)
    @apolice.eventos.create!(tipo: PASSO_DESFEZ, quando: Time.current, user: @user, valores: { anterior: anterior }) if anterior
  end

  def desfecho_de_agora
    return PASSO_RENOVOU if @apolice.renovado_em

    PASSO_NAO_RENOVOU if @apolice.nao_renovou_em
  end

  def tirar_do_quadro
    @apolice.update!(renovacao_card_removido_em: Time.current) unless @apolice.renovacao_card_removido_em
  end
end
