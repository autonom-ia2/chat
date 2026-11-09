# == Schema Information
#
# Table name: channel_instagram
#
#  id           :bigint           not null, primary key
#  access_token :string           not null
#  expires_at   :datetime         not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :integer          not null
#  instagram_id :string           not null
#  app_scoped_user_id :string
#  login        :string           default("instagram"), not null
#  page_id      :string
#
# Indexes
#
#  index_channel_instagram_on_instagram_id_and_account_id  (instagram_id,account_id) UNIQUE
#
class Channel::Instagram < ApplicationRecord
  include Channelable
  include Reauthorizable
  self.table_name = 'channel_instagram'

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :access_token if Chatwoot.encryption_configured?

  AUTHORIZATION_ERROR_THRESHOLD = 1
  # #2406: de qual login veio a caixa. 'instagram': o login do Instagram (graph.instagram.com, token que se renova).
  # 'facebook': o login único dos Anúncios (graph.facebook.com, token da Página `page_id`, que não expira).
  LOGINS = %w[instagram facebook].freeze
  INSTAGRAM_HOST = 'https://graph.instagram.com'.freeze
  FACEBOOK_HOST = 'https://graph.facebook.com'.freeze

  validates :access_token, presence: true
  validates :login, inclusion: { in: LOGINS }
  validates :page_id, presence: true, if: :facebook_login?
  # #2781: o mesmo Instagram pode estar em mais de uma conta, como a Página do Facebook; numa conta, uma vez só.
  validates :instagram_id, uniqueness: { scope: :account_id }, presence: true

  after_create_commit :subscribe
  before_destroy :unsubscribe

  def name
    'Instagram'
  end

  def create_contact_inbox(instagram_id, name)
    @contact_inbox = ::ContactInboxWithContactBuilder.new({
                                                            source_id: instagram_id,
                                                            inbox: inbox,
                                                            contact_attributes: { name: name }
                                                          }).perform
  end

  def facebook_login?
    login == 'facebook'
  end

  def graph_host
    facebook_login? ? FACEBOOK_HOST : INSTAGRAM_HOST
  end

  def graph_base_uri
    "#{graph_host}/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end

  # O nó do Instagram nas leituras (perfil, posts, números). No login do Facebook o `me` seria a Página.
  def graph_node
    facebook_login? ? instagram_id : 'me'
  end

  # Onde o Direct sai: no login do Facebook, pela Página (doc da Messenger Platform para o Instagram).
  def messages_node
    facebook_login? ? page_id : instagram_id.presence || 'me'
  end

  def subscribe
    return Instagram::PageSubscribeJob.perform_later(id) if facebook_login?

    # ref https://developers.facebook.com/docs/instagram-platform/webhooks#enable-subscriptions
    # #2113: a edição do cliente ainda não está aqui. O candidato documentado é `message_edit` (singular, na página de
    # exemplos de webhook do Instagram); `message_edits` é o nome do Messenger e não vale aqui. Um nome errado derruba a
    # inscrição de caixas novas: confirmar no painel do app da Meta (Webhooks > Instagram) antes, e entrar junto com a
    # reinscrição das caixas, com OK do Rodrigo.
    HTTParty.post(
      "#{graph_base_uri}/#{instagram_id}/subscribed_apps",
      query: {
        subscribed_fields: %w[messages message_reactions messaging_seen],
        access_token: access_token
      }
    )
  rescue StandardError => e
    Rails.logger.debug { "Rescued: #{e.inspect}" }
    true
  end

  # A inscrição vale para o Instagram, não para a caixa: com o mesmo Instagram ligado noutra conta desta stack (#2781),
  # cancelar aqui calaria a outra. Como na Página (Channel::FacebookPage#unsubscribe), só este banco é conferido.
  # No login do Facebook a inscrição é da Página, que pode servir a outros recursos (Messenger, leads): fica.
  def unsubscribe
    return true if facebook_login?
    return true if Channel::Instagram.where(instagram_id: instagram_id).where.not(id: id).exists?

    HTTParty.delete(
      "#{graph_base_uri}/#{instagram_id}/subscribed_apps",
      query: {
        access_token: access_token
      }
    )
    true
  rescue StandardError => e
    Rails.logger.debug { "Rescued: #{e.inspect}" }
    true
  end

  # O token da Página (login do Facebook) não se renova: é o gravado.
  def access_token
    return self[:access_token] if facebook_login?

    Instagram::RefreshOauthTokenService.new(channel: self).access_token
  end

  # Meta data deletion request: drop the stored token and expire it so nothing calls Instagram with it.
  # update_columns skips the presence validation on purpose — a blank, expired token is the revoked state,
  # and reconnecting through Instagram login writes a fresh one.
  def revoke_access!
    update_columns(access_token: '', expires_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    prompt_reauthorization!
  end
end
