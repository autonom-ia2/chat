# Controle de qualidade da saída da IA (#1076): as regras do QualityGate (#1082) que valem para um e-mail
# gerado — contraste WCAG AA, botão com 44 px, imagem com alt, só placeholders que a campanha preenche,
# tamanho abaixo do corte do Gmail e um único rodapé travado com o único link de descadastro. Fonte e
# servidor da imagem não entram: o e-mail com identidade usa a fonte do site (com Arial de reserva) e a
# logo/assets vêm do ActiveStorage.
#
# Sem Node em produção não há HTML compilado; o tamanho é estimado pelo MJML (ESTIMATED_HTML_PER_MJML_BYTE).
# A estimativa erra para os dois lados, então perto do corte do Gmail (dentro de SIZE_MARGIN) é aviso
# (html_size_near); só bloqueia (html_size) quando passa claramente.
#
# Tudo que falha pede UMA correção ao modelo (repair?). Depois dela, o que impede o envio (blocking) faz a
# geração falhar; o resto vira aviso para a pessoa (warnings).
class EmailCampaigns::Ai::QualityCheck
  REVIEWED = %i[contrast button_height image_alt placeholders unsubscribe].freeze
  BLOCKING = %i[placeholders html_size unsubscribe].freeze
  # Bytes de HTML compilado por byte de MJML. Medido em 07/10/2026 compilando os 13 modelos da biblioteca
  # (db/seeds/email_templates) com mjml-browser: 4,2x a 5,5x. Usa o maior, para não subestimar.
  ESTIMATED_HTML_PER_MJML_BYTE = 5.5
  # Faixa de incerteza em volta do corte (102 KB): dentro dela, aviso; acima dela, bloqueio.
  SIZE_MARGIN = 0.15
  HTML_LIMIT = EmailCampaigns::QualityGate::MAX_HTML_BYTES

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
    Result.new([*violations, size_violation].compact)
  end

  private

  def size_violation
    estimate = (@mjml.bytesize * ESTIMATED_HTML_PER_MJML_BYTE).round
    return if estimate < HTML_LIMIT * (1 - SIZE_MARGIN)

    check = estimate > HTML_LIMIT * (1 + SIZE_MARGIN) ? :html_size : :html_size_near
    EmailCampaigns::QualityGate::Violation.new(check, "about #{estimate} bytes of HTML (Gmail clips at #{HTML_LIMIT})")
  end
end
