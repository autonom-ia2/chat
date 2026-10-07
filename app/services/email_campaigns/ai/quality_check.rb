# Controle de qualidade da saída da IA (#1076): as regras do QualityGate (#1082) que valem para um e-mail
# gerado — contraste WCAG AA, botão com 44 px, imagem com alt, só placeholders que a campanha preenche,
# tamanho abaixo do corte do Gmail e um único rodapé travado com o único link de descadastro. Fonte e
# servidor da imagem não entram: o e-mail com identidade usa a fonte do site (com Arial de reserva) e a
# logo/assets vêm do ActiveStorage.
#
# Sem Node em produção não há HTML compilado; o tamanho é estimado pelo MJML. Medido nos 13 modelos da
# biblioteca e no e-mail de IA de exemplo, o HTML compilado tem 4,2–5,5x o MJML; com folga de 6x, 102 KB
# de HTML equivalem a 17 KB de MJML.
#
# Tudo que falha pede UMA correção ao modelo (repair?). Depois dela, o que impede o envio (blocking) faz a
# geração falhar; o resto vira aviso para a pessoa (warnings).
class EmailCampaigns::Ai::QualityCheck
  REVIEWED = %i[contrast button_height image_alt placeholders html_size unsubscribe].freeze
  BLOCKING = %i[placeholders html_size unsubscribe].freeze
  HTML_TO_MJML_RATIO = 6
  MAX_MJML_BYTES = EmailCampaigns::QualityGate::MAX_HTML_BYTES / HTML_TO_MJML_RATIO

  Result = Struct.new(:violations) do
    def repair?
      violations.any?
    end

    def blocking
      violations.select { |violation| BLOCKING.include?(violation.check) }
    end

    def warnings
      violations - blocking
    end

    def report
      violations.map { |violation| "- #{violation.check}: #{violation.detail}" }.join("\n")
    end
  end

  def initialize(mjml, placeholders: [])
    @mjml = mjml.to_s
    @placeholders = (EmailCampaigns::TemplateValidator::DEFAULT_KEYS + Array(placeholders).map(&:to_s)).uniq
  end

  def call
    gate = EmailCampaigns::QualityGate.new(mjml: @mjml, html: nil, placeholders: @placeholders)
    violations = gate.violations.select { |violation| REVIEWED.include?(violation.check) }
    if @mjml.bytesize > MAX_MJML_BYTES
      violations << EmailCampaigns::QualityGate::Violation.new(:html_size, "MJML #{@mjml.bytesize} bytes > #{MAX_MJML_BYTES}")
    end
    Result.new(violations)
  end
end
