# IA cuida dos comentários (#2212): o que acontece com um comentário novo num post ou anúncio de que a IA cuida.
#
# 1. Filtra o que não é dela: flag desligada, caixa de outra conta ou de outro canal, resposta a outro comentário, post
#    sem cuidado ou pausado, ou comentário com mais de 7 dias (o privado não sai mais).
# 2. Reivindica o comentário (Registro, `ai_seen`) ANTES do Jev: o webhook reenviado, ou outro job do mesmo comentário,
#    sai aqui sem gastar nada. O teto do dia é contado depois da reserva (ela conta), para a concorrência não passar
#    dele; passou, o comentário fica com o dono.
# 3. Lê o comentário na Meta (o evento leva só ids, #2327). Se a Meta diz que não dá (apagado, sem permissão), ele fica
#    descartado; se ela não responde, o job tenta de novo (CuidarJob, com teto).
#    Depois, pergunta ao Jev o que fazer (Classificador). Jev fora do ar: como a Meta, o job tenta de novo.
#    A IA que não cuidou (sem certeza, teto do dia, Jev barrado pelo teto ou pela flag) grava `ai_unread`: o comentário
#    fica com o dono, no "Esperando você", nunca some.
# 4. Faz:
#    - privado ou preço: reserva a pessoa no post (um privado por pessoa, antes da Meta), manda o privado e põe o
#      comentário no topo da conversa. Depois responde no comentário com a frase da vez, ou com o preço, se a pessoa
#      ligou essa chave. Privado recusado: a reserva da pessoa sai, nada em público, e a conversa fica para a pessoa.
#      Sem resposta da Meta (pode ter saído): a reserva fica, e a conversa vai para a pessoa conferir no direct;
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
    return nao_cuidou('teto') if @registro.hoje(@comentario.account_id) > TETO_DIARIO

    lido = rede.ler
    return descartar if lido.nil?

    @comentario = @comentario.lido(**lido)
    decisao = decidir
    decisao ? executar(decisao) : nao_cuidou('sem_certeza')
  rescue Crm::MetaAds::ComentariosIa::Classificador::Bloqueado => e
    nao_cuidou(e.code)
  rescue StandardError
    soltar_leitura unless @agiu
    raise
  end

  # O privado só sai com o que mandar (oferta ou "para quem") e na rede que já o libera; senão, fica com o dono.
  def decidir
    decisao = classificador.decidir!(@comentario.text)
    return decisao unless %w[private price].include?(decisao)

    care.privado? && rede.privado_disponivel? ? decisao : 'no_reply'
  end

  # Uma falha ao soltar não pode trocar o erro original: é ele que diz ao job se tenta de novo.
  def soltar_leitura
    @registro.soltar!(@comentario, Crm::MetaAds::ComentariosIa::Registro::LIDO)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: Account.find_by(id: @comentario.account_id)).capture_exception
  end

  # O comentário fica com o dono, com o porquê só no log (ids, nunca o texto).
  def nao_cuidou(motivo)
    Rails.logger.info("[comentarios_ia] não cuidou motivo=#{motivo} #{ids}")
    @registro.gravar!(@comentario, Crm::MetaAds::ComentariosIa::Registro::NAO_CUIDOU)
  end

  def ids
    "account=#{@comentario.account_id} network=#{@comentario.network} comment=#{@comentario.comment_id}"
  end

  def descartar
    Rails.logger.info("[comentarios_ia] comentário não lido, descartado: account=#{@comentario.account_id} " \
                      "network=#{@comentario.network} comment=#{@comentario.comment_id}")
  end

  def cuidar?
    return false if inbox.nil? || @comentario.resposta? || care.nil? || rede.nil?
    return false unless inbox.account.feature_enabled?(FLAG)

    na_janela?
  end

  def na_janela?
    @comentario.momento.present? && @comentario.momento >= JANELA.ago
  end

  def executar(decisao)
    @agiu = %w[private price to_you hide].include?(decisao)
    case decisao
    when 'private', 'price' then privado(decisao)
    when 'to_you' then para_voce('to_you')
    when 'hide' then esconder
    end
  end

  # Sem saber quem comentou, não dá para garantir um privado por pessoa: fica com o dono. A pessoa que já tem o privado
  # deste post (outro comentário dela) não recebe outro.
  def privado(decisao)
    return nao_cuidou('sem_quem_comentou') if @comentario.from_id.blank?
    return ja_tem_privado unless @registro.reservar_pessoa!(@comentario)

    inicio = Time.current
    envio = rede.privado(care)
    return nao_saiu(envio) unless envio.ok

    na_conversa(envio.conversation, inicio)
    recusou('reply') unless rede.responder(care.resposta_publica(decisao, @registro.vez(@comentario.account_id)))
  end

  # Já feito (pela pessoa, na tela do #2196, ou por outro job): nada a mostrar. Sem resposta da Meta, pode ter saído: a
  # reserva da pessoa fica. Recusa: a reserva sai.
  def nao_saiu(envio)
    return outro_envio if envio.erro == Crm::MetaAds::ComentariosIa::Rede::JA_FEITO
    return para_voce('private_reply_unsure') if envio.talvez_entregue

    @registro.soltar_pessoa!(@comentario)
    para_voce('private_reply_failed')
  end

  # O comentário no topo da conversa do privado, e o id dela na linha do privado. O privado já saiu: uma falha aqui vai
  # para o rastreador e não impede a resposta pública (a reserva da pessoa já marca o envio).
  def na_conversa(conversation, inicio)
    return Rails.logger.warn("[comentarios_ia] privado sem conversa gravada #{ids}") if conversation.nil?

    @conversa.anotar!(conversation, @comentario, care, nova: conversation.created_at >= inicio)
    @registro.vincular!(@comentario, 'private_reply', conversation)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception
  end

  def recusou(acao)
    Rails.logger.warn("[comentarios_ia] a Meta recusou #{acao} #{ids}")
  end

  # A Meta não escondeu: a propaganda segue no post, e o dono vê "não cuidei".
  def esconder
    return if rede.esconder

    recusou('hide')
    @registro.gravar!(@comentario, Crm::MetaAds::ComentariosIa::Registro::NAO_CUIDOU)
  end

  # Outro envio deste comentário (a pessoa na tela, ou outro job). Confirmado pela Meta: "já recebeu". Ainda saindo, ou
  # recusado depois: não dá para dizer que recebeu; a reserva da pessoa sai (quem enviar marca de novo) e fica com o
  # dono como "não cuidei".
  def outro_envio
    return ja_tem_privado if privado_confirmado?

    @registro.soltar_pessoa!(@comentario)
    nao_cuidou('outro_envio_sem_confirmacao')
  end

  def privado_confirmado?
    Crm::MetaAdsCommentAction.where(account_id: @comentario.account_id, network: @comentario.network, comment_id: @comentario.comment_id.to_s,
                                    action: 'private_reply').where.not(confirmed_at: nil).exists?
  end

  # O Painel mostra "já recebeu o privado" em vez de "não se aplica".
  def ja_tem_privado
    @registro.gravar!(@comentario, Crm::MetaAds::ComentariosIa::Registro::JA_TEM_PRIVADO)
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
