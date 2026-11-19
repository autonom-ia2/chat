class Autonomia::Agents::SourceFile
  URL_TTL = 1.minute
  INLINE_TYPES = %w[application/pdf image/jpeg image/png image/webp image/gif].freeze
  # Signed file links belong to the authenticated screen, never to the Guide/LLM context.
  SO_NA_TELA_DO_GUIA = { 'GET autonomia/agents/:agent_id/sources/:source_id/file' => 'agent_source_file' }.freeze

  def initialize(blob)
    @blob = blob
  end

  def url
    disposition = INLINE_TYPES.include?(@blob.content_type) ? :inline : :attachment
    @blob.url(expires_in: URL_TTL, disposition: disposition)
  end
end
