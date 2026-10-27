# IA cuida dos comentários (#2212): o que acontece com um comentário novo num post ou anúncio de que a IA cuida.
#
# 1. Filtra o que não é dela: flag desligada, caixa de outra conta ou de outro canal, resposta a outro comentário, post
#    sem cuidado ou pausado, teto do dia atingido ou comentário com mais de 7 dias (o privado não sai mais).
# 2. Reivindica o comentário (Registro, `ai_seen`) ANTES do Jev: o webhook reenviado, ou outro job do mesmo comentário,
#    sai aqui sem gastar nada.
# 3. Pergunta ao Jev o que fazer (Classificador). Sem certeza, não faz nada: o comentário fica para a pessoa.
# 4. Faz:
#    - privado ou preço: manda o privado e põe o comentário no topo da conversa. Depois responde no comentário com a
#      frase da vez, ou com o preço, se a pessoa ligou essa chave. Privado recusado: nada em público, e a conversa fica
#      para a pessoa;
#    - reclamação: não responde, e a conversa abre urgente para a pessoa;
#    - propaganda: esconde;
#    - o resto: nada (a reivindicação já registra que a IA leu).
#    Post sem oferta nunca manda privado.
class Crm::MetaAds::ComentariosIa::Cuidar
  FLAG = 'meta_ads_comentarios_ia'.freeze
  TETO_DIARIO = 200
  # Até quando o comentário aceita o Private Reply.
  JANELA = 7.days

  def initialize(comentario, rede: nil, classificador: nil, conversa: Crm::MetaAds::ComentariosIa::Conversa,
                 registro: Crm::MetaAds::ComentariosIa::Registro)
    @comentario = comentario
    @rede = rede
    @classificador = classificador
    @conversa = conversa
    @registro = registro
  end

  def call
    return unless cuidar? && @registro.reservar!(@comentario)

    decisao = classificador.decidir(@comentario.text)
    return if decisao.nil?

    decisao = 'no_reply' if %w[private price].include?(decisao) && !care.offer?
    executar(decisao)
  end

  private

  def cuidar?
    return false if inbox.nil? || @comentario.resposta? || care.nil? || rede.nil?
    return false unless inbox.account.feature_enabled?(FLAG)

    na_janela? && @registro.hoje(@comentario.account_id) < TETO_DIARIO
  end

  def na_janela?
    @comentario.momento.present? && @comentario.momento >= JANELA.ago
  end

  def executar(decisao)
    case decisao
    when 'private', 'price' then privado(decisao)
    when 'to_you' then para_voce('to_you')
    when 'hide' then rede.esconder
    end
  end

  def privado(decisao)
    envio = rede.privado(care)
    return if envio.erro == Crm::MetaAds::ComentariosIa::Rede::JA_FEITO
    return para_voce('private_reply_failed') unless envio.ok

    @conversa.anotar!(envio.conversation, @comentario, care)
    rede.responder(care.resposta_publica(decisao, @registro.vez(@comentario.account_id)))
  end

  # Reivindica antes de abrir a conversa: o mesmo comentário nunca abre duas.
  def para_voce(motivo)
    return unless @registro.reivindicar!(@comentario, motivo)

    @registro.vincular!(@comentario, motivo, @conversa.para_voce!(@comentario, care, motivo))
  end

  def inbox
    return @inbox if defined?(@inbox)

    @inbox = Inbox.find_by(id: @comentario.inbox_id, account_id: @comentario.account_id)
  end

  def care
    @care ||= Crm::MetaAdsCommentCare.cuidando(account_id: @comentario.account_id, post_id: @comentario.post_id,
                                               ad_id: @comentario.ad_id)
  end

  def classificador
    @classificador ||= Crm::MetaAds::ComentariosIa::Classificador.new(care: care)
  end

  def rede
    @rede ||= Crm::MetaAds::ComentariosIa::Rede.para(inbox, @comentario)
  end
end
