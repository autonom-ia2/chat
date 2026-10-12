# minha_empresa.* (#1331): o rodapé do Kit da marca padrão da conta (`brand_kits.appearance.footer`, #1076), o mesmo
# que o e-mail com IA usa. Só leitura. Sem kit, ou sem nome no rodapé, o nome é o da conta.
class TemplateFields::AccountResolver
  include TemplateFields::FieldReader

  READERS = {
    'minha_empresa.nome' => :name, 'minha_empresa.endereco' => :address,
    'minha_empresa.telefone' => :phone, 'minha_empresa.site' => :website
  }.freeze

  def initialize(account)
    @account = account
  end

  private

  attr_reader :account

  def footer
    @footer ||= (default_kit&.appearance_data || {}).fetch('footer', nil).to_h
  end

  def default_kit
    BrandKit.live.find_by(account_id: account.id, is_default: true)
  end

  def name
    footer['company_name'].presence || account.name
  end

  def address
    footer['address']
  end

  def phone
    footer['phone']
  end

  def website
    footer['website']
  end
end
