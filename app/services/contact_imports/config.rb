# Importar contatos (#1006) is the campaign journey's contact import: it needs the journey
# (CAMPAIGN_JOURNEY_ENABLED) and the spreadsheet import jobs (CAMPAIGN_IMPORT_ENABLED). With
# either off, the Contacts menu keeps Chatwoot's own import and these endpoints answer 404.
# The dashboard applies the same rule (contactImportJourney.js).
class ContactImports::Config
  def self.enabled?
    CampaignJourney::Config.enabled? && CampaignImports::Config.enabled?
  end
end
