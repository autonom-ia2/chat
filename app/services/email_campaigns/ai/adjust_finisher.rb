# Finishes one provider answer of "Ajustar com IA" (#1095), called by PollJob when the generation is an
# adjustment. The answer (EditPromptBuilder::SCHEMA) is rebuilt into the e-mail (MjmlSections), cleaned
# (Sanitizer: dangerous markup, citation links, the single locked footer, canonical MJML) and checked by
# EmailCampaigns::QualityGate on what an adjustment can break. Only problems the e-mail did not have before
# (same check on the same block, image or placeholder) count: the person is not blamed for a template's old
# flaw. With problems, the model gets ONE more round with the report; still failing, the generation fails with
# the check that broke. A good result becomes a proposal (Adjustment) the editor shows before and after — the
# campaign itself is never changed here.
class EmailCampaigns::Ai::AdjustFinisher
  MAX_FIX_ROUNDS = 1
  REASON_MAX = 300
  SUMMARY_MAX = 200
  Violation = EmailCampaigns::QualityGate::Violation

  def initialize(campaign:, token:, client:, response_id:, adjustment:)
    @campaign = campaign
    @token = token
    @client = client
    @response_id = response_id
    @adjustment = adjustment
  end

  def call(text:, usage:, model:)
    return unless EmailCampaigns::Ai::Adjustment.claim_response(@campaign, @response_id)

    Crm::Ai::UsageRecorder.record(account: @campaign.account, feature: 'email', model: model, usage: usage,
                                  reasoning_effort: 'high')
    finish(text)
    @client.delete(@response_id)
  end

  private

  def finish(text)
    answer = parse(text)
    return fail!('empty_response') if answer.nil?
    return refuse!(answer['reason']) if answer['outcome'] == 'impossible'

    sections = EmailCampaigns::Ai::MjmlSections.parse(@adjustment['base'])
    return fail!('adjust_unreadable') if sections.nil?

    check(sections, answer, text)
  end

  def check(sections, answer, text)
    mjml = EmailCampaigns::Ai::Sanitizer.new(sections.assemble(answer['blocks'])).perform
    return fail!('generation_too_large') if mjml.length > EmailCampaign::BODY_HTML_MAX

    problems = new_problems(mjml, sections)
    return propose!(mjml, answer['summary']) if problems.empty?
    return fix!(text, problems) if @adjustment['round'].to_i < MAX_FIX_ROUNDS

    fail!('adjust_quality', problem: problems.first.check.to_s)
  end

  def parse(text)
    parsed = JSON.parse(text.to_s)
    parsed.is_a?(Hash) && parsed['outcome'].present? ? parsed : nil
  rescue JSON::ParserError, TypeError
    nil
  end

  # Compared by Violation#identity (check and target), never by detail: the detail carries measurements (bytes,
  # ratios) that change with any edit, so an e-mail already over the size limit would look like a new problem.
  def new_problems(mjml, sections)
    before = problems(sections.canonical).map(&:identity)
    unknown = sections.unknown_ids.map { |id| Violation.new(:unknown_block, id, id) }
    unknown + problems(mjml).reject { |violation| before.include?(violation.identity) }
  end

  def problems(mjml)
    allowed = EmailCampaigns::TemplateValidator::DEFAULT_KEYS | Array(@adjustment['placeholders'])
    EmailCampaigns::QualityGate.new(mjml: mjml, html: nil, placeholders: allowed).violations
                               .select { |violation| EmailCampaigns::QualityGate::AI_CHECKS.include?(violation.check) }
  end

  # Second round: the same request plus the previous answer and the report of the quality check.
  def fix!(text, problems)
    result = @client.create_background(
      model: Crm::Ai::Config::MODEL_EMAIL, instructions: @adjustment['instructions'], input: fix_input(text, problems),
      schema: EmailCampaigns::Ai::EditPromptBuilder::SCHEMA, reasoning_effort: 'high'
    )
    return fail!('empty_response') if result[:id].blank?

    EmailCampaigns::Ai::Adjustment.update(@campaign, @token, round: @adjustment['round'].to_i + 1)
    return @client.delete(result[:id]) unless @campaign.ai_attach_response!(@token, result[:id])

    EmailCampaigns::Ai::PollJob.set(wait: EmailCampaigns::Ai::SubmitJob::INITIAL_POLL_WAIT)
                               .perform_later(@campaign.id, @token, result[:id], 0)
  rescue Crm::Ai::ResponsesClient::Error => e
    fail!(e.message)
  end

  def fix_input(text, problems)
    fix = EmailCampaigns::Ai::EditPromptBuilder.fix_text(previous_answer: text, problems: problems)
    [{ role: 'user', content: [{ type: 'input_text', text: @adjustment['input'] }, { type: 'input_text', text: fix }] }]
  end

  def propose!(mjml, summary)
    summary = EmailCampaigns::Ai::ShortSentence.call(summary, SUMMARY_MAX)
    EmailCampaigns::Ai::Adjustment.update(@campaign, @token, status: 'proposed', mjml: mjml, summary: summary)
    EmailCampaigns::Ai::Broadcaster.ready(@campaign) if @campaign.ai_propose!(@token)
  end

  def refuse!(reason)
    reason = EmailCampaigns::Ai::ShortSentence.call(reason, REASON_MAX)
    EmailCampaigns::Ai::Adjustment.update(@campaign, @token, status: 'refused', reason: reason)
    fail!('adjust_refused', status: 'refused')
  end

  def fail!(message, problem: nil, status: 'failed')
    EmailCampaigns::Ai::Adjustment.update(@campaign, @token, { status: status, problem: problem }.compact)
    EmailCampaigns::Ai::Broadcaster.failed(@campaign) if @campaign.ai_fail!(@token, message)
  end
end
