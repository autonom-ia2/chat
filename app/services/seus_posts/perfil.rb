# Seus posts (#2302): um perfil é o canal de uma caixa da conta, do Instagram (login do Instagram) ou da Página do
# Facebook, com o id "instagram-12" ou "facebook-3" (o id do canal). Só canal com caixa nesta conta: é a caixa que tem
# as conversas e que o "Libere o acesso" reautoriza. A Página entra mesmo com instagram_id: o Chatwoot o grava em toda
# Página com Instagram ligado (#2321). Quem a pessoa vê é com SeusPosts::Caixa.
module SeusPosts::Perfil
  REDES = { 'instagram' => 'Channel::Instagram', 'facebook' => 'Channel::FacebookPage' }.freeze

  module_function

  def canais(account)
    com_caixa(account, Channel::Instagram) + com_caixa(account, Channel::FacebookPage)
  end

  # O canal do perfil `id` nesta conta; nil quando o id não é de perfil ou o canal é de outra conta.
  def achar(account, id)
    rede, numero = id.to_s.split('-', 2)
    return unless REDES.key?(rede) && digits?(numero)

    com_caixa(account, REDES[rede].constantize).find { |canal| canal.id == numero.to_i }
  end

  def id_do(canal)
    "#{rede(canal)}-#{canal.id}"
  end

  def rede(canal)
    canal.is_a?(Channel::Instagram) ? 'instagram' : 'facebook'
  end

  def com_caixa(account, klass)
    klass.where(account_id: account.id, id: Inbox.where(account_id: account.id, channel_type: klass.name).select(:channel_id))
         .includes(:inbox).order(:id).to_a
  end

  def digits?(text)
    text.present? && text.each_char.all? { |char| char.between?('0', '9') }
  end
end
