# The search by conversation (#2277) only runs on the account's own AI key (the "IA do CRM" integration). The
# resolver falls back to the installation key, which must never pay for a client's search: without the account's
# key there is no search, and the screen asks the admin to connect one.
module ConversationAudience::Credential
  module_function

  def for(account)
    credential = Crm::Ai::CredentialResolver.new(account: account).resolve
    credential if credential.present? && credential[:source] == :hook
  end
end
