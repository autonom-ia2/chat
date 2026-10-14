# O catálogo de produtos da WABA de uma caixa do WhatsApp oficial (#1418, épico #1320), para a Nova campanha escolher os
# produtos. Só leitura, só com a flag `whatsapp_campaign_products` (sem ela, 404 antes de qualquer chamada à Meta), e só
# para quem vê os modelos (`whatsapp_templates_view`). A WABA e o catálogo são sempre os da caixa: nada no pedido os
# escolhe (`Whatsapp::Templates::CatalogClient`).
class Api::V1::Accounts::Inboxes::WhatsappCatalogsController < Api::V1::Accounts::BaseController
  before_action :ensure_feature_enabled
  before_action :fetch_inbox
  before_action :check_authorization

  rescue_from Whatsapp::Templates::CatalogClient::NoCatalog, with: :catalog_missing
  rescue_from Whatsapp::Templates::MetaClient::Unreachable, with: :meta_unreachable
  rescue_from Whatsapp::Templates::MetaClient::MetaError, with: :meta_refused

  def show
    catalog = client.catalog
    render json: { catalog: catalog && { name: catalog.name, product_count: catalog.product_count } }
  end

  def products
    page = client.products(search: params[:q], after: params[:after])
    render json: { payload: page.products.map(&:to_h), meta: { after: page.after } }
  end

  private

  def ensure_feature_enabled
    render_error('feature_disabled', :not_found) unless Current.account.feature_enabled?('whatsapp_campaign_products')
  end

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
    render_error('inbox_not_supported', :not_found) unless Whatsapp::Templates::MetaClient.supported?(@inbox)
  end

  def check_authorization
    authorize(WhatsappTemplateProfile, :index?, policy_class: WhatsappTemplatePolicy)
  end

  def client
    @client ||= Whatsapp::Templates::CatalogClient.new(inbox: @inbox)
  end

  # Os três abaixo rodam fora do `around_action` do idioma (#1419): cada um reabre o idioma da pessoa ou da conta.
  def catalog_missing
    switch_locale_using_account_locale { render_error('catalog_missing', :not_found) }
  end

  def meta_unreachable
    switch_locale_using_account_locale { render_error('meta_unreachable', :service_unavailable) }
  end

  # O texto da Meta nunca vai para a tela (#1394): falta de permissão tem texto nosso, o resto vai com o genérico.
  def meta_refused(error)
    code = error.code == 'permission_denied' ? 'catalog_permission_denied' : 'meta_failed'
    switch_locale_using_account_locale { render_error(code) }
  end

  def render_error(code, status = :unprocessable_entity)
    render json: { error: code, message: I18n.t("whatsapp_templates.errors.#{code}") }, status: status
  end
end
