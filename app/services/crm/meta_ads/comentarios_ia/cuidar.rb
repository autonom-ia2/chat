# IA cuida dos comentários (#2212): o que acontece com um comentário novo num post ou anúncio de que a IA cuida.
#
# 1. Filtra o que não é dela: flag desligada, caixa de outra conta, resposta a outro comentário, post sem cuidado ou
#    pausado, comentário já cuidado (a Meta reenvia o webhook), teto do dia atingido ou comentário com mais de 7 dias
#    (o privado não sai mais).
# 2. Pergunta ao Jev o que fazer (Classificador). Sem certeza, não faz nada: o comentário fica para a pessoa.
# 3. Faz:
#    - privado ou preço: manda o privado e abre a conversa na caixa. Depois responde no comentário com a frase da vez,
#      ou com o preço, se a pessoa ligou essa chave. Privado recusado: nada em público, e a conversa fica para a pessoa;
#    - reclamação: não responde, e a conversa abre urgente para a pessoa;
#    - propaganda: esconde;
#    - o resto: só registra.
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
    return unless cuidar?

    decisao = classificador.decidir(@comentario.text)
    return if decisao.nil?

    decisao = 'no_reply' if %w[private price].include?(decisao) && !care.offer?
    executar(decisao)
  end

  private

  def cuidar?
    return false if inbox.nil? || @comentario.resposta? || care.nil?
    return false unless inbox.account.feature_enabled?(FLAG)

    na_janela? && !@registro.ja_cuidado?(@comentario) && @registro.hoje(@comentario.account_id) < TETO_DIARIO
  end

  def na_janela?
    @comentario.momento.present? && @comentario.momento >= JANELA.ago
  end

  def executar(decisao)
    case decisao
    when 'private', 'price' then privado(decisao)
    when 'to_you' then para_voce('to_you')
    when 'hide'
      @registro.gravar!(@comentario, 'hide') if rede.hide(@comentario.comment_id).ok
    else
      @registro.gravar!(@comentario, 'no_reply')
    end
  end

  def privado(decisao)
    envio = rede.private_reply(@comentario.comment_id, care.message, button: care.button)
    return para_voce('failed') unless envio.ok

    @registro.gravar!(@comentario, 'private_reply', conversation: @conversa.do_privado!(@comentario, care, envio))
    frase = care.resposta_publica(decisao, @registro.vez(@comentario))
    @registro.gravar!(@comentario, 'reply') if rede.reply(@comentario.comment_id, frase).ok
  end

  def para_voce(motivo)
    @registro.gravar!(@comentario, motivo, conversation: @conversa.para_voce!(@comentario, care, motivo))
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
    @rede ||= Crm::MetaAds::ComentariosIa::Rede.para(inbox)
  end
end
