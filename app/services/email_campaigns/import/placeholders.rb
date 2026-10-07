# Images the importer puts where it cannot place the original (#1099), served by the installation itself:
# UNRESOLVED marks a part the converter did not understand (the AI rebuilds it on request, delivery D; until then the
# saving is blocked, since the placeholder is not the part) and MISSING an image that could not be used (relative path,
# SVG...). Both are swapped by the person in the editor. A section whose background image could not be used carries
# MISSING_BACKGROUND_CLASS instead, so the check before saving sees it in the MJML.
module EmailCampaigns::Import::Placeholders
  UNRESOLVED_SRC = '/email-templates/importacao/trecho-pendente.png'.freeze
  MISSING_SRC = '/email-templates/importacao/imagem-pendente.png'.freeze
  UNRESOLVED_CLASS = 'import-unresolved'.freeze
  MISSING_CLASS = 'import-missing'.freeze
  MISSING_BACKGROUND_CLASS = 'import-missing-background'.freeze
end
