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
#
# Indexes
#
#  index_channel_instagram_on_instagram_id  (instagram_id) UNIQUE
#
class Channel::Instagram < ApplicationRecord
  include Channelable
  include Reauthorizable
  self.table_name = 'channel_instagram'

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  encrypts :access_token if Chatwoot.encryption_configured?

  AUTHORIZATION_ERROR_THRESHOLD = 1
  SUBSCRIPTION_TIMEOUT = 10
  # ref https://developers.facebook.com/docs/instagram-platform/webhooks#enable-subscriptions
  # `message_edit` (#2113): a edição do cliente, confirmada no painel do app da Meta (Webhooks > Instagram).
  SUBSCRIBED_FIELDS = %w[messages message_reactions messaging_seen message_edit].freeze

  validates :access_token, presence: true
  validates :instagram_id, uniqueness: true, presence: true

  after_create_commit :subscribe
  # Reconectar troca o token: a inscrição é refeita junto, para a caixa voltar a receber todos os campos. Método
  # próprio porque after_create_commit e after_update_commit com o mesmo nome deixam só o último valer. A renovação
  # do token também troca o token e repete a inscrição: é idempotente, e a renovação não se repete em seguida
  # (RefreshOauthTokenService só renova token com mais de 24h).
  after_update_commit :resubscribe, if: :saved_change_to_access_token?
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

  def subscribe
    response = renew_subscription
    Rails.logger.warn("[Channel::Instagram] channel #{id}: Meta recusou a inscrição (HTTP #{response.code})") unless response.success?
    response
  rescue StandardError => e
    Rails.logger.debug { "Rescued: #{e.inspect}" }
    true
  end

  def resubscribe
    subscribe
  end

  # A resposta da Meta, sem engolir erro: quem chama (Instagram::RenovarInscricaoJob) decide se deu certo.
  def renew_subscription
    HTTParty.post(
      "#{base_uri}/#{instagram_id}/subscribed_apps",
      query: {
        subscribed_fields: SUBSCRIBED_FIELDS,
        access_token: access_token
      },
      timeout: SUBSCRIPTION_TIMEOUT
    )
  end

  def unsubscribe
    HTTParty.delete(
      "#{base_uri}/#{instagram_id}/subscribed_apps",
      query: {
        access_token: access_token
      }
    )
    true
  rescue StandardError => e
    Rails.logger.debug { "Rescued: #{e.inspect}" }
    true
  end

  def access_token
    Instagram::RefreshOauthTokenService.new(channel: self).access_token
  end

  # Meta data deletion request: drop the stored token and expire it so nothing calls Instagram with it.
  # update_columns skips the presence validation on purpose — a blank, expired token is the revoked state,
  # and reconnecting through Instagram login writes a fresh one.
  def revoke_access!
    update_columns(access_token: '', expires_at: Time.current, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    prompt_reauthorization!
  end

  private

  def base_uri
    "https://graph.instagram.com/#{GlobalConfigService.load('INSTAGRAM_API_VERSION', 'v22.0')}"
  end
end
