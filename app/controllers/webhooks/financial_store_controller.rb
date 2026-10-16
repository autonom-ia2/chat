# frozen_string_literal: true

class Webhooks::FinancialStoreController < ActionController::API
  def create
    configuration = ::Autonomia::Financial::StoreConfiguration.new
    verifier = ::Autonomia::Financial::StoreEventVerifier.new(configuration: configuration)
    return head :payload_too_large if request.content_length.to_i > ::Autonomia::Financial::StoreEventVerifier::MAX_BODY_BYTES

    payload = verifier.verify!(body: request.raw_post, headers: request.headers)
    digest = Digest::SHA256.hexdigest(request.raw_post)
    event = persist_event(payload, digest)
    return head :conflict unless event.body_sha256 == digest

    ::Autonomia::Store::EventJob.perform_later(event.id) if event.state == 'pending'
    head :accepted
  rescue ::Autonomia::Financial::StoreClientError => e
    render json: { error: 'Invalid financial store event.', code: e.code }, status: e.status
  end

  private

  def persist_event(payload, digest)
    ::Autonomia::Store::Event.create_or_find_by!(id: payload.fetch('eventId')) do |record|
      record.payload = payload
      record.body_sha256 = digest
    end
  end
end
