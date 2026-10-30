# IA cuida dos comentários (#2212): o cuidado de um post (Instagram ou Página do Facebook) ou de um anúncio (as duas
# redes). Guarda o que a pessoa aprovou na tela: a ficha do que o post oferece, a correção dela, a mensagem do privado,
# para quem ele vai (`para_quem`, nas palavras do dono: a IA decide comentário a comentário se é o caso), o botão do
# WhatsApp, as frases públicas, a resposta do preço (nil: a chave do preço desligada) e quem continua a conversa quando
# a pessoa responde. Os textos ficam como a tela mostrou, no idioma de quem aprovou: o servidor não
# monta frase.
#
# O comentário não fica aqui (dado de terceiro, lido ao vivo); o que a IA fez com cada um fica nas ações do #2196.
class Crm::MetaAdsCommentCare < ApplicationRecord
  self.table_name = 'crm_meta_ads_comment_cares'

  TARGET_KINDS = %w[post ad].freeze
  NETWORKS = %w[instagram facebook both].freeze
  STATUSES = %w[on paused].freeze
  # assignment: você ou sua equipe, pela Atribuição; agent: o agente de IA da caixa.
  HANDOFFS = %w[assignment agent].freeze
  # Texto de uma mensagem do Instagram (a mais curta das duas redes).
  MESSAGE_LIMIT = 1_000
  NOTE_LIMIT = 500
  PHRASES = (1..3)
  PHRASE_LIMIT = 300
  # O botão só abre conversa no WhatsApp: nenhum outro endereço sai na mensagem automática.
  WHATSAPP_URL = 'https://wa.me/'.freeze
  BUTTON_TITLE_LIMIT = 20

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :inbox, optional: true

  validates :target_kind, inclusion: { in: TARGET_KINDS }
  validates :target_id, presence: true, uniqueness: { scope: [:account_id, :target_kind] }
  validates :network, inclusion: { in: NETWORKS }
  validates :status, inclusion: { in: STATUSES }
  validates :handoff, inclusion: { in: HANDOFFS }
  validates :message, presence: true, length: { maximum: MESSAGE_LIMIT }
  validates :note, length: { maximum: NOTE_LIMIT }
  validates :para_quem, length: { maximum: NOTE_LIMIT }
  validates :price_reply, length: { maximum: PHRASE_LIMIT }
  validate :phrases_validas
  validate :botao_do_whatsapp

  scope :on, -> { where(status: 'on') }

  # O cuidado que vale para um comentário: o do anúncio, quando ele veio de um (pelo id do anúncio ou por um dos posts
  # do criativo), senão o do post. Só o da rede do comentário (ou das duas).
  def self.cuidando(account_id:, network:, post_id:, ad_id:)
    escopo = on.where(account_id: account_id, network: [network.to_s, 'both'])
    do_anuncio(escopo, post_id, ad_id) || (post_id.present? && escopo.find_by(target_kind: 'post', target_id: post_id.to_s)) || nil
  end

  def self.do_anuncio(escopo, post_id, ad_id)
    anuncios = escopo.where(target_kind: 'ad')
    (ad_id.present? && anuncios.find_by(target_id: ad_id.to_s)) ||
      (post_id.present? && anuncios.find_by('post_ids @> ?', [post_id.to_s].to_json)) || nil
  end

  # Post sem produto: a IA só esconde propaganda e avisa reclamação.
  def offer?
    offer.to_h['offer'].present?
  end

  # A IA só manda privado se sabe o que o post oferece ou para quem o dono quer mandar. Sem nenhum dos dois, ela só
  # esconde propaganda e avisa reclamação.
  def privado?
    offer? || para_quem.present?
  end

  # A frase do comentário depois do privado. `vez` reveza as frases, para a IA não repetir a mesma em seguida.
  def resposta_publica(decisao, vez)
    return price_reply if decisao == 'price' && price_reply.present?

    phrases[vez % phrases.size]
  end

  private

  def phrases_validas
    lista = Array(phrases)
    valida = PHRASES.cover?(lista.size) && lista.all? { |frase| frase.is_a?(String) && frase.strip.length.between?(1, PHRASE_LIMIT) }
    errors.add(:phrases, :invalid) unless valida
  end

  def botao_do_whatsapp
    return if button.nil?

    titulo = button.to_h['title'].to_s.strip
    url = button.to_h['url'].to_s
    valido = titulo.length.between?(1, BUTTON_TITLE_LIMIT) && url.start_with?(WHATSAPP_URL) && url.length > WHATSAPP_URL.length
    errors.add(:button, :invalid) unless valido
  end
end
