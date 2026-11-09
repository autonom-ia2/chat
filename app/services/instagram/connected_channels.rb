# O mesmo Instagram pode estar ligado em mais de uma conta (#2781), como a Página no Messenger
# (Integrations::Facebook::MessageCreator entrega a todas as caixas da Página). Devolve um canal por conta, em ordem de
# id: o do login do Instagram e, na conta que não tem esse canal, a Página com o Instagram ligado. É a regra de antes
# ("login do Instagram primeiro, Página depois"), agora aplicada a cada conta.
class Instagram::ConnectedChannels
  def self.for(instagram_id)
    return [] if instagram_id.blank?

    instagram = Channel::Instagram.where(instagram_id: instagram_id.to_s).order(:id).to_a
    pages = Channel::FacebookPage.where(instagram_id: instagram_id.to_s).where.not(account_id: instagram.map(&:account_id)).order(:id)
    instagram + pages.to_a.uniq(&:account_id)
  end
end
