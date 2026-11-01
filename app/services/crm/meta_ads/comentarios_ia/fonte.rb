# IA cuida dos comentários (#2212, A2): de onde vêm os comentários que esperam o dono, num post do Seus posts ou num
# anúncio. Lê ao vivo pelos mesmos serviços das telas (F2 #2305 no post, #2196 e #2197 no anúncio), sem pessoa: nada
# do comentário é gravado (dado de terceiro).
#
# `ler` devolve `{ status:, linhas:, escondidas: }`. `status` é o da leitura ('ready', 'needs_permission' ou o erro da
# Meta). `linhas` são só os comentários de primeiro nível que esperam o dono: de outra pessoa, não escondidos, sem
# resposta da conta e sem privado, do mais novo para o mais velho. `escondidas` são os de outra pessoa que estão
# escondidos. Cada linha: `{ id:, network:, author:, text:, momento:, inbox_id:, post_id:, respostas: }` (a caixa e o
# post de onde veio, para o "Ler e mandar" cuidar dele como um comentário novo; `respostas`: as de outras pessoas dentro
# dele, `{ author:, text: }`, para a prévia, #2454). O anúncio que roda nas duas redes junta as listas.
#
# `respostas_que_esperam` (#2454, o fio conta): as respostas de outra pessoa dentro de um comentário (até dentro de um
# da própria conta) que esperam o dono: à mostra, com texto, sem privado e sem a conta responder no fio depois dela.
# Sem a hora de uma das duas, a resposta da conta conta como depois. Cada uma como as linhas, com `parent_id` (o
# comentário de cima) no lugar de `respostas`. Quem conta e cuida delas só com a flag da conversa: `que_esperam`.
#
# `legenda` (#2424): o texto do post, lido pela Rede como no motor, para a prévia decidir com o mesmo dado.
class Crm::MetaAds::ComentariosIa::Fonte
  SEM_PESSOA = ->(_inbox) { true }
  NAO_VE_CONVERSA = ->(_conversation) { false }
  SUMIU = { status: 'ad_not_found' }.freeze

  # O alvo só com ids (o que o Resumo e o LerAntigosJob recebem): `{ 'kind' => 'post', 'perfil' =>, 'post_id' => }` ou
  # `{ 'kind' => 'ad', 'ad_id' =>, 'networks' => [] }`. nil quando o perfil, a conexão ou o anúncio não existem mais.
  def self.do_alvo(account, alvo)
    alvo = alvo.to_h.stringify_keys
    if alvo['kind'] == 'post'
      canal = SeusPosts::Perfil.achar(account, alvo['perfil'].to_s)
      canal && post(canal, alvo['post_id'].to_s)
    else
      connection = Crm::MetaAdsConnection.find_by(account_id: account.id)
      lido = connection && Crm::MetaAds::ComentariosIa::Anuncio.ler(connection, alvo['ad_id'].to_s)
      lido && anuncio(lido, Array(alvo['networks']))
    end
  end

  # O que espera o dono, para contar e cuidar: os comentários de primeiro nível e, com a flag
  # meta_ads_comentarios_ia_conversa, também as respostas de cliente (#2454). Desligada, como antes.
  def self.que_esperam(account, lido)
    return lido[:linhas] unless account.feature_enabled?(Crm::MetaAds::ComentariosIa::Foto::FLAG)

    lido[:linhas] + Array(lido[:respostas_que_esperam])
  end

  def self.post(canal, post_id)
    leitor = if canal.is_a?(Channel::Instagram)
               SeusPosts::ComentariosInstagram.new(canal, can_manage: false, conversation_access: NAO_VE_CONVERSA)
             else
               SeusPosts::ComentariosPagina.new(canal, can_manage: false)
             end
    new({ SeusPosts::Perfil.rede(canal) => { ler: -> { leitor.payload(post_id) }, inbox_id: canal.inbox.id, post_id: post_id } })
  end

  # O anúncio (Anuncio) diz, por rede, o post do criativo e a caixa que recebe o comentário: o "Ler e mandar" põe cada
  # um na fila do motor com eles, como o webhook faria. Só as redes pedidas em que a IA ainda pode cuidar. Os leitores
  # recebem a AdManagement que já leu o anúncio: o criativo não é lido de novo na Meta.
  def self.anuncio(anuncio, networks)
    connection = anuncio.connection
    ad_id = anuncio.ad_id
    lido = { inbox_access: SEM_PESSOA, management: anuncio.management }
    leitores = {
      'instagram' => -> { Crm::MetaAds::InstagramComments.new(connection, **lido, can_manage: false).payload(ad_id) },
      'facebook' => -> { Crm::MetaAds::FacebookComments.new(connection, **lido).list(ad_id) }
    }
    redes = anuncio.redes.slice(*networks)
    new(redes.to_h { |network, rede| [network, { ler: leitores[network], inbox_id: rede[:inbox].id, post_id: rede[:post_id] }] })
  end

  def initialize(leituras)
    @leituras = leituras
  end

  # leituras: { rede => { ler: -> { payload da tela }, inbox_id:, post_id: } }.
  # Erro da Meta vira o status. AdManagement::Error cobre também o FacebookComments::Error (do anúncio e da Página do
  # Seus posts), que é filho dele. O leitor do Instagram devolve nil quando o anúncio sumiu da conta: `ad_not_found`.
  def ler
    lidas = ler_cada_rede
    falha = lidas.map { |_network, _leitura, payload| payload[:status] }.find { |status| status != 'ready' }
    return { status: falha, linhas: [], escondidas: [] } if falha

    linhas = lidas.flat_map { |network, leitura, payload| de_outra_pessoa(network, leitura, payload[:comments]) }
    respostas = lidas.flat_map { |network, leitura, payload| respostas_que_esperam(network, leitura, payload[:comments]) }
    { status: 'ready', linhas: so(linhas, :espera), escondidas: so(linhas, :escondida), respostas_que_esperam: mais_novos_antes(respostas) }
  rescue Crm::MetaAds::InstagramPrivateReply::Error, Crm::MetaAds::AdManagement::Error => e
    { status: e.code, linhas: [], escondidas: [] }
  end

  # A legenda do primeiro post (o anúncio nas duas redes é o mesmo criativo), ou nil. Na tela, a Meta fora do ar não
  # derruba a prévia: ela segue sem a legenda.
  def legenda
    rede = rede_do_post
    rede && Crm::MetaAds::ComentariosIa::Rede.para(*rede.values_at(:inbox, :comentario))&.legenda
  rescue Crm::MetaAds::ComentariosIa::Rede::Indisponivel
    nil
  end

  # "O que eu vi na foto" (#2454) do primeiro post, como a legenda: a Foto, que lê as imagens na Rede só quando ainda não
  # há leitura. nil sem caixa ou sem post.
  def foto
    rede = rede_do_post
    return if rede.nil?

    inbox, comentario = rede.values_at(:inbox, :comentario)
    Crm::MetaAds::ComentariosIa::Foto.new(account: inbox.account, network: comentario.network, post_id: comentario.post_id,
                                          imagens: -> { Crm::MetaAds::ComentariosIa::Rede.para(inbox, comentario)&.imagens || [] })
  end

  private

  # O primeiro post (o anúncio nas duas redes é o mesmo criativo): a caixa e um comentário só com ids, para a Rede.
  def rede_do_post
    network, leitura = @leituras.first
    inbox = leitura && Inbox.find_by(id: leitura[:inbox_id])
    return if inbox.nil? || leitura[:post_id].blank?

    comentario = Crm::MetaAds::ComentariosIa::Comentario.new(network: network, account_id: inbox.account_id, inbox_id: inbox.id,
                                                             post_id: leitura[:post_id])
    { inbox: inbox, comentario: comentario }
  end

  def ler_cada_rede
    @leituras.map { |network, leitura| [network, leitura, leitura[:ler].call || SUMIU] }
  end

  def de_outra_pessoa(network, leitura, comments)
    Array(comments).filter_map do |row|
      next if row.dig(:author, :is_page) || row[:text].blank?

      { id: row[:id], network: network, author: autor(row), text: row[:text].to_s, momento: momento(row[:created_time]),
        inbox_id: leitura[:inbox_id], post_id: leitura[:post_id], respostas: respostas(row), espera: espera?(row),
        escondida: row[:hidden] == true }
    end
  end

  def respostas(row)
    Array(row[:replies]).filter_map do |reply|
      next if reply.dig(:author, :is_page) || reply[:text].blank?

      { author: autor(reply), text: reply[:text].to_s }
    end
  end

  def respostas_que_esperam(network, leitura, comments)
    Array(comments).flat_map do |row|
      replies = Array(row[:replies])
      replies.filter_map do |reply|
        next unless resposta_espera?(reply, replies)

        { id: reply[:id], network: network, author: autor(reply), text: reply[:text].to_s, momento: momento(reply[:created_time]),
          inbox_id: leitura[:inbox_id], post_id: leitura[:post_id], parent_id: row[:id].to_s }
      end
    end
  end

  def resposta_espera?(reply, fio)
    return false if reply.dig(:author, :is_page) || reply[:text].blank? || reply[:hidden] || !reply[:private_reply].nil?

    fio.none? { |outra| outra.dig(:author, :is_page) && depois?(outra, reply) }
  end

  # A resposta da conta veio depois desta? Sem a hora de uma das duas, conta como depois: na dúvida, não insiste.
  def depois?(da_conta, reply)
    hora_da_conta = momento(da_conta[:created_time])
    hora = momento(reply[:created_time])
    hora_da_conta.nil? || hora.nil? || hora_da_conta >= hora
  end

  def espera?(row)
    !row[:hidden] && row[:private_reply].nil? && Array(row[:replies]).none? { |reply| reply.dig(:author, :is_page) }
  end

  def so(linhas, marca)
    mais_novos_antes(linhas.select { |linha| linha[marca] }.map { |linha| linha.except(:espera, :escondida) })
  end

  # Estável: com a mesma hora, fica a ordem da Meta.
  def mais_novos_antes(linhas)
    linhas.each_with_index.sort_by { |linha, indice| [-linha[:momento].to_f, indice] }.map(&:first)
  end

  def momento(valor)
    Time.zone.parse(valor.to_s)
  rescue ArgumentError
    nil
  end

  def autor(row)
    row.dig(:author, :username) || row.dig(:author, :name)
  end
end
