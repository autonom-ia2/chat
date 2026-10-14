# frozen_string_literal: true

require 'digest'
require 'securerandom'
require 'jwt'

class Autonomia::Financial::StoreActorAssertion
  ACTIONS = {
    ['GET', '/catalog'] => 'catalog.read',
    ['GET', '/services'] => 'service.read',
    ['POST', '/services'] => 'service.create',
    ['POST', '/checkout-sessions'] => 'checkout.create',
    ['POST', '/checkout-sessions/resolve'] => 'checkout.read',
    ['GET', '/service-subscriptions'] => 'subscription.list',
    ['POST', '/usage-reservations'] => 'usage.reserve',
    ['POST', '/entitlements/resolve'] => 'entitlements.read'
  }.freeze
  RESOURCE_ACTIONS = {
    ['GET', 'publications', nil] => 'publication.read',
    ['PUT', 'publications', nil] => 'publication.write',
    ['GET', 'checkout-sessions', nil] => 'checkout.read',
    ['GET', 'service-subscriptions', nil] => 'subscription.read',
    ['GET', 'usage-reservations', nil] => 'usage.read',
    %w[POST usage-reservations commit] => 'usage.commit',
    %w[POST usage-reservations release] => 'usage.release',
    %w[GET service-subscriptions cancellation] => 'subscription.cancellation.read',
    %w[POST service-subscriptions cancellation] => 'subscription.cancellation.schedule',
    %w[POST service-subscriptions cancellation/resume] => 'subscription.cancellation.resume',
    %w[POST checkout-sessions reconcile] => 'checkout.reconcile'
  }.freeze

  def initialize(configuration:, subject:)
    @configuration = configuration
    @subject = subject
  end

  def issue!(method, path, body, idempotency_key: nil, checkout_context: nil)
    method = method.to_s.upcase
    pathname = URI.parse(path).path
    suffix = pathname.delete_prefix(Autonomia::Financial::StoreClient::STORE_PATH)
    action = action_for(method, suffix)
    raise ArgumentError, 'Unsupported store action.' unless action

    claims = base_claims(action, method, pathname, body)
    claims.merge!(service_claims(path)) if action == 'service.read'
    claims.merge!(checkout_claims(checkout_context, idempotency_key)) if action == 'checkout.create'
    JWT.encode(claims, @configuration.assertion_secret, 'HS256')
  end

  private

  def action_for(method, suffix)
    exact = ACTIONS[[method, suffix]]
    return exact if exact

    pattern = %r{\A/(publications|checkout-sessions|service-subscriptions|usage-reservations)/[a-f0-9-]{36}
                 (?:/(commit|release|reconcile|cancellation(?:/resume)?))?\z}ix
    match = suffix.match(pattern)
    RESOURCE_ACTIONS[[method, match[1], match[2]]] if match
  end

  def base_claims(action, method, pathname, body)
    now = Time.now.to_i
    {
      iss: @configuration.namespace.fetch('installationId'), aud: 'financial-internal-store',
      sub: @subject, role: 'superadmin', namespace: @configuration.namespace,
      jti: SecureRandom.uuid, iat: now, exp: now + 120,
      action: action, method: method, path: pathname, bodySha256: Digest::SHA256.hexdigest(body.to_s)
    }
  end

  def service_claims(path)
    query = URI.decode_www_form(URI.parse(path).query.to_s).to_h
    return { principalAgentId: Integer(query.fetch('principalAgentId'), 10) } if query.key?('principalAgentId')

    { featureKey: Autonomia::Financial::StoreFeatures.target!(query.fetch('featureKey')).fetch('featureKey') }
  end

  def checkout_claims(context, idempotency_key)
    Autonomia::Financial::StoreContract.validate!('uuid', context&.fetch('checkoutIntentId'))
    Autonomia::Financial::StoreContract.validate!('uuid', idempotency_key)
    extension = {
      'checkoutIntentId' => context.fetch('checkoutIntentId'), 'idempotencyKeySha256' => Digest::SHA256.hexdigest(idempotency_key),
      'returnContext' => context.except('target')
    }
    target = context['target']
    if target && target['type'] == 'agent'
      extension['target'] = target
    else
      extension['featureKey'] = if target
                                  Autonomia::Financial::StoreFeatures.target!(target.fetch('featureKey')).fetch('featureKey')
                                else
                                  Autonomia::Financial::StoreFeatures::PILOT_KEY
                                end
    end
    Autonomia::Financial::StoreCheckoutContract.validate!('checkoutActorExtension', extension)
    extension.transform_keys(&:to_sym)
  end
end
