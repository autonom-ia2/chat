# IA cuida dos comentários (#2212): o que acontece com um comentário novo num post ou anúncio de que a IA cuida.
#
# 1. Filtra o que não é dela: flag desligada, caixa de outra conta ou de outro canal, resposta a outro comentário, post
#    sem cuidado ou pausado, teto do dia atingido ou comentário com mais de 7 dias (o privado não sai mais).
# 2. Reivindica o comentário (Registro, `ai_seen`) ANTES do Jev: o webhook reenviado, ou outro job do mesmo comentário,
#    sai aqui sem gastar nada.
# 3. Lê o comentário na Meta (o evento leva só ids, #2327). Se a Meta diz que não dá (apagado, sem permissão), ele fica
#    descartado; se ela não responde, o job tenta de novo (CuidarJob, com teto).
#    Depois, pergunta ao Jev o que fazer (Classificador). Sem certeza, não faz nada: o comentário fica para a pessoa.
# 4. Faz:
#    - privado ou preço: manda o privado e põe o comentário no topo da conversa. Depois responde no comentário com a
#      frase da vez, ou com o preço, se a pessoa ligou essa chave. Privado recusado: nada em público, e a conversa fica
#      para a pessoa;
#    - reclamação: não responde, e a conversa abre urgente para a pessoa;
#    - propaganda: esconde;
#    - o resto: nada (a reivindicação já registra que a IA leu).
#    Sem oferta na ficha nem "para quem" do dono, ou na rede em que o privado ainda não está liberado (Facebook, F4),
#    nunca manda privado: a pergunta fica com o dono.
#
# Erro antes de a IA agir na Meta solta a reivindicação e sobe: o job tenta de novo. Depois de agir, a reivindicação
# fica, para o reenvio não mandar o privado de novo.
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
    cuidar if cuidar? && @registro.reservar!(@comentario)
  end

  private

  # Depois da reserva: um erro antes de agir na Meta solta a leitura, para o job tentar de novo. Depois de agir, não.
  # O comentário que a Meta diz que não dá para ler (apagado, sem permissão) fica com a reserva: descartado, não volta.
  def cuidar
    lido = rede.ler
    return descartar if lido.nil?

    @comentario = @comentario.lido(**lido)
    decisao = decidir
    executar(decisao) if decisao
  rescue StandardError
    soltar_leitura unless @agiu
    raise
  end

  # O privado só sai com o que mandar (oferta ou "para quem") e na rede que já o libera; senão, fica com o dono.
  def decidir
    decisao = classificador.decidir(@comentario.text)
    return decisao unless %w[private price].include?(decisao)

    care.privado? && rede.privado_disponivel? ? decisao : 'no_reply'
  end

  # Uma falha ao soltar não pode trocar o erro original: é ele que diz ao job se tenta de novo.
  def soltar_leitura
    @registro.soltar!(@comentario, Crm::MetaAds::ComentariosIa::Registro::LIDO)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Account.find_by(id: @comentario.account_id)).capture_exception
  end

  def descartar
    Rails.logger.info("[comentarios_ia] comentário não lido, descartado: account=#{@comentario.account_id} " \
                      "network=#{@comentario.network} comment=#{@comentario.comment_id}")
  end

  def cuidar?
    return false if inbox.nil? || @comentario.resposta? || care.nil? || rede.nil?
    return false unless inbox.account.feature_enabled?(FLAG)

    na_janela? && @registro.hoje(@comentario.account_id) < TETO_DIARIO
  end

  def na_janela?
    @comentario.momento.present? && @comentario.momento >= JANELA.ago
  end

  def executar(decisao)
    @agiu = %w[private price to_you hide].include?(decisao)
    case decisao
    when 'private', 'price' then privado(decisao)
    when 'to_you' then para_voce('to_you')
    when 'hide' then rede.esconder
    end
  end

  def privado(decisao)
    return if @conversa.ja_mandou?(@comentario)

    inicio = Time.current
    envio = rede.privado(care)
    return if envio.erro == Crm::MetaAds::ComentariosIa::Rede::JA_FEITO
    return para_voce('private_reply_failed') unless envio.ok

    na_conversa(envio.conversation, inicio)
    rede.responder(care.resposta_publica(decisao, @registro.vez(@comentario.account_id)))
  end

  # O comentário no topo da conversa do privado, e o id dela na linha do privado.
  def na_conversa(conversation, inicio)
    return if conversation.nil?

    @conversa.anotar!(conversation, @comentario, care, nova: conversation.created_at >= inicio)
    @registro.vincular!(@comentario, 'private_reply', conversation)
  end

  # Uma vez só por comentário: o `ai_seen` já deixou um job só cuidando dele.
  def para_voce(motivo)
    @registro.gravar!(@comentario, motivo, conversation: @conversa.para_voce!(@comentario, care, motivo))
  end

  def inbox
    return @inbox if defined?(@inbox)

    @inbox = Inbox.find_by(id: @comentario.inbox_id, account_id: @comentario.account_id)
  end

  def care
    @care ||= Crm::MetaAdsCommentCare.cuidando(account_id: @comentario.account_id, network: @comentario.network,
                                               post_id: @comentario.post_id, ad_id: @comentario.ad_id)
  end

  def classificador
    @classificador ||= Crm::MetaAds::ComentariosIa::Classificador.new(care: care)
  end

  def rede
    @rede ||= Crm::MetaAds::ComentariosIa::Rede.para(inbox, @comentario)
  end
end
