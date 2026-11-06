# Login único (#2338): as Páginas que vieram do "Entrar com o Facebook" dos Anúncios, para o passo "Confira a Página".
#
# Só com o token do próprio cliente: no modo `partner` o token é o da plataforma, e `me/accounts` traria Páginas da
# plataforma (ou de outros clientes) para esta conta (o mesmo cuidado do Crm::MetaAds::AdManagement#pages).
# `linked`: a Página já tem caixa nesta conta. `declined_permissions`: o que a pessoa recusou na janela da Meta.
class Crm::MetaAds::LoginUnico::Paginas
  def initialize(connection)
    @connection = connection
  end

  # { pages: [...], declined_permissions: [...] }, ou nil quando a Meta não respondeu.
  def call
    return { pages: [], declined_permissions: [] } unless @connection.own_token?

    result = client.login_pages
    return unless result.ok

    { pages: pages(Array(result.data['data'])), declined_permissions: declined }
  end

  private

  def client
    @client ||= Meta::AdsGraphClient.new(access_token: @connection.read_token)
  end

  def pages(rows)
    linked = Channel::FacebookPage.where(account_id: @connection.account_id, page_id: rows.pluck('id')).pluck(:page_id)
    rows.filter_map do |row|
      next unless row.is_a?(Hash) && row['id'].present? && row['name'].present?

      { id: row['id'], name: row['name'], category: row['category'], followers: row['followers_count'],
        instagram: instagram(row['instagram_business_account']), linked: linked.include?(row['id']) }
    end
  end

  def instagram(account)
    return unless account.is_a?(Hash) && account['username'].present?

    { username: account['username'], followers: account['followers_count'] }
  end

  # Sem a lista de permissões o passo segue: a Página vale do mesmo jeito, só não dá para dizer o que faltou.
  def declined
    result = client.permissions
    return [] unless result.ok

    Array(result.data['data']).filter_map { |row| row['permission'] if row.is_a?(Hash) && row['status'] == 'declined' }
  end
end
