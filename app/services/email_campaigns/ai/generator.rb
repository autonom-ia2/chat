module EmailCampaigns
  module Ai
    # Monta o pedido (instructions + input multimodal) da geração de e-mail por IA a partir do
    # brief + placeholders + assets (imagens/PDF/vídeo). Com base_mjml (o e-mail que está na tela) o
    # pedido é um AJUSTE (#1095): o brief é o que a pessoa quer mudar e o modelo devolve os blocos do
    # e-mail ajustado (EditPromptBuilder). Extraído do AiController p/ que o job assíncrono (SubmitJob)
    # e o controller usem a MESMA lógica. Resolve apenas blobs que a CONTA possui (builder_assets das
    # próprias campanhas) — não confia em url do cliente.
    class Generator
      IMAGE_TYPES = %w[image/png image/jpeg image/gif image/webp].freeze
      VIDEO_TYPES = %w[video/mp4 video/webm video/quicktime].freeze
      PDF_TYPE = 'application/pdf'.freeze
      MAX_IMAGES_PER_REQUEST = 6
      MAX_BASE_MJML_BYTES = 120_000

      GENERATE_SCHEMA = {
        name: 'email_campaign_generate',
        schema: {
          type: 'object',
          properties: {
            subject: { type: 'string' },
            preheader: { type: 'string' },
            mjml: { type: 'string' },
            subject_variants: { type: 'array', items: { type: 'string' } }
          },
          required: %w[subject preheader mjml subject_variants],
          additionalProperties: false
        }
      }.freeze

      # identity: BrandKits::PromptPayload hash of the chosen visual identity (#1076), or nil.
      # rubocop:disable Metrics/ParameterLists -- keyword data of one generation request
      def initialize(account:, brief:, placeholders: [], assets: [], base_mjml: nil, identity: nil)
        @identity = identity
        @account = account
        @brief = brief.to_s
        @placeholders = Array(placeholders)
        @assets = normalize_assets(assets)
        @base_mjml = base_mjml.to_s.presence
        @image_budget = MAX_IMAGES_PER_REQUEST
        @pdf_budget = Crm::Ai::Config::MAX_PDFS_PER_REQUEST
      end
      # rubocop:enable Metrics/ParameterLists

      def base_mjml_too_large?
        @base_mjml.present? && @base_mjml.bytesize > MAX_BASE_MJML_BYTES
      end

      def adjust?
        @base_mjml.present?
      end

      # Blocos do e-mail que está sendo ajustado; nil quando não há base ou ela não se divide.
      def sections
        return nil unless adjust?

        @sections ||= MjmlSections.parse(@base_mjml)
      end

      # { instructions:, input:, input_text:, schema:, tools: } pronto p/ ResponsesClient. enrich_image_src!
      # roda antes de instructions (o prompt usa asset[:src_url]); o input carrega imagens/PDF como base64.
      def build
        videos = resolve_video_assets
        enrich_image_src!
        adjust? ? build_adjust(videos) : build_generate(videos)
      end

      private

      def build_generate(videos)
        text = PromptBuilder.input_text(brief: @brief, placeholders: @placeholders, assets: @assets, videos: videos,
                                        identity: @identity)
        { instructions: PromptBuilder.generate(placeholders: @placeholders, assets: @assets, videos: videos,
                                               brand: @account.name, identity: @identity),
          input: build_input(text), input_text: text, schema: GENERATE_SCHEMA, tools: Crm::Ai::WebSearch.tools }
      end

      # Ajuste: sem busca na web — o modelo só mexe no e-mail que recebeu.
      def build_adjust(videos)
        text = EditPromptBuilder.input_text(request: @brief, sections: sections.editable, placeholders: @placeholders,
                                            assets_rule: PromptBuilder.assets_rule(@assets),
                                            video_rule: PromptBuilder.video_embed_rule(videos))
        { instructions: EditPromptBuilder.instructions(identity: identity), input: build_input(text), input_text: text,
          schema: EditPromptBuilder::SCHEMA, tools: nil }
      end

      # Identidade visual em uso. Hoje o nome da conta; o kit de marca (#1076) entra aqui.
      def identity
        { name: @account.name }
      end

      def normalize_assets(assets)
        Array(assets).map do |asset|
          h = asset.respond_to?(:permit) ? asset.to_unsafe_h : asset
          h.to_h.with_indifferent_access
        end
      end

      def build_input(text)
        content = [{ type: 'input_text', text: text }]
        @assets.each do |asset|
          part = asset_content_part(asset)
          content << part if part
        end
        [{ role: 'user', content: content }]
      end

      def asset_content_part(asset)
        blob = resolve_blob(asset[:signed_id])
        return nil if blob.blank?
        return image_content_part(blob) if image_content_type?(blob.content_type)
        return pdf_content_part(blob) if pdf_content_type?(blob.content_type)

        nil
      end

      def image_content_part(blob)
        return nil unless @image_budget.positive?
        return nil if blob.byte_size > Crm::Ai::Config::IMAGE_BYTE_LIMIT

        @image_budget -= 1
        data = "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
        { type: 'input_image', image_url: data }
      end

      def pdf_content_part(blob)
        return nil unless @pdf_budget.positive?
        return nil if blob.byte_size > Crm::Ai::Config::PDF_BYTE_LIMIT

        @pdf_budget -= 1
        data = "data:application/pdf;base64,#{Base64.strict_encode64(blob.download)}"
        { type: 'input_file', filename: blob.filename.to_s.presence || 'document.pdf', file_data: data }
      end

      def enrich_image_src!
        budget = MAX_IMAGES_PER_REQUEST
        @assets.each do |asset|
          next unless asset[:kind].to_s == 'image'

          asset[:src_url] = nil
          next unless budget.positive?

          blob = resolve_blob(asset[:signed_id])
          next if blob.blank? || !image_content_type?(blob.content_type)
          next if blob.byte_size > Crm::Ai::Config::IMAGE_BYTE_LIMIT

          asset[:src_url] = blob_url(blob)
          budget -= 1
        end
      end

      def resolve_video_assets
        @assets.filter_map do |asset|
          next unless asset[:kind].to_s == 'video'

          resolve_video_asset(asset)
        end
      end

      def resolve_video_asset(asset)
        result = resolve_uploaded_video_asset(asset) || resolve_external_video_asset(asset)
        return nil if result.blank?

        result.merge(kind: 'video', description: asset[:description].to_s.strip, role: asset[:role].to_s.strip)
              .with_indifferent_access
      rescue EmailCampaigns::VideoAsset::Error
        nil
      end

      def resolve_uploaded_video_asset(asset)
        signed_id = asset[:signed_id].presence || signed_id_from_storage_url(asset[:video_url])
        return nil if signed_id.blank?

        blob = resolve_blob(signed_id)
        return nil unless blob && video_content_type?(blob.content_type)

        poster_blob = resolve_blob(asset[:poster_signed_id])
        poster_url = blob_url(poster_blob) if poster_blob && image_content_type?(poster_blob.content_type)
        EmailCampaigns::VideoAsset.from_upload(video_url: blob_url(blob), poster_url: poster_url)
      end

      def resolve_external_video_asset(asset)
        url = asset[:video_url].presence || asset[:url]
        return nil if url.blank?

        EmailCampaigns::VideoAsset.from_url(url)
      end

      def signed_id_from_storage_url(url)
        return nil if url.blank?

        segments = URI.parse(url.to_s).path.split('/')
        blob_index = segments.index('blobs')
        return nil if blob_index.blank?

        route_segment = segments[blob_index + 1]
        %w[redirect proxy].include?(route_segment) ? segments[blob_index + 2] : route_segment
      rescue URI::InvalidURIError
        nil
      end

      def resolve_blob(signed_id)
        return nil if signed_id.blank?

        blob = ActiveStorage::Blob.find_signed(signed_id)
        return nil if blob.blank?
        return nil unless EmailCampaign.where(account: @account).joins(:builder_assets_attachments)
                                       .exists?(active_storage_attachments: { blob_id: blob.id })

        blob
      rescue StandardError
        nil
      end

      # URL pública (redirect do ActiveStorage) usada como <mj-image src> que o destinatário do
      # e-mail busca. No job não há request, então o host vem do FRONTEND_URL — sem fallback para
      # um domínio fixo (evita gravar URLs apontando para a instalação errada). Falha clara se
      # ausente (a geração é marcada failed e o usuário pode tentar de novo).
      def blob_url(blob)
        EmailCampaigns::PublicBlobUrl.call(blob)
      end

      def image_content_type?(content_type)
        IMAGE_TYPES.include?(content_type.to_s)
      end

      def video_content_type?(content_type)
        VIDEO_TYPES.include?(content_type.to_s)
      end

      def pdf_content_type?(content_type)
        content_type.to_s == PDF_TYPE
      end
    end
  end
end
