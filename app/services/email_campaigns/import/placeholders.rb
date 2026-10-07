# Images the importer puts where it cannot place the original (#1099), served by the installation itself:
# UNRESOLVED marks a part the converter did not understand (the AI rebuilds it on request, delivery D) and MISSING an
# image that could not be used (relative path, SVG...). Both are swapped by the person in the editor.
module EmailCampaigns::Import::Placeholders
  UNRESOLVED_SRC = '/email-templates/importacao/trecho-pendente.png'.freeze
  MISSING_SRC = '/email-templates/importacao/imagem-pendente.png'.freeze
  UNRESOLVED_CLASS = 'import-unresolved'.freeze
  MISSING_CLASS = 'import-missing'.freeze
end
