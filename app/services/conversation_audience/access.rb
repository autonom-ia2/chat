# Who may run a search by conversation (#2277): the gate of the controller (campaign_manage AND conversation_view, or
# an administrator), checked again by each job. A person who lost the role or left the account while the search waited
# in line stops spending the account's AI key.
module ConversationAudience::Access
  PERMISSIONS = %w[campaign_manage conversation_view].freeze
  ERROR = 'no_access'.freeze
  # Where a saved audience says it came from the conversations (ConversationAudience::Save).
  SOURCE = 'conversations'.freeze

  module_function

  def allowed?(search)
    account_user = search.user_id && AccountUser.find_by(account_id: search.account_id, user_id: search.user_id)
    account_user.present? && PERMISSIONS.all? { |key| account_user.permission_granted?(key) }
  end

  # The contact's own data (name, phone, e-mail, company, custom attributes) is contact reading: the same rule as the
  # contact base, ContactPolicy#index? (EE: contact_view, which contact_manage implies; administrator and plain agent keep it).
  def reads_contacts?(account_user)
    return false if account_user.nil?

    context = { user: account_user.user, account: account_user.account, account_user: account_user }
    Pundit.policy!(context, Contact).index?
  end

  def from_conversations?(campaign_import)
    campaign_import.options.to_h['source'] == SOURCE
  end

  # Who of an audience built from the conversations the viewer may see by name: the people whose conversation the
  # viewer can open (the name plus the audience's name tell what was said there; access review of #2303). An audience
  # without its search gives nobody. The count and the send are the audience's reach and stay whole.
  def visible_contact_ids(campaign_import, user)
    search_id = campaign_import.options.to_h['conversation_audience_search_id']
    return Set.new if search_id.blank? || user.nil?

    people = ConversationAudiencePerson.where(search_id: search_id)
    visible = ConversationAudience::Conversations.visible_ids(campaign_import.account, user, people.pluck(:conversation_id))
    people.where(conversation_id: visible.to_a).pluck(:contact_id).to_set
  end

  # Whatever the audience's origin (conversations, prospecting, automation, a file), its people are contacts of the base:
  # only who reads contacts sees their phone, e-mail, company and columns (access review of #2303; #2414 review).
  def hides_contact_data?(account_user)
    !reads_contacts?(account_user)
  end

  # The masks shown to who does not read contacts, the ones of the campaign result export (#1007): first name and the
  # initial of the last one; e-mail with only its first letter and the domain.
  def masked_name(name)
    CampaignJourney::ResultExport.masked_name(name)
  end

  def masked_email(email)
    email.present? ? EmailCampaigns::EmailNormalizer.mask(email.to_s.strip.downcase) : email
  end

  # The only phone mask of the campaign features (CampaignImports::PhoneMask): country code and the last 4 digits.
  def masked_phone(phone)
    phone.present? ? CampaignImports::PhoneMask.mask(phone) : phone
  end
end
