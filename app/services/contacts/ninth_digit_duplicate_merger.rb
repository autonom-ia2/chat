# #990: the same Brazilian mobile saved twice in one account, once with the ninth digit and once without it
# (+55 DD 9XXXXXXXX vs +55 DD XXXXXXXX). The contact WITH the ninth digit is kept (base); the other one (mergee)
# is folded into it by Contacts::NinthDigitMergeAction (Chatwoot's ContactMergeAction, messages moved in bulk).
#
# In the same transaction per pair, before the merge: the fork tables that ContactMergeAction does not move are
# re-pointed to the base (destroying the mergee would delete them by FK cascade / destroy_async, or orphan them by
# nullify), the mergee's labels are added to the base (case-insensitive; campaign audiences are label-based), and the
# base takes the mergee's company when it has none (through ContactMembershipService, so the counter stays right).
#
# Skipped and reported, never merged: more than two contacts for the same number, different e-mails, identifiers,
# companies, blocked flags or names (other person / recycled number), or both contacts in the same WhatsApp campaign
# (unique per campaign/contact). A contact gone mid-run is "skip: missing"; any other error rolls the pair back and is
# reported as "failed: <class>" only.
#
# Dry-run by default (apply: false writes nothing). Idempotent: after a merge the number has one contact left.
# Results carry ids, counts and flags only, never names, phones or e-mails.
class Contacts::NinthDigitDuplicateMerger
  BRAZIL_PREFIX = '+55'.freeze
  REPOINT_MODELS = %w[CampaignImportRow CampaignRecipient EmailCampaignRecipient WhatsappApiCampaignRecipient
                      Crm::Card Crm::FollowUp Crm::MeetingGuest CsatSurveyResponse].freeze
  # Tables with a unique (campaign, contact) index: both contacts in the same campaign cannot be re-pointed.
  CAMPAIGN_SCOPED = { 'CampaignRecipient' => :campaign_id, 'WhatsappApiCampaignRecipient' => :whatsapp_api_campaign_id }.freeze
  # Characters a name made only of a phone number may have; such a name counts as empty.
  PHONE_NAME_CHARACTERS = '0-9+() -'.freeze

  Result = Struct.new(:base_id, :mergee_id, :group_ids, :conversations, :repoint, :name_differs, :outcome, keyword_init: true) do
    def to_line
      ids = base_id ? "base=#{base_id} mergee=#{mergee_id}" : "group=#{group_ids.join(',')}"
      rows = (repoint || {}).map { |table, count| "#{table}=#{count}" }.join(' ')
      ["pair #{ids}", "conversations=#{conversations || 0}", "repoint[#{rows}]", "name_differs=#{name_differs || false}", outcome]
        .join(' | ')
    end
  end

  def initialize(account:, apply: false)
    @account = account
    @apply = apply
  end

  # Yields each result as soon as its pair is processed, so a caller can print it before the next one starts.
  def perform
    duplicate_groups.map do |members|
      result = process(members)
      yield result if block_given?
      result
    end
  end

  private

  def normalizer
    @normalizer ||= Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new
  end

  # The ninth-digit form of a number: the longest of the candidates the normalizer accepts for it.
  def ninth_digit_key(phone)
    normalizer.contact_candidates(phone.delete_prefix('+')).max_by(&:length)
  end

  def full_form?(phone)
    phone.delete_prefix('+') == ninth_digit_key(phone)
  end

  def duplicate_groups
    @account.contacts.where('contacts.phone_number LIKE ?', "#{BRAZIL_PREFIX}%").order(:id).pluck(:id, :phone_number)
            .group_by { |_id, phone| ninth_digit_key(phone) }.values
            .select { |members| members.map { |_id, phone| full_form?(phone) }.uniq.size == 2 }
  end

  def process(members)
    return group_result(members, 'skip: ambiguous_group') if members.size > 2

    base_member, mergee_member = members.partition { |_id, phone| full_form?(phone) }.map(&:first)
    pair_result(@account.contacts.find(base_member.first), @account.contacts.find(mergee_member.first))
  rescue ActiveRecord::RecordNotFound
    group_result(members, 'skip: missing')
  rescue StandardError => e
    # Only the class: messages may echo contact data. The pair's transaction was rolled back.
    group_result(members, "failed: #{e.class.name}")
  end

  def group_result(members, outcome)
    Result.new(group_ids: members.map(&:first), outcome: outcome)
  end

  def pair_result(base, mergee)
    Result.new(base_id: base.id, mergee_id: mergee.id, conversations: Conversation.where(contact_id: mergee.id).count,
               repoint: repoint_counts(mergee), name_differs: names_differ?(base, mergee), outcome: outcome_for(base, mergee))
  end

  def outcome_for(base, mergee)
    reason = skip_reason(base, mergee)
    return "skip: #{reason}" if reason
    return 'would merge' unless @apply

    merge(base, mergee)
    'merged'
  end

  def skip_reason(base, mergee)
    return 'email_conflict' if conflict?(base.email.to_s.strip.downcase, mergee.email.to_s.strip.downcase)
    return 'identifier_conflict' if conflict?(base.identifier.to_s.strip, mergee.identifier.to_s.strip)
    return 'company_conflict' if conflict?(base.company_id, mergee.company_id)
    return 'blocked_mismatch' if base.blocked != mergee.blocked
    return 'name_conflict' if names_differ?(base, mergee)

    'shared_campaign' if shared_campaign?(base, mergee)
  end

  def conflict?(left, right)
    left.present? && right.present? && left != right
  end

  def names_differ?(base, mergee)
    conflict?(comparable_name(base.name), comparable_name(mergee.name))
  end

  # Case, accents and extra spaces do not count; a name that is only a phone number counts as empty.
  def comparable_name(name)
    comparable = I18n.transliterate(name.to_s).downcase.split.join(' ')
    comparable.delete(PHONE_NAME_CHARACTERS).empty? ? '' : comparable
  end

  def shared_campaign?(base, mergee)
    CAMPAIGN_SCOPED.any? do |model_name, column|
      model = model_name.constantize
      model.where(contact_id: mergee.id).exists?(column => model.where(contact_id: base.id).select(column))
    end
  end

  def repoint_counts(mergee)
    REPOINT_MODELS.to_h { |model_name| [model_name.constantize.table_name, model_name.constantize.where(contact_id: mergee.id).count] }
  end

  def merge(base, mergee)
    ActiveRecord::Base.transaction do
      REPOINT_MODELS.each do |model_name|
        model_name.constantize.where(contact_id: mergee.id).update_all(contact_id: base.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
      end
      merge_labels(base, mergee)
      inherit_company(base, mergee)
      Contacts::NinthDigitMergeAction.new(account: @account, base_contact: base, mergee_contact: mergee).perform
    end
  end

  def merge_labels(base, mergee)
    known = base.label_list.map(&:downcase)
    extra = mergee.label_list.uniq(&:downcase).reject { |label| known.include?(label.downcase) }
    base.update!(label_list: base.label_list + extra) if extra.any?
  end

  # The flag stops Enterprise's after_commit from deriving another company from the e-mail.
  def inherit_company(base, mergee)
    return if base.company_id.present? || mergee.company_id.blank?

    base.skip_company_auto_association = true
    Companies::ContactMembershipService.new(company: mergee.company).assign(contact: base)
  end
end
