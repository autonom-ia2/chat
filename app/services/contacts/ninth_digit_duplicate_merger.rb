# #990: the same Brazilian mobile saved twice in one account, once with the ninth digit and once without it
# (+55 DD 9XXXXXXXX vs +55 DD XXXXXXXX). The contact WITH the ninth digit is kept (base); the other one (mergee)
# is folded into it by Chatwoot's own ContactMergeAction.
#
# Before the merge, the fork tables that ContactMergeAction does not move are re-pointed to the base, inside the same
# transaction, because destroying the mergee would delete (FK cascade / destroy_async) or orphan (nullify) them.
# The mergee's labels are added to the base (campaign audiences are label-based).
#
# Skipped and reported, never merged: more than two contacts for the same number, two different e-mails, two
# different companies, or both contacts in the same WhatsApp campaign (unique per campaign/contact).
#
# Dry-run by default (apply: false writes nothing). Idempotent: after a merge the number has one contact left.
# Output carries ids and counts only, never names, phones or e-mails.
class Contacts::NinthDigitDuplicateMerger
  BRAZIL_PREFIX = '+55'.freeze
  REPOINT_MODELS = %w[CampaignImportRow CampaignRecipient EmailCampaignRecipient WhatsappApiCampaignRecipient
                      Crm::Card Crm::FollowUp Crm::MeetingGuest CsatSurveyResponse].freeze
  # Tables with a unique (campaign, contact) index: both contacts in the same campaign cannot be re-pointed.
  CAMPAIGN_SCOPED = { 'CampaignRecipient' => :campaign_id, 'WhatsappApiCampaignRecipient' => :whatsapp_api_campaign_id }.freeze

  Result = Struct.new(:base_id, :mergee_id, :group_ids, :conversations, :repoint, :outcome, keyword_init: true) do
    def to_line
      ids = base_id ? "base=#{base_id} mergee=#{mergee_id}" : "group=#{group_ids.join(',')}"
      rows = (repoint || {}).map { |table, count| "#{table}=#{count}" }.join(' ')
      ["pair #{ids}", "conversations=#{conversations || 0}", "repoint[#{rows}]", outcome].join(' | ')
    end
  end

  def initialize(account:, apply: false)
    @account = account
    @apply = apply
  end

  def perform
    duplicate_groups.map { |members| process(members) }
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
    return Result.new(group_ids: members.map(&:first), outcome: 'skip: ambiguous_group') if members.size > 2

    base_member, mergee_member = members.partition { |_id, phone| full_form?(phone) }.map(&:first)
    base = @account.contacts.find(base_member.first)
    mergee = @account.contacts.find(mergee_member.first)
    Result.new(base_id: base.id, mergee_id: mergee.id, conversations: Conversation.where(contact_id: mergee.id).count,
               repoint: repoint_counts(mergee), outcome: outcome_for(base, mergee))
  end

  def outcome_for(base, mergee)
    reason = skip_reason(base, mergee)
    return "skip: #{reason}" if reason
    return 'would merge' unless @apply

    merge(base, mergee)
  end

  def skip_reason(base, mergee)
    return 'email_conflict' if conflict?(base.email.to_s.strip.downcase, mergee.email.to_s.strip.downcase)
    return 'company_conflict' if conflict?(base.company_id, mergee.company_id)

    'shared_campaign' if shared_campaign?(base, mergee)
  end

  def conflict?(left, right)
    left.present? && right.present? && left != right
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
      labels = (base.label_list + mergee.label_list).uniq
      base.update!(label_list: labels) if labels.size > base.label_list.size
      ContactMergeAction.new(account: @account, base_contact: base, mergee_contact: mergee).perform
    end
    'merged'
  rescue StandardError => e
    # Only the class: messages may echo contact data. The pair's transaction is rolled back; the task exits non-zero.
    "failed: #{e.class.name}"
  end
end
