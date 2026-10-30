# IA cuida dos comentários (#2212, A2): de onde vêm os comentários que esperam o dono, num post do Seus posts ou num
# anúncio. Lê ao vivo pelos mesmos serviços das telas (F2 #2305 no post, #2196 e #2197 no anúncio), sem pessoa: nada
# do comentário é gravado (dado de terceiro).
#
# `ler` devolve `{ status:, linhas: }`. `status` é o da leitura ('ready', 'needs_permission' ou o erro da Meta) e
# `linhas` são só os comentários de primeiro nível que esperam o dono: de outra pessoa, não escondidos, sem resposta da
# conta e sem privado, do mais novo para o mais velho. Cada linha: `{ id:, network:, author:, text:, momento: }`. O
# anúncio que roda nas duas redes junta as duas listas.
class Crm::MetaAds::ComentariosIa::Fonte
  SEM_PESSOA = ->(_inbox) { true }
  NAO_VE_CONVERSA = ->(_conversation) { false }

  # O alvo só com ids (o que o ResumoJob recebe): `{ 'kind' => 'post', 'perfil' =>, 'post_id' => }` ou
  # `{ 'kind' => 'ad', 'ad_id' =>, 'networks' => [] }`. nil quando o perfil ou a conexão não existem mais.
  def self.do_alvo(account, alvo)
    alvo = alvo.to_h.stringify_keys
    if alvo['kind'] == 'post'
      canal = SeusPosts::Perfil.achar(account, alvo['perfil'].to_s)
      canal && post(canal, alvo['post_id'].to_s)
    else
      connection = Crm::MetaAdsConnection.find_by(account_id: account.id)
      connection && anuncio(connection, alvo['ad_id'].to_s, Array(alvo['networks']))
    end
  end

  def self.post(canal, post_id)
    leitor = if canal.is_a?(Channel::Instagram)
               SeusPosts::ComentariosInstagram.new(canal, can_manage: false, conversation_access: NAO_VE_CONVERSA)
             else
               SeusPosts::ComentariosPagina.new(canal, can_manage: false)
             end
    new({ SeusPosts::Perfil.rede(canal) => -> { leitor.payload(post_id) } })
  end

  def self.anuncio(connection, ad_id, networks)
    leituras = {
      'instagram' => lambda {
        Crm::MetaAds::InstagramComments.new(connection, inbox_access: SEM_PESSOA, can_manage: false).payload(ad_id)
      },
      'facebook' => -> { Crm::MetaAds::FacebookComments.new(connection, inbox_access: SEM_PESSOA).list(ad_id) }
    }
    new(leituras.slice(*networks))
  end

  def initialize(leituras)
    @leituras = leituras
  end

  def ler
    lidas = @leituras.map { |network, leitura| [network, leitura.call] }
    falha = lidas.map { |_network, payload| payload[:status] }.find { |status| status != 'ready' }
    return { status: falha, linhas: [] } if falha

    linhas = lidas.flat_map { |network, payload| esperando(network, payload[:comments]) }
    { status: 'ready', linhas: mais_novos_antes(linhas) }
  rescue Crm::MetaAds::InstagramPrivateReply::Error, Crm::MetaAds::AdManagement::Error => e
    { status: e.code, linhas: [] }
  end

  private

  def esperando(network, comments)
    Array(comments).filter_map do |row|
      next unless espera?(row)

      { id: row[:id], network: network, author: autor(row), text: row[:text].to_s, momento: momento(row[:created_time]) }
    end
  end

  def espera?(row)
    !row.dig(:author, :is_page) && !row[:hidden] && row[:private_reply].nil? && row[:text].present? &&
      Array(row[:replies]).none? { |reply| reply.dig(:author, :is_page) }
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
