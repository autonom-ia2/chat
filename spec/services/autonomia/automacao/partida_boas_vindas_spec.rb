require 'rails_helper'

# A receita pronta Boas-vindas (#2526), como sai de automacao-receitas.yml, ligada numa conta: o filtro do gatilho só
# deixa começar na primeira mensagem do cliente, numa conversa que o cliente começou. Nada sai na conversa que a equipe
# ou a plataforma abriu, nem na conversa que o cliente reabre.
RSpec.describe Autonomia::Automacao::Partida, :automacao_motor do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:receita) { Autonomia::Automacao::Catalogo.receitas.find { |item| item['chave'] == 'BOAS_VINDAS' }.fetch('receita') }
  let(:definicao) do
    create(:autonomia_automacao, account: account, ligada_por: admin).tap do |automacao|
      automacao.salvar_versao!(receita: receita, autor: admin)
      automacao.update!(ativa: true)
    end
  end
  let(:conversa) { create(:conversation, account: account, status: :open) }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  def mensagem(message_type, alvo = conversa, **atributos)
    create(:message, conversation: alvo, account: account, inbox: alvo.inbox, message_type: message_type, **atributos)
  end

  # A Escuta pode já ter começado pela mesma mensagem: o que vale é a execução aberta para a conversa.
  def comecou?(disparo)
    Autonomia::Automacao::Partida.new(definicao: definicao, alvo: disparo.conversation.reload, chave_gatilho: 'mensagem.criada',
                                      mensagem: disparo).call
    Autonomia::Automacao::Execucao.exists?(automacao_id: definicao.id, alvo: disparo.conversation)
  end

  it 'começa na primeira mensagem do cliente, na conversa que ele começou' do
    expect(comecou?(mensagem(:incoming))).to be(true)
  end

  it 'não começa na segunda mensagem do cliente, nem na resposta da equipe, nem na nota', :aggregate_failures do
    mensagem(:incoming)

    expect(comecou?(mensagem(:incoming))).to be(false)
    expect(comecou?(mensagem(:outgoing))).to be(false)
    expect(comecou?(mensagem(:outgoing, private: true))).to be(false)
  end

  it 'não começa na conversa que a equipe abriu: Nova conversa, modelo ou campanha', :aggregate_failures do
    [[:outgoing, {}], [:template, {}], [:outgoing, { additional_attributes: { 'campaign_id' => 1 } }]].each do |message_type, atributos|
      aberta = create(:conversation, account: account, status: :open)
      mensagem(message_type, aberta, **atributos)

      expect(comecou?(mensagem(:incoming, aberta))).to be(false), "#{message_type} #{atributos}"
    end
  end

  it 'não começa quando o cliente reabre a conversa resolvida' do
    mensagem(:incoming)
    conversa.update!(status: :resolved)

    expect(comecou?(mensagem(:incoming))).to be(false)
  end

  # Coexistência do WhatsApp: o histórico entra depois, com a data original. A mensagem antiga é a primeira.
  it 'não começa quando o histórico importado mostra que a conversa já existia' do
    nova = mensagem(:incoming)
    mensagem(:incoming, created_at: 2.days.ago)

    expect(comecou?(nova)).to be(false)
  end

  describe 'conversa que nasce de comentário' do
    let(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
    let(:instagram) { create(:channel_instagram, account: account).inbox }
    let(:pagina) do
      stub_request(:post, %r{graph\.facebook\.com/.*/subscribed_apps})
      create(:inbox, account: account, channel: create(:channel_facebook_page, account: account))
    end

    before { allow(Crm::Entrega).to receive(:new).and_return(instance_double(Crm::Entrega, call: nil)) }

    def comentario(rede, caixa)
      Crm::MetaAds::ComentariosIa::Comentario.new(
        network: rede, account_id: account.id, inbox_id: caixa.id, owner_id: 'dono-1', post_id: '1790', ad_id: nil,
        comment_id: "c-#{rede}", parent_id: nil, from_id: "autor-#{rede}", from_name: 'carla.mendes', text: 'Ninguém me responde',
        created_time: 1.minute.ago
      )
    end

    # A IA passou o comentário à equipe: a conversa nasce só com atividade, e o cliente escreve depois no direct.
    it 'não começa quando o cliente escreve na conversa que a IA abriu para a equipe, no Instagram e no Facebook',
       :aggregate_failures do
      [['instagram', instagram], ['facebook', pagina]].each do |rede, caixa|
        aberta = Crm::MetaAds::ComentariosIa::Conversa.para_voce!(comentario(rede, caixa), care, 'to_you')

        expect(comecou?(mensagem(:incoming, aberta))).to be(false), rede
      end
    end

    it 'não começa quando o cliente responde ao privado que a IA mandou' do
      privado = create(:conversation, account: account, inbox: instagram, status: :open)
      mensagem(:outgoing, privado, source_id: 'mid-1')
      Crm::MetaAds::ComentariosIa::Conversa.anotar!(privado, comentario('instagram', instagram), care, nova: true)

      expect(comecou?(mensagem(:incoming, privado))).to be(false)
    end
  end
end
