# IA cuida dos comentários (#2212): as ações na Página do Facebook.
# - privado pelo Messenger: nosso (Rede::Pagina, com o token da caixa), com os estados do #2196: solta a reserva
#   abandonada, reserva, `attempt!` logo antes da chamada, `confirm!` quando a Meta aceita, e abre a conversa na caixa
#   do Messenger com a mensagem que saiu (Conversa.no_messenger!). Recusado (4xx), a linha sai; sem resposta ou 5xx, a
#   Meta pode ter entregado: a linha fica sem confirmação e travada. Na resposta a comentário (2º nível, #2454), nada
#   recusa antes da Meta, e o resultado fica gravado como no Instagram (meta_message_id, ou a recusa com o código);
# - leitura, resposta e esconder (#2587): Rede::ComentariosDaPagina, com o token da caixa da Página, em post e em
#   anúncio, sem a conexão de Anúncios (antes, sem ela, o comentário era descartado). Ele confere que o comentário é do
#   post e que o post é desta Página, e grava a ação com actor 'ai'. Aqui não há pessoa abrindo a tela: a IA age pela
#   caixa da Página, sem conferir quem a vê.
class Crm::MetaAds::ComentariosIa::Rede::Facebook
  TENTA_DE_NOVO = %w[meta_unavailable needs_login].freeze
  REGISTRO = Crm::MetaAds::ComentariosIa::Registro

  def initialize(inbox, comentario)
    @inbox = inbox
    @comentario = comentario
  end

  # O privado pelo Messenger depende da `pages_messaging`: só na conta com a flag (Rede.privado_liberado?, #2613). Sem
  # ela, no Facebook a IA esconde propaganda e passa reclamação; a pergunta fica com o dono (`kept_for_owner`). A frase
  # pública só acompanha o privado, então também não sai.
  def privado_disponivel?
    Crm::MetaAds::ComentariosIa::Rede.privado_liberado?(@inbox.account, 'facebook')
  end

  # texto: a mensagem escrita pela IA para este comentário (#2458); sem ela, a do dono. O botão do dono vai junto.
  def privado(care, texto: nil)
    reivindicacao = reivindicar
    # Sem a linha, ou com o envio dela já saindo em outra requisição: o privado não sai duas vezes.
    return Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: Crm::MetaAds::ComentariosIa::Rede::JA_FEITO) unless enviando?(reivindicacao)

    texto ||= care.texto_do_privado
    envio = Crm::MetaAds::ComentariosIa::Rede::Pagina.new(@inbox.channel).private_reply(@comentario.comment_id, mensagem(care, texto))
    return falhou(envio) unless envio.ok

    reivindicacao.confirm!
    aceito_em_resposta(reivindicacao, envio)
    envio.conversation = na_caixa(envio, texto)
    envio
  end

  def ler
    dados = comentarios.comment(@comentario.post_id, @comentario.comment_id)
    dados && { text: dados['message'], from_name: dados.dig('from', 'name'), from_id: dados.dig('from', 'id')&.to_s }
  # Como no Instagram: Meta fora do ar, login caído ou permissão tirada tentam de novo (um problema da Página não
  # descarta os comentários um a um; esgotado, o CuidarJob deixa o comentário com o dono). O resto é descartado.
  rescue Crm::MetaAds::FacebookComments::Error => e
    nao_lido!(e, 'comentário')
  end

  # O texto do comentário que esta resposta responde (#2454), ou nil (primeiro nível, ou o de cima que não dá para ler).
  # As mesmas regras do `ler`.
  # Lido uma vez por comentário (#2458): o Classificador e a Escrita leem o mesmo.
  def ler_pai
    return @ler_pai if defined?(@ler_pai)
    return if @comentario.parent_id.blank?

    @ler_pai = comentarios.comment(@comentario.post_id, @comentario.parent_id)&.dig('message')
  rescue Crm::MetaAds::FacebookComments::Error => e
    nao_lido!(e, 'comentário de cima')
  end

  # O texto do post (#2424), ou nil. As mesmas regras do `ler`. Lido uma vez por comentário (#2458).
  def legenda
    return @legenda if defined?(@legenda)

    @legenda = @comentario.post_id.present? ? comentarios.post_message(@comentario.post_id) : nil
  rescue Crm::MetaAds::FacebookComments::Error => e
    nao_lido!(e, 'post')
  end

  # As imagens do post (#2454), pelos anexos (Imagens). As mesmas regras da `legenda`; sem nada, nenhuma. prazo: segundos
  # para todas as idas à Graph desta leitura (a leitura da foto roda dentro da requisição); passou dele, Indisponivel.
  def imagens(prazo: nil)
    limite = prazo && (Process.clock_gettime(Process::CLOCK_MONOTONIC) + prazo)
    dados = @comentario.post_id.present? ? comentarios(prazo: limite).post_media(@comentario.post_id) : nil
    Crm::MetaAds::ComentariosIa::Imagens.do_facebook(dados.to_h)
  rescue Crm::MetaAds::FacebookComments::Error => e
    nao_lido!(e, 'imagens do post')
    []
  end

  def responder(texto)
    comentarios.reply_as_ai(@comentario.post_id, @comentario.comment_id, texto).present?
  rescue Crm::MetaAds::FacebookComments::Error
    false
  end

  def esconder
    comentarios.hide_as_ai(@comentario.post_id, @comentario.comment_id, true) == true
  rescue Crm::MetaAds::FacebookComments::Error
    false
  end

  private

  # Meta fora do ar, login caído ou permissão tirada: Indisponivel, para o job tentar de novo. O resto (comentário de
  # outro post ou de outra Página, recusa da Meta) não volta: fica no log, só com ids e o código, e a leitura dá nil.
  def nao_lido!(error, what)
    raise Crm::MetaAds::ComentariosIa::Rede::Indisponivel if TENTA_DE_NOVO.include?(error.code)

    Rails.logger.warn("[meta_ads] #{what} do Facebook não lido: #{error.code} account=#{@comentario.account_id} " \
                      "post=#{@comentario.post_id} comment=#{@comentario.comment_id}")
    nil
  end

  # O privado já saiu: uma falha ao abrir a conversa não pode soltar a reivindicação (o reenvio mandaria de novo).
  def na_caixa(envio, texto)
    Crm::MetaAds::ComentariosIa::Conversa.no_messenger!(@comentario, envio, texto)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception
    nil
  end

  def enviando?(reivindicacao)
    reivindicacao.present? && reivindicacao.attempt!
  end

  def reivindicar
    REGISTRO.soltar_abandonada!(@comentario)
    REGISTRO.reivindicar!(@comentario, 'private_reply')
  end

  def falhou(envio)
    return envio if envio.talvez_entregue

    REGISTRO.soltar!(@comentario, 'private_reply')
    # Como o motor: só a recusa com código da Meta fica gravada.
    REGISTRO.recusa_do_privado!(@comentario, codigo: envio.codigo, subcodigo: envio.subcodigo) if @comentario.resposta? && envio.codigo
    envio
  end

  # O resultado do privado em resposta (2º nível, #2454), como no InstagramPrivateReply. Só registro: o privado já saiu,
  # e uma falha ao gravar vai para o rastreador.
  def aceito_em_resposta(reivindicacao, envio)
    reivindicacao.update!(meta_message_id: envio.message_id) if @comentario.resposta?
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @inbox.account).capture_exception
  end

  def mensagem(care, texto)
    button = care.button
    return { text: texto } if button.blank?

    { attachment: { type: 'template', payload: { template_type: 'button', text: texto,
                                                 buttons: [{ type: 'web_url', url: button['url'], title: button['title'] }] } } }
  end

  def comentarios(prazo: nil)
    Crm::MetaAds::ComentariosIa::Rede::ComentariosDaPagina.new(@inbox.channel, prazo: prazo)
  end
end
