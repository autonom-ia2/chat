# IA cuida dos comentários (#2212): o que acontece com um comentário novo num post ou anúncio de que a IA cuida.
#
# 1. Filtra o que não é dela: flag desligada, caixa de outra conta ou de outro canal, resposta a outro comentário, post
#    sem cuidado ou pausado, ou comentário com mais de 7 dias (o privado não sai mais).
#    Com a flag meta_ads_comentarios_ia (#2454), a resposta dentro de um comentário entra: a de cliente é
#    decidida como um comentário próprio, com o de cima (lido na Meta pelo id, Rede#ler_pai) à parte, como contexto. A
#    da própria conta (o perfil ou a Página, inclusive a frase pública que a IA posta) nunca entra. O privado para
#    resposta vai à Meta, que decide (o teste real é do próprio produto, na conta piloto). A recusa dela com código é
#    final: a pessoa recebe só a frase pública que não promete o privado (o preço, se o dono ligou essa chave); sem ela,
#    o comentário fica com o dono. A recusa, com o código e o subcódigo, fica gravada pela Rede.
# 2. Reivindica o comentário (Registro, `ai_seen`) ANTES da IA: o webhook reenviado, ou outro job do mesmo comentário,
#    sai aqui sem gastar nada. Não há teto de uso (decisão do Rodrigo, #2454): as guardas são contra defeito, não
#    contra uso — o mesmo comentário não é decidido duas vezes (esta reserva) e um privado por pessoa em cada post
#    (a reserva da pessoa, no passo 4).
# 3. Lê o comentário na Meta (o evento leva só ids, #2327). Se a Meta diz que não dá (apagado, sem permissão), ele fica
#    descartado; se ela não responde, o job tenta de novo (CuidarJob, com teto).
#    Depois, pergunta à IA o que fazer (Classificador), com a legenda do post. IA fora do ar, ou a legenda sem resposta
#    da Meta: o job tenta de novo. Sem a legenda, "quanto custa esse?" pode ser decidido errado, e o motor não manda
#    privado no escuro; esgotadas as tentativas, o comentário fica com o dono. O que a IA escolheu, a certeza e o motivo
#    ficam na linha `ai_seen` (#2424), também quando ela age.
#    A IA que não cuidou (sem certeza, IA barrada pela flag ou sem chave) grava `ai_unread`: o comentário
#    fica com o dono, no "Esperando você", nunca some.
# 4. Faz:
#    - privado ou preço: reserva a pessoa no post (um privado por pessoa, antes da Meta), manda o privado e põe o
#      comentário no topo da conversa. Depois responde no comentário com a frase da vez, ou com o preço, se a pessoa
#      ligou essa chave. Privado recusado: a reserva da pessoa sai, nada em público, e a conversa fica para a pessoa.
#      Sem resposta da Meta (pode ter saído): a reserva fica, e a conversa vai para a pessoa conferir no direct;
#    - reclamação: não responde, e a conversa abre urgente para a pessoa;
#    - propaganda: esconde;
#    - o resto: nada (a reivindicação já registra que a IA leu).
#    - #2458: a frase do comentário e a do privado são escritas pela IA
#      para este comentário (Escrita), as duas ANTES de qualquer envio. O que o agente não sabe, e o comentário sobre o
#      assunto proibido do dono (`owner_topic`), ficam com o dono (`kept_for_owner`). O preço que o dono escreveu vale
#      no lugar da frase escrita. Sem agente que possa escrever, as frases fixas (o motivo vai ao log).
#    Sem oferta na ficha nem "para quem" do dono, ou na rede em que o privado ainda não está liberado (Facebook, F4),
#    nunca manda privado: a pergunta fica com o dono (`kept_for_owner`, "Esperando você" no Painel).
#
# Erro antes de a IA agir na Meta solta a reivindicação e sobe: o job tenta de novo. Depois de agir, a reivindicação
# fica, para o reenvio não mandar o privado de novo.
class Crm::MetaAds::ComentariosIa::Cuidar # rubocop:disable Metrics/ClassLength -- no teto antes do #2458; a escrita fica entre a reserva e o envio
  FLAG = 'meta_ads_comentarios_ia'.freeze
  # Até quando o comentário aceita o Private Reply.
  JANELA = 7.days
  # Era o caso do privado, mas ele não sai aqui (sem o que mandar, ou a rede ainda não o libera).
  FICA_COM_O_DONO = 'kept_for_owner'.freeze

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
    return da_conta_na_leitura if da_conta?

    decisao = decidir
    decisao ? executar(decisao) : nao_cuidou('sem_certeza')
  rescue Crm::MetaAds::ComentariosIa::Classificador::Bloqueado => e
    nao_cuidou(e.code)
  rescue StandardError
    soltar_leitura unless @agiu
    raise
  end

  # O privado só sai com o que mandar (oferta ou "para quem") e na rede que já o libera; senão, a pergunta fica com o
  # dono (FICA_COM_O_DONO: o Painel a mostra em "Esperando você", não como "não se aplica").
  def decidir
    avaliacao = avaliar
    @registro.decisao!(@comentario, avaliacao) if avaliacao
    decisao = avaliacao&.chave
    return decisao unless %w[private price].include?(decisao)

    care.privado? && rede.privado_disponivel? ? decisao : FICA_COM_O_DONO
  end

  # Na resposta, o comentário de cima vai à IA à parte (Classificador, `parent_comment`).
  def avaliar
    return classificador.avaliar!(@comentario.text) unless @comentario.resposta?

    classificador.avaliar!(@comentario.text, pai: rede.ler_pai)
  end

  # O autor só veio na leitura (comentário da lista) e é a própria conta: a leitura sai, e nada fica gravado.
  def da_conta_na_leitura
    Rails.logger.info("[comentarios_ia] comentário da própria conta ignorado #{ids}")
    soltar_leitura
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
    return false if inbox.nil? || !do_motor? || care.nil? || rede.nil?
    return false unless inbox.account.feature_enabled?(FLAG)

    na_janela?
  end

  # O comentário de primeiro nível e a resposta dentro dele (#2454), nunca o da própria conta.
  def do_motor?
    !da_conta?
  end

  # O perfil ou a Página da própria conta (o dono do evento ou o da caixa): a frase pública que a IA posta, ou a
  # resposta do dono, não volta para ela.
  def da_conta?
    autor = @comentario.from_id.to_s
    return false if autor.blank?

    [@comentario.owner_id, inbox.channel.try(:instagram_id), inbox.channel.try(:page_id)].compact.map(&:to_s).include?(autor)
  end

  def na_janela?
    @comentario.momento.present? && @comentario.momento >= JANELA.ago
  end

  # `@agiu` marca o ponto sem volta: daqui em diante algo já saiu (Meta chamada, conversa aberta), e um erro não solta a
  # leitura. Antes dele (reserva da pessoa, por exemplo), o erro solta, e o job tenta de novo.
  def executar(decisao)
    case decisao
    when 'private', 'price' then privado(decisao)
    when 'to_you' then agir { para_voce('to_you') }
    when 'hide' then esconder
    when FICA_COM_O_DONO, Crm::MetaAds::ComentariosIa::Classificador::DONO then @registro.gravar!(@comentario, FICA_COM_O_DONO)
    end
  end

  def agir
    @agiu = true
    yield
  end

  # Sem saber quem comentou, não dá para garantir um privado por pessoa: fica com o dono. A pessoa que já tem o privado
  # deste post (outro comentário dela) não recebe outro.
  def privado(decisao)
    return nao_cuidou('sem_quem_comentou') if @comentario.from_id.blank? || @comentario.post_id.blank?

    return ja_tem_privado unless @registro.reservar_pessoa!(@comentario)

    textos = textos_reservados(decisao)
    # O agente não soube escrever: fica com o dono, no "Esperando você".
    return @registro.gravar!(@comentario, FICA_COM_O_DONO) if textos.key?(:dono)

    inicio = Time.current
    envio = agir { rede.privado(care, texto: textos[:privado]) }
    return nao_saiu(envio, decisao) unless envio.ok

    na_conversa(envio.conversation, inicio)
    responder(decisao, textos[:publico])
  end

  # #2458: com a escrita ligada, a mensagem do privado e a frase do comentário escritas pela IA (Escrita#textos), as duas
  # antes de qualquer envio e depois da reserva da pessoa: quem já tem o privado deste post não gasta IA. Nada saiu
  # (fica com o dono, ou a IA fora do ar): a reserva sai.
  def textos_reservados(decisao)
    return {} unless Crm::MetaAds::ComentariosIa::Escrita.ligada?(inbox.account)

    textos = textos_escritos(decisao)
    @registro.soltar_pessoa!(@comentario) if textos.key?(:dono)
    textos
  rescue Crm::MetaAds::ComentariosIa::Classificador::Erro
    @registro.soltar_pessoa!(@comentario)
    raise
  end

  def textos_escritos(decisao)
    Crm::MetaAds::ComentariosIa::Escrita.new(care: care, inbox: inbox, legenda: rede.legenda, foto: texto_da_foto)
                                        .textos(decisao, comentario: @comentario.text, pai: rede.ler_pai)
  end

  # A frase pública depois do privado (a escrita pela IA, ou a do dono). A Meta recusou: o dono vê "não cuidei" e
  # responde ele.
  def responder(decisao, escrita = nil)
    return if rede.responder(escrita || care.resposta_publica(decisao, @registro.vez(@comentario.account_id)))

    recusou('reply')
    @registro.gravar!(@comentario, Crm::MetaAds::ComentariosIa::Registro::NAO_CUIDOU)
  end

  # Já feito (pela pessoa, na tela do #2196, ou por outro job): nada a mostrar. Sem resposta da Meta, pode ter saído: a
  # reserva da pessoa fica. Recusa: a reserva sai.
  def nao_saiu(envio, decisao)
    return outro_envio if envio.erro == Crm::MetaAds::ComentariosIa::Rede::JA_FEITO
    return para_voce('private_reply_unsure') if envio.talvez_entregue

    return limite_em_resposta(envio) if @comentario.resposta? && Crm::MetaAds::ComentariosIa::LimiteDaMeta.do_envio?(envio)

    @registro.soltar_pessoa!(@comentario)
    return recusado_em_resposta(envio, decisao) if @comentario.resposta? && envio.codigo.present?

    para_voce('private_reply_failed')
  end

  # #2454: limite de chamadas da Meta no privado em resposta não é recusa. A leitura sai (para o job poder cuidar de
  # novo) e o erro sobe como passageiro: o CuidarJob tenta mais tarde. A pessoa fica reservada para este comentário
  # (Registro#reservar_pessoa! reconhece a dele), e nada é decidido pelo dono.
  def limite_em_resposta(envio)
    Rails.logger.info("[comentarios_ia] limite da Meta no privado em resposta codigo=#{envio.codigo} http=#{envio.http} #{ids}")
    soltar_leitura
    raise Crm::MetaAds::ComentariosIa::Rede::Indisponivel
  end

  # #2454: a Meta recusou o privado na resposta (2º nível), com código. É final: não volta para a fila. A pessoa recebe
  # só a frase pública que não promete o privado (o preço, se o dono ligou essa chave); sem ela, fica com o dono. A
  # recusa, com o código e o subcódigo, já ficou gravada pela Rede; aqui o motivo vai ao log, só com ids e códigos.
  def recusado_em_resposta(envio, decisao)
    Rails.logger.info("[comentarios_ia] privado em resposta recusado codigo=#{envio.codigo} subcodigo=#{envio.subcodigo} #{ids}")
    frase = care.price_reply.presence if decisao == 'price'
    return @registro.gravar!(@comentario, FICA_COM_O_DONO) if frase.nil?
    return if rede.responder(frase)

    recusou('reply')
    @registro.gravar!(@comentario, Crm::MetaAds::ComentariosIa::Registro::NAO_CUIDOU)
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
    return if agir { rede.esconder }

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
    @classificador ||= Crm::MetaAds::ComentariosIa::Classificador.new(care: care, legenda: rede.legenda, foto: texto_da_foto)
  end

  # O que a foto do post mostra (#2454), lido do banco: a leitura é feita no passo 1 da tela, nunca aqui.
  def texto_da_foto
    Crm::MetaAds::ComentariosIa::Foto.texto_para_ia(inbox.account, @comentario.network, @comentario.post_id)
  end

  def rede
    @rede ||= Crm::MetaAds::ComentariosIa::Rede.para(inbox, @comentario)
  end
end
