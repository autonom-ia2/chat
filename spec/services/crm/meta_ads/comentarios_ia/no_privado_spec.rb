require 'rails_helper'

# #2481: o grupo "no privado" da gaveta Comentários em Agentes. As conversas do privado de um cuidado, as mesmas que o
# número `sent` conta (Painel.resultados), com quem, o comentário do topo, se a pessoa respondeu e o "Ver conversa".
RSpec.describe Crm::MetaAds::ComentariosIa::NoPrivado do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_instagram, account: account).inbox }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:care) { create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '1790', para_quem: 'Quem perguntar o preço') }
  let(:ve_tudo) { ->(_conversation) { true } }

  def lista(viewer: admin, acesso: ve_tudo, cuidado: care)
    described_class.new(account: account, care: cuidado, viewer: viewer, conversation_access: acesso).call
  end

  # A conversa como o motor a deixa (Conversa#anotar!): a origem, a atividade do comentário no topo e o privado.
  def conversa(nome, comentario, respondeu: false, horas: 1, origem: {})
    origem = { 'care_id' => care.id, 'network' => 'instagram', 'private_reply' => true }.merge(origem).compact
    conversation = create(:conversation, account: account, inbox: inbox, contact: create(:contact, account: account, name: nome),
                                         created_at: horas.hours.ago, additional_attributes: { 'meta_ads_comment' => origem })
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :activity,
                     content: "Comentou no post: “#{comentario}”", created_at: horas.hours.ago)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Te mandei os valores')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Quero!') if respondeu
    conversation
  end

  it 'lista quem recebeu, da mais nova para a mais velha, com o comentário do topo, se respondeu e o "Ver conversa"' do
    velha = conversa('Rafael', 'Qual o valor?', horas: 3)
    nova = conversa('Mariana', 'Quanto custa?', respondeu: true)

    expect(lista).to eq([
                          { id: nova.display_id, contato: 'Mariana', comentario: 'Comentou no post: “Quanto custa?”', network: 'instagram',
                            respondeu: true, conversation_path: "/app/accounts/#{account.id}/conversations/#{nova.display_id}" },
                          { id: velha.display_id, contato: 'Rafael', comentario: 'Comentou no post: “Qual o valor?”', network: 'instagram',
                            respondeu: false, conversation_path: "/app/accounts/#{account.id}/conversations/#{velha.display_id}" }
                        ])
  end

  it 'só as do privado deste cuidado: a conversa passada à pessoa (reclamação) e a de outro cuidado ficam fora' do
    outro = create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '1791', para_quem: 'Quem pedir')
    conversa('Reclamou', 'Péssimo', origem: { 'private_reply' => nil })
    conversa('De outro', 'Quanto custa?', origem: { 'care_id' => outro.id })
    minha = conversa('Mariana', 'Quanto custa?')

    expect(lista.pluck(:id)).to eq([minha.display_id])
  end

  it 'só as conversas que quem abre a tela vê (PermissionFilterService), como o número' do
    conversa('Mariana', 'Quanto custa?')
    agente = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agente, inbox: create(:inbox, account: account))

    expect(lista(viewer: agente)).to eq([])

    create(:inbox_member, user: agente, inbox: inbox)
    expect(lista(viewer: agente).size).to eq(1)
  end

  it 'sem acesso à conversa, sem o "Ver conversa"' do
    conversa('Mariana', 'Quanto custa?')

    expect(lista(acesso: ->(_conversation) { false }).sole[:conversation_path]).to be_nil
  end

  def consultas_de_uma_lista
    consultas = []
    contar = ->(*, dados) { consultas << dados[:sql] unless dados[:name] == 'SCHEMA' || dados[:sql].start_with?('SAVEPOINT', 'RELEASE') }
    resultado = ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { lista }
    [resultado, consultas.size]
  end

  it 'até LIMITE, com o mesmo número de consultas para uma conversa ou várias (sem N+1)' do
    stub_const("#{described_class}::LIMITE", 3)
    conversa('Pessoa 0', 'Quanto custa?')
    lista # aquece o que é carregado uma vez (a conta, a pessoa)
    _uma, com_uma = consultas_de_uma_lista
    4.times { |n| conversa("Pessoa #{n + 1}", 'Quanto custa?', horas: n + 2) }

    resultado, com_varias = consultas_de_uma_lista

    expect(resultado.pluck(:contato)).to eq(['Pessoa 0', 'Pessoa 1', 'Pessoa 2'])
    expect(com_varias).to eq(com_uma)
  end

  it 'sem cuidado, nada' do
    expect(lista(cuidado: nil)).to eq([])
  end
end
