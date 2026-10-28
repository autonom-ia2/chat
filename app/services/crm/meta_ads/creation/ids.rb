# IDs da Meta que entram no caminho da Graph (#2198): só dígitos, para que `?`, `/` ou `&` não virem outro caminho ou
# parâmetros extras na chamada (mesma regra do Crm::MetaAds::AdManagement).
module Crm::MetaAds::Creation::Ids
  def self.numeric?(value)
    value.is_a?(String) && value.present? && value.each_char.all? { |char| char.between?('0', '9') }
  end
end
