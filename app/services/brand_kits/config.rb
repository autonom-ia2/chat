# Chave geral da identidade visual (#1076): BRAND_KITS_ENABLED=false esconde as telas, recusa a API e faz o
# e-mail com IA ignorar os kits — rollback sem deploy. Ligada por padrão.
module BrandKits::Config
  module_function

  def enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('BRAND_KITS_ENABLED', true)) == true
  end
end
