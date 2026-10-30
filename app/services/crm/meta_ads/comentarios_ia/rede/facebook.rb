# IA cuida dos comentários (#2212): as ações na Página do Facebook.
# - privado pelo Messenger: nosso (Rede::Pagina, com o token da caixa), com os estados do #2196: solta a reserva
#   abandonada, reserva, `attempt!` logo antes da chamada, `confirm!` quando a Meta aceita, e abre a conversa na caixa
#   do Messenger com a mensagem que saiu (Conversa.no_messenger!). Recusado (4xx), a linha sai; sem resposta ou 5xx, a
#   Meta pode ter entregado: a linha fica sem confirmação e travada;
# - leitura, resposta e esconder: Crm::MetaAds::FacebookComments do #2197, com a conexão de anúncios da conta. Ele
#   confere que o comentário é do post e que a Página é da conta (leitura) ou tem a caixa do Messenger nela (ações), e
#   grava a ação com actor 'ai'. Aqui não há pessoa abrindo a tela: a IA age pela caixa da Página, sem conferir quem a vê.
class Crm::MetaAds::ComentariosIa::Rede::Facebook
  TENTA_DE_NOVO = %w[meta_unavailable needs_login].freeze
  REGISTRO = Crm::MetaAds::ComentariosIa::Registro
  SEM_PESSOA = ->(_inbox) { true }

  def initialize(inbox, comentario)
    @inbox = inbox
    @comentario = comentario
  end

  # O privado pelo Messenger depende da `pages_messaging`, que a Meta ainda não aprovou para o app (F4 do Seus posts).
  # Até lá, no Facebook a IA esconde propaganda e passa reclamação; a pergunta fica com o dono (`kept_for_owner`). A
  # frase pública só acompanha o privado, então também não sai.
  def privado_disponivel?
    false
  end

  def privado(care)
    reivindicacao = reivindicar
    # Sem a linha, ou com o envio dela já saindo em outra requisição: o privado não sai duas vezes.
    return Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: Crm::MetaAds::ComentariosIa::Rede::JA_FEITO) unless enviando?(reivindicacao)

    envio = Crm::MetaAds::ComentariosIa::Rede::Pagina.new(@inbox.channel).private_reply(@comentario.comment_id, mensagem(care))
    return falhou(envio) unless envio.ok

    reivindicacao.confirm!
    envio.conversation = na_caixa(envio, care)
    envio
  end

  def ler
    dados = comentarios&.comment(@comentario.post_id, @comentario.comment_id)
    dados && { text: dados['message'], from_name: dados.dig('from', 'name'), from_id: dados.dig('from', 'id')&.to_s }
  # Como no Instagram: Meta fora do ar, login caído ou permissão tirada tentam de novo (um problema da Página não
  # descarta os comentários um a um; esgotado, o CuidarJob deixa o comentário com o dono). O resto é descartado.
  rescue Crm::MetaAds::FacebookComments::Error => e
    raise Crm::MetaAds::ComentariosIa::Rede::Indisponivel if TENTA_DE_NOVO.include?(e.code)

    nil
  end

  def responder(texto)
    comentarios&.reply_as_ai(@comentario.post_id, @comentario.comment_id, texto).present?
  rescue Crm::MetaAds::FacebookComments::Error
    false
  end

  def esconder
    comentarios&.hide_as_ai(@comentario.post_id, @comentario.comment_id, true) == true
  rescue Crm::MetaAds::FacebookComments::Error
    false
  end

  private

  # O privado já saiu: uma falha ao abrir a conversa não pode soltar a reivindicação (o reenvio mandaria de novo).
  def na_caixa(envio, care)
    Crm::MetaAds::ComentariosIa::Conversa.no_messenger!(@comentario, envio, care.texto_do_privado)
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
    REGISTRO.soltar!(@comentario, 'private_reply') unless envio.talvez_entregue
    envio
  end

  def mensagem(care)
    button = care.button
    return { text: care.texto_do_privado } if button.blank?

    { attachment: { type: 'template', payload: { template_type: 'button', text: care.texto_do_privado,
                                                 buttons: [{ type: 'web_url', url: button['url'], title: button['title'] }] } } }
  end

  def comentarios
    conexao = Crm::MetaAdsConnection.find_by(account_id: @comentario.account_id)
    conexao && Crm::MetaAds::FacebookComments.new(conexao, inbox_access: SEM_PESSOA)
  end
end
