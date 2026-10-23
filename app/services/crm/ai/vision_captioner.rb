module Crm
  module Ai
    # Produces a short Portuguese caption for an image attachment using the
    # Responses API with multimodal input (input_text + input_image as a
    # base64 data URL). Result is cached at `attachment.meta['ai_caption']`.
    class VisionCaptioner
      INSTRUCTIONS = 'Você descreve imagens enviadas em conversas de atendimento ao cliente de forma objetiva e curta.'.freeze
      PROMPT = 'Descreva em uma frase curta, em português, o que aparece nesta imagem. ' \
               'Inclua texto visível relevante. Não invente conteúdo que não esteja na imagem.'.freeze

      def initialize(client:)
        @client = client
      end

      def caption(attachment)
        data_url = to_data_url(attachment)
        return if data_url.blank?

        response = @client.create(
          model: Config::VISION_MODEL,
          instructions: INSTRUCTIONS,
          input: [
            {
              role: 'user',
              content: [
                { type: 'input_text', text: PROMPT },
                { type: 'input_image', image_url: data_url }
              ]
            }
          ],
          reasoning_effort: Config::VISION_REASONING_EFFORT
        )
        response[:text].to_s.strip
      end

      private

      def to_data_url(attachment)
        blob = attachment.file&.blob
        return if blob.blank?
        return if blob.byte_size > Config::IMAGE_BYTE_LIMIT

        "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.download)}"
      end
    end
  end
end
