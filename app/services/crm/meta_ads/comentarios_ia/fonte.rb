# IA cuida dos comentários (#2212, A2): de onde vêm os comentários que esperam o dono, num post do Seus posts ou num
# anúncio. Lê ao vivo pelos mesmos serviços das telas (F2 #2305 no post, #2196 e #2197 no anúncio), sem pessoa: nada
# do comentário é gravado (dado de terceiro).
#
# `ler` devolve `{ status:, linhas:, escondidas: }`. `status` é o da leitura ('ready', 'needs_permission' ou o erro da
# Meta). `linhas` são só os comentários de primeiro nível que esperam o dono: de outra pessoa, não escondidos, sem
# resposta da conta e sem privado, do mais novo para o mais velho. `escondidas` são os de outra pessoa que estão
# escondidos. Cada linha: `{ id:, network:, author:, text:, momento:, inbox_id:, post_id: }` (a caixa e o post de onde
# veio, para o "Ler e mandar" cuidar dele como um comentário novo). O anúncio que roda nas duas redes junta as listas.
class Crm::MetaAds::ComentariosIa::Fonte
  SEM_PESSOA = ->(_inbox) { true }
  NAO_VE_CONVERSA = ->(_conversation) { false }

  # O alvo só com ids (o que o ResumoJob recebe): `{ 'kind' => 'post', 'perfil' =>, 'post_id' => }` ou
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

  def self.post(canal, post_id)
    leitor = if canal.is_a?(Channel::Instagram)
               SeusPosts::ComentariosInstagram.new(canal, can_manage: false, conversation_access: NAO_VE_CONVERSA)
             else
               SeusPosts::ComentariosPagina.new(canal, can_manage: false)
             end
    new({ SeusPosts::Perfil.rede(canal) => { ler: -> { leitor.payload(post_id) }, inbox_id: canal.inbox.id, post_id: post_id } })
  end

  # O anúncio (Anuncio) diz, por rede, o post do criativo e a caixa que recebe o comentário: o "Ler e mandar" põe cada
  # um na fila do motor com eles, como o webhook faria. Só as redes pedidas em que a IA ainda pode cuidar.
  def self.anuncio(anuncio, networks)
    connection = anuncio.connection
    ad_id = anuncio.ad_id
    leitores = {
      'instagram' => -> { Crm::MetaAds::InstagramComments.new(connection, inbox_access: SEM_PESSOA, can_manage: false).payload(ad_id) },
      'facebook' => -> { Crm::MetaAds::FacebookComments.new(connection, inbox_access: SEM_PESSOA).list(ad_id) }
    }
    redes = anuncio.redes.slice(*networks)
    new(redes.to_h { |network, rede| [network, { ler: leitores[network], inbox_id: rede[:inbox].id, post_id: rede[:post_id] }] })
  end

  def initialize(leituras)
    @leituras = leituras
  end

  # leituras: { rede => { ler: -> { payload da tela }, inbox_id:, post_id: } }.
  def ler
    lidas = @leituras.map { |network, leitura| [network, leitura, leitura[:ler].call] }
    falha = lidas.map { |_network, _leitura, payload| payload[:status] }.find { |status| status != 'ready' }
    return { status: falha, linhas: [], escondidas: [] } if falha

    linhas = lidas.flat_map { |network, leitura, payload| de_outra_pessoa(network, leitura, payload[:comments]) }
    { status: 'ready', linhas: so(linhas, :espera), escondidas: so(linhas, :escondida) }
  rescue Crm::MetaAds::InstagramPrivateReply::Error, Crm::MetaAds::AdManagement::Error => e
    { status: e.code, linhas: [], escondidas: [] }
  end

  private

  def de_outra_pessoa(network, leitura, comments)
    Array(comments).filter_map do |row|
      next if row.dig(:author, :is_page) || row[:text].blank?

      { id: row[:id], network: network, author: autor(row), text: row[:text].to_s, momento: momento(row[:created_time]),
        inbox_id: leitura[:inbox_id], post_id: leitura[:post_id], espera: espera?(row), escondida: row[:hidden] == true }
    end
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
