# Right before a WhatsApp Oficial campaign goes out (#1329): is the template the campaign recorded
# still the one Meta will accept? Compares campaign.template_params with the template as it is now —
# asked to Meta (Whatsapp::Templates::MetaLookup, one call per campaign) or, when Meta does not
# answer, read from the inbox cache (channel.message_templates). Returns a Verdict; nothing is written.
#
# Reason codes (source `template` unless noted):
#   template_missing           no template with this name and language
#   template_not_approved      status is not APPROVED (paused, in review after an edit, rejected, disabled)
#   template_category_changed  category differs from the one recorded (cost changes)
#   template_structure_changed variables, header or buttons differ from the recorded ones
#   template_format_unsupported a format our engines cannot send yet (Whatsapp::Templates::SendableFormat)
#   template_offer_expired     the limited-time offer expiration the campaign recorded already passed (#1334)
#   templates_not_synced       (system) Meta did not answer and the cache is empty after an account switch
#   template_unverifiable      (system) Meta did not answer and there is no cache to read
class Whatsapp::Templates::DispatchCheck
  # `template`: the item the check matched (from Meta or the cache), so the dispatch gate can keep it (#1382).
  Verdict = Data.define(:reason_code, :source, :details, :template) do
    def initialize(reason_code:, source:, details:, template: nil)
      super
    end

    def ok?
      reason_code.nil?
    end
  end

  META = 'meta'.freeze
  CACHE = 'cache'.freeze

  # `lookup: false` (#1332): só a lista guardada da caixa, sem perguntar à Meta. A lista de campanhas paradas usa assim
  # para dizer se "Retomar" já vai passar, sem uma chamada à Meta por campanha.
  def initialize(campaign, channel: campaign.inbox.channel, lookup: true)
    @campaign = campaign
    @channel = channel
    @lookup = lookup
    @params = campaign.template_params.to_h
  end

  def call
    templates, lookup_source = current_templates
    return unverifiable_verdict if templates.nil?

    template = templates.find { |item| item.is_a?(Hash) && item['name'] == name && item['language'].to_s.casecmp?(language) }
    template_verdict(template, lookup_source)
  end

  private

  def name
    @params['name'].to_s
  end

  def language
    @params['language'].to_s
  end

  def current_templates
    from_meta = @lookup ? Whatsapp::Templates::MetaLookup.new(channel: @channel, name: name).templates : nil
    return [from_meta, META] if from_meta

    cache = Array(@channel.message_templates)
    warn_cache_fallback(cache) if @lookup
    cache.empty? ? [nil, CACHE] : [cache, CACHE]
  end

  def warn_cache_fallback(cache)
    Rails.logger.warn "[WhatsappTemplates::DispatchCheck] campaign=#{@campaign.id} meta_unavailable source=#{CACHE} cached=#{cache.size}"
  end

  def template_verdict(template, lookup_source)
    base = { template_name: name, language: language, lookup_source: lookup_source }
    return verdict('template_missing', base) unless template
    return verdict('template_not_approved', base.merge(status: template['status'].to_s.upcase)) unless approved?(template)

    category_verdict(template, base) || format_verdict(template, base) || structure_verdict(template, base) || ok(template, base)
  end

  def approved?(template)
    template['status'].to_s.casecmp?('approved')
  end

  def category_verdict(template, base)
    recorded = @params['category'].to_s
    current = template['category'].to_s
    return if recorded.empty? || current.empty? || recorded.casecmp?(current)

    verdict('template_category_changed', base.merge(recorded_category: recorded.upcase, current_category: current.upcase))
  end

  def format_verdict(template, base)
    format = sendable_format(template)
    return if format.sendable?
    return verdict('template_offer_expired', base) if format.reason_code == Whatsapp::Templates::SendableFormat::OFFER_EXPIRED

    verdict('template_format_unsupported', base.merge(format_code: format.reason_code))
  end

  def sendable_format(template)
    Whatsapp::Templates::SendableFormat.check(template, recorded: @params['processed_params'])
  end

  def structure_verdict(template, base)
    recorded = Whatsapp::Templates::Structure.of_processed_params(@params['processed_params'])
    return unless recorded

    current = Whatsapp::Templates::Structure.of_template(template)
    return if Whatsapp::Templates::Structure.same?(recorded, current)

    verdict('template_structure_changed', base.merge(Whatsapp::Templates::Structure.differences(recorded, current)))
  end

  def ok(template, base)
    warnings = sendable_format(template).warnings
    Rails.logger.warn "[WhatsappTemplates::DispatchCheck] campaign=#{@campaign.id} warnings=#{warnings.join(',')}" if warnings.any?
    Verdict.new(reason_code: nil, source: nil, details: base.merge(warnings: warnings), template: template)
  end

  def unverifiable_verdict
    code = @channel.message_templates_last_updated.nil? ? 'templates_not_synced' : 'template_unverifiable'
    Verdict.new(reason_code: code, source: 'system', details: { template_name: name, language: language })
  end

  def verdict(code, details)
    Verdict.new(reason_code: code, source: 'template', details: details)
  end
end
