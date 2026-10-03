# Shared SES error. Callers (provisioner, jobs, controller) rescue EmailCampaigns::Ses::Error.
# Lives in its own file so Zeitwerk can autoload it without loading the client first.
class EmailCampaigns::Ses::Error < StandardError; end
