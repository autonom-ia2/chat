# Demo do #2215 (protótipo): caixa do Instagram com conversas que nasceram de comentário (#2212). Só banco da demo.
# Flags da conta 1 iguais às da conta 1 hub em produção (lidas em 04/11/2026, só leitura).
account = Account.find(1)
account.update_columns(feature_flags: 9_094_241_222_486_130_663, feature_flags_ext_1: 9_223_372_036_854_742_007, # rubocop:disable Rails/SkipsModelValidations
                       feature_flags_ext_2: 8_388_599)

Channel::Instagram.skip_callback(:commit, :after, :subscribe)
canal = Channel::Instagram.find_or_create_by!(account: account, instagram_id: '17841400000000001') do |c|
  c.access_token = 'demo-sem-token'
  c.expires_at = 60.days.from_now
end
inbox = Inbox.find_or_create_by!(account: account, channel: canal) { |i| i.name = 'Instagram @clinica.vida' }
User.where(email: 'john@acme.inc').find_each { |u| InboxMember.find_or_create_by!(inbox: inbox, user: u) }

def conversa!(account, inbox, dados)
  nome, ig_id, comentario, onde, mensagens = dados.values_at(:nome, :ig_id, :comentario, :onde, :mensagens)
  contact_inbox = ContactInboxWithContactBuilder.new(source_id: ig_id, inbox: inbox, contact_attributes: { name: nome }).perform
  conv = Conversation.create!(account: account, inbox: inbox, contact: contact_inbox.contact, contact_inbox: contact_inbox, status: :open,
                              additional_attributes: { 'meta_ads_comment' => { 'network' => 'instagram', 'comment_id' => "179#{ig_id}",
                                                                               'post_id' => '18000000000000001', 'from_id' => ig_id,
                                                                               'ad_id' => (onde == :anuncio ? '120000000000001' : nil) }.compact })
  inicio = 50.minutes.ago
  chave = onde == :anuncio ? 'commented_ad' : 'commented_post'
  Message.create!(account: account, inbox: inbox, conversation: conv, message_type: :activity, created_at: inicio,
                  content: I18n.with_locale(:pt_BR) { I18n.t("conversations.activity.meta_ads_comment.#{chave}", text: comentario) })
  mensagens.each_with_index do |(tipo, texto), i|
    Message.create!(account: account, inbox: inbox, conversation: conv, message_type: tipo, content: texto,
                    created_at: inicio + (i + 1).minutes, sender: (tipo == :incoming ? contact_inbox.contact : nil))
  end
  conv
end

conversa!(account, inbox, { nome: 'marina.costa', ig_id: '9100000000000001', onde: :post,
                            comentario: 'Quanto custa o plano para família de 4 pessoas? Tem carência para consulta?',
                            mensagens: [[:outgoing, 'Oi, Marina! Vi seu comentário no post. Me conta as idades que eu mando os valores 😊'],
                                        [:incoming, '38, 36, 9 e 5 anos. Somos de Campinas.']] })
conversa!(account, inbox, { nome: 'rafa.lopes', ig_id: '9100000000000002', onde: :anuncio,
                            comentario: 'Golpe! Paguei e ninguém me atende!!',
                            mensagens: [] })
puts "inbox #{inbox.id}; conversas: #{inbox.conversations.pluck(:display_id).join(', ')}"
