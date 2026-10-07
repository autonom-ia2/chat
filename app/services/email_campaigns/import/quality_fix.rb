# Deterministic quality corrections of an imported design (#1099), checked on the server against the MJML itself
# (QualityGate without compiled HTML): Arial, body text at 14px or more, text and buttons readable (WCAG AA contrast),
# buttons 44px tall, images described. At most MAX_PASSES rounds of gate → fix; what still fails is reported as pending
# (unknown fields have their own blocking warning). Returns the corrected MJML.
class EmailCampaigns::Import::QualityFix
  MAX_PASSES = 2
  FIXABLE = %i[font_family font_size contrast button_height image_alt].freeze
  REPORTED_ELSEWHERE = %i[placeholders html_size].freeze

  def self.call(mjml, report, placeholders:)
    new(report, placeholders).call(mjml)
  end

  def initialize(report, placeholders)
    @report = report
    @placeholders = placeholders
  end

  def call(mjml)
    attempted = []
    MAX_PASSES.times do
      checks = violations(mjml).map(&:check).uniq & FIXABLE
      break if checks.empty?

      attempted |= checks
      mjml = EmailCampaigns::MjmlCanonicalizer.call(mjml) { |root, cut| Fixes.new(root, cut, checks).call }
    end
    report(attempted, violations(mjml))
    mjml
  end

  private

  def violations(mjml)
    EmailCampaigns::QualityGate.new(mjml: mjml, remote_images: true, placeholders: @placeholders).violations
  end

  def report(attempted, remaining)
    pending = remaining.map(&:check).uniq
    (attempted - pending).each { |check| @report.add(:quality_fixed, item: check.to_s) }
    (pending - REPORTED_ELSEWHERE).each { |check| @report.add(:quality_pending, item: check.to_s) }
    @report.add(:gmail_clip) if pending.include?(:html_size)
  end
end
