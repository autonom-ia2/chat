require 'rails_helper'

# Module keys added to custom roles in #452 (<module>_view / <module>_manage). Lives under spec/enterprise:
# the custom-role half of AccountUser#permission_granted? only exists with the EE overlay loaded.
RSpec.describe 'Custom role module permissions', type: :policy do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  def context_for(user)
    { user: user, account: account, account_user: user.account_users.find_by(account: account) }
  end

  def custom_role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  describe 'AccountUser#permission_granted?' do
    def granted?(user, key)
      user.account_users.find_by(account: account).permission_granted?(key)
    end

    it 'grants every key to administrators and none to plain agents' do
      expect(granted?(admin, 'campaign_manage')).to be(true)
      expect(granted?(agent, 'campaign_view')).to be(false)
    end

    it 'lets a manage key imply the matching view key only' do
      user = custom_role_user('campaign_manage')

      expect(granted?(user, 'campaign_view')).to be(true)
      expect(granted?(user, 'campaign_manage')).to be(true)
      expect(granted?(user, 'inbox_view')).to be(false)
    end

    it 'never lets a view key imply manage' do
      user = custom_role_user('autonomia_view')

      expect(granted?(user, 'autonomia_view')).to be(true)
      expect(granted?(user, 'autonomia_manage')).to be(false)
    end
  end

  describe 'campaign policies' do
    let(:email_campaign) { build(:email_campaign, account: account) }

    it 'gives campaign_view read access only' do
      context = context_for(custom_role_user('campaign_view'))

      expect(CampaignPolicy.new(context, Campaign).index?).to be(true)
      expect(CampaignPolicy.new(context, Campaign).create?).to be(false)
      expect(EmailCampaignPolicy.new(context, email_campaign).show?).to be(true)
      expect(EmailCampaignPolicy.new(context, email_campaign).send_now?).to be(false)
    end

    it 'keeps personal-data exports and imports out of campaign_view' do
      context = context_for(custom_role_user('campaign_view'))

      expect(EmailCampaignReportPolicy.new(context, :email_campaign_report).view?).to be(true)
      expect(EmailCampaignReportPolicy.new(context, :email_campaign_report).export?).to be(false)
      expect(CampaignImportPolicy.new(context, CampaignImport).report?).to be(true)
      expect(CampaignImportPolicy.new(context, CampaignImport).download?).to be(false)
      expect(WhatsappApiCampaignPolicy.new(context, WhatsappApiCampaign).create?).to be(false)
    end

    it 'gives campaign_manage full campaign access' do
      context = context_for(custom_role_user('campaign_manage'))

      expect(CampaignPolicy.new(context, Campaign).create?).to be(true)
      expect(EmailCampaignPolicy.new(context, email_campaign).send_now?).to be(true)
      expect(CampaignImportPolicy.new(context, CampaignImport).confirm?).to be(true)
      expect(WhatsappApiCampaignPolicy.new(context, WhatsappApiCampaign).create?).to be(true)
      expect(EmailSenderIdentityPolicy.new(context, EmailSenderIdentity).create?).to be(true)
    end

    it 'keeps campaigns closed to plain agents' do
      context = context_for(agent)

      expect(CampaignPolicy.new(context, Campaign).index?).to be(false)
      expect(EmailCampaignPolicy.new(context, email_campaign).index?).to be(false)
    end
  end

  describe 'InboxPolicy' do
    let(:inbox) { create(:inbox, account: account) }

    it 'lets inbox_view open settings of any inbox without joining its conversations' do
      user = custom_role_user('inbox_view')
      context = context_for(user)
      Current.user = user # InboxPolicy#show? reads the member inboxes from Current.user and Current.account
      Current.account = account

      expect(InboxPolicy.new(context, inbox).settings?).to be(true)
      expect(InboxPolicy.new(context, inbox).show?).to be(false)
      expect(InboxPolicy.new(context, inbox).update?).to be(false)
      expect(InboxPolicy.new(context, inbox).manage_csat_templates?).to be(false)
    end

    it 'lets inbox_manage configure inboxes but not read their credentials' do
      context = context_for(custom_role_user('inbox_manage'))

      expect(InboxPolicy.new(context, inbox).update?).to be(true)
      expect(InboxPolicy.new(context, inbox).create?).to be(true)
      expect(InboxPolicy.new(context, inbox).whatsapp_business_management_token?).to be(false)
      expect(InboxPolicy.new(context, inbox).reset_secret?).to be(false)
    end

    it 'gives campaign_view the inbox campaigns listing' do
      expect(InboxPolicy.new(context_for(custom_role_user('campaign_view')), inbox).campaigns?).to be(true)
      expect(InboxPolicy.new(context_for(agent), inbox).campaigns?).to be(false)
    end
  end

  describe 'Autonomia::Agents::FaqSuggestionPolicy' do
    it 'splits review (view) from approval (manage)' do
      viewer = context_for(custom_role_user('autonomia_view'))
      manager = context_for(custom_role_user('autonomia_manage'))
      policy_class = Autonomia::Agents::FaqSuggestionPolicy

      expect(policy_class.new(viewer, nil).index?).to be(true)
      expect(policy_class.new(viewer, nil).approve?).to be(false)
      expect(policy_class.new(manager, nil).approve?).to be(true)
      expect(policy_class.new(context_for(agent), nil).index?).to be(false)
    end
  end

  describe 'CannedResponsePolicy' do
    it 'keeps plain agents managing canned responses and gates custom roles by canned_response_manage' do
      expect(CannedResponsePolicy.new(context_for(agent), CannedResponse).create?).to be(true)
      expect(CannedResponsePolicy.new(context_for(custom_role_user('contact_manage')), CannedResponse).create?).to be(false)
      expect(CannedResponsePolicy.new(context_for(custom_role_user('canned_response_manage')), CannedResponse).destroy?).to be(true)
    end
  end

  describe 'settings keys' do
    it 'gate label, attribute, automation and SLA writes by their keys' do
      context = context_for(custom_role_user('label_manage', 'attribute_manage', 'automation_view', 'sla_manage'))

      expect(LabelPolicy.new(context, Label).create?).to be(true)
      expect(CustomAttributeDefinitionPolicy.new(context, CustomAttributeDefinition).update?).to be(true)
      expect(AutomationRulePolicy.new(context, AutomationRule).index?).to be(true)
      expect(AutomationRulePolicy.new(context, AutomationRule).create?).to be(false)
      expect(SlaPolicyPolicy.new(context, SlaPolicy).destroy?).to be(true)
    end

    it 'keeps plain agents out of settings writes' do
      context = context_for(agent)

      expect(LabelPolicy.new(context, Label).create?).to be(false)
      expect(AutomationRulePolicy.new(context, AutomationRule).index?).to be(false)
      expect(SlaPolicyPolicy.new(context, SlaPolicy).create?).to be(false)
    end

    it 'lets macro_manage edit team-wide macros' do
      macro = create(:macro, account: account, visibility: :global, created_by: admin, updated_by: admin)

      expect(MacroPolicy.new(context_for(custom_role_user('macro_manage')), macro).update?).to be(true)
      expect(MacroPolicy.new(context_for(agent), macro).update?).to be(false)
    end
  end

  describe 'help center read-only' do
    let(:portal) { create(:portal, account_id: account.id) }
    let(:article) { create(:article, portal: portal, account_id: account.id, author_id: admin.id) }

    it 'lets knowledge_base_view read articles without editing them' do
      context = context_for(custom_role_user('knowledge_base_view'))

      expect(ArticlePolicy.new(context, article).show?).to be(true)
      expect(ArticlePolicy.new(context, article).update?).to be(false)
    end
  end
end
