require 'rails_helper'

# #2454: a resposta dentro de um comentário, com a flag meta_ads_comentarios_ia (a do cuidado).
RSpec.describe Crm::MetaAds::ComentariosIa::Cuidar do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
  let(:rede) do
    instance_double(Crm::MetaAds::ComentariosIa::Rede::Instagram, responder: true, esconder: true, privado_disponivel?: true,
                                                                  ler_pai: 'Tem em azul?')
  end
  let(:classificador) { instance_double(Crm::MetaAds::ComentariosIa::Classificador) }
  let(:conversa) { class_double(Crm::MetaAds::ComentariosIa::Conversa) }
  let(:registro) { class_double(Crm::MetaAds::ComentariosIa::Registro) }
  let(:conversation) { instance_double(Conversation, id: 77, created_at: 1.minute.from_now) }
  let(:agora) { 1.minute.ago }

  # A resposta da cliente ao comentário c-1 (o de cima).
  def resposta(**mudancas)
    Crm::MetaAds::ComentariosIa::Comentario.new(
      network: 'instagram', account_id: account.id, inbox_id: inbox.id, owner_id: 'ig-1', post_id: '1790', ad_id: nil,
      comment_id: 'c-2', parent_id: 'c-1', from_id: 'igsid-1', created_time: agora, **mudancas
    )
  end

  def cuidar(item = resposta)
    described_class.new(item, rede: rede, classificador: classificador, conversa: conversa, registro: registro).call
  end

  def decide(decisao)
    avaliacao = Crm::MetaAds::ComentariosIa::Classificador::Avaliacao.new(chave: decisao, escolha: decisao, certeza: 0.9)
    allow(classificador).to receive(:avaliar!).and_return(avaliacao)
  end

  before do
    account.enable_features!(described_class::FLAG)
    allow(registro).to receive_messages(reservar!: true, vez: 0, gravar!: true, vincular!: 1, soltar!: 1,
                                        reservar_pessoa!: true, soltar_pessoa!: 1, decisao!: 1)
    allow(conversa).to receive_messages(anotar!: conversation, para_voce!: conversation)
    allow(rede).to receive_messages(privado: Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: conversation),
                                    ler: { text: 'Quanto custa o azul?', from_name: 'carla.mendes' })
  end

  it 'a resposta de cliente é decidida como um comentário próprio, com o comentário de cima à parte' do
    decide('hide')

    cuidar

    expect(registro).to have_received(:reservar!).with(resposta)
    expect(classificador).to have_received(:avaliar!).with('Quanto custa o azul?', pai: 'Tem em azul?')
    expect(rede).to have_received(:esconder)
  end

  it 'o comentário de cima que não dá para ler: decide só com a resposta' do
    decide('no_reply')
    allow(rede).to receive(:ler_pai).and_return(nil)

    cuidar

    expect(classificador).to have_received(:avaliar!).with('Quanto custa o azul?', pai: nil)
  end

  it 'a Meta não responde à leitura do comentário de cima: solta a leitura e sobe, para o job tentar de novo' do
    allow(rede).to receive(:ler_pai).and_raise(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)

    expect { cuidar }.to raise_error(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
    expect(registro).to have_received(:soltar!).with(anything, 'ai_seen')
  end

  describe 'a resposta da própria conta' do
    before { allow(classificador).to receive(:avaliar!) }

    it 'a frase pública que a IA posta não volta para ela: nada é reservado, lido nem decidido' do
      cuidar(resposta(comment_id: 'c-3', from_id: 'ig-1'))

      expect(registro).not_to have_received(:reservar!)
      expect(rede).not_to have_received(:ler)
      expect(classificador).not_to have_received(:avaliar!)
    end

    it 'a Página ou o perfil da caixa respondendo, mesmo sem o dono no evento: ignorada' do
      allow(inbox).to receive(:channel).and_return(instance_double(Channel::Instagram, instagram_id: 'ig-9'))
      allow(Inbox).to receive(:find_by).and_return(inbox)

      cuidar(resposta(owner_id: nil, from_id: 'ig-9'))

      expect(registro).not_to have_received(:reservar!)
    end

    it 'o autor só aparece na leitura (comentário da lista): solta a leitura, sem IA' do
      allow(rede).to receive(:ler).and_return({ text: 'Te mandei no privado!', from_name: 'loja', from_id: 'ig-1' })

      cuidar(resposta(from_id: nil))

      expect(classificador).not_to have_received(:avaliar!)
      expect(registro).to have_received(:soltar!).with(anything, 'ai_seen')
    end
  end

  describe 'privado para resposta: vai à Meta, que decide (o teste real é do produto, na conta piloto)' do
    def recusa(codigo, subcodigo = nil)
      Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: 'meta_refused', codigo: codigo, subcodigo: subcodigo)
    end

    it 'a Meta aceita: o privado sai, e a resposta ganha a frase pública da vez, como no comentário de cima' do
      decide('private')

      cuidar

      expect(rede).to have_received(:privado).with(care)
      expect(registro).to have_received(:reservar_pessoa!)
      expect(rede).to have_received(:responder).with(care.resposta_publica('private', 0))
    end

    it 'a Meta recusa, com código conhecido ou desconhecido: final, sem nova tentativa; preço com frase só pública responde aqui' do
      care.update!(price_reply: 'Custa R$ 490.')
      decide('price')
      [recusa(10, 2_018_278), recusa(987_654)].each do |envio|
        allow(rede).to receive(:privado).and_return(envio)

        expect { cuidar }.not_to raise_error
      end

      expect(rede).to have_received(:responder).with('Custa R$ 490.').twice
      expect(registro).to have_received(:soltar_pessoa!).twice
      expect(registro).not_to have_received(:soltar!)
      expect(conversa).not_to have_received(:para_voce!)
    end

    # Graph API, "Rate Limiting" (developers.facebook.com/docs/graph-api/overview/rate-limiting): 4, 17, 32, 613 e os
    # de caso de uso da Página, do Instagram e do Messenger (80001, 80002, 80006); mais o HTTP 429.
    it 'limite de chamadas da Meta não é recusa: passageiro, o job tenta de novo, sem soltar a pessoa nem decidir pelo dono' do
      decide('private')
      envios = [4, 17, 32, 613, 80_001, 80_002, 80_006].map { |codigo| recusa(codigo) }
      envios << Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: 'meta_refused', http: 429)

      envios.each do |envio|
        allow(rede).to receive(:privado).and_return(envio)

        expect { cuidar }.to raise_error(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
      end

      expect(registro).to have_received(:soltar!).with(anything, 'ai_seen').exactly(envios.size).times
      expect(registro).not_to have_received(:soltar_pessoa!)
      expect(registro).not_to have_received(:gravar!)
      expect(rede).not_to have_received(:responder)
      expect(conversa).not_to have_received(:para_voce!)
    end

    it 'no comentário de primeiro nível, o limite segue a regra de hoje' do
      decide('private')
      allow(rede).to receive(:privado).and_return(recusa(4))

      cuidar(resposta(parent_id: nil))

      expect(conversa).to have_received(:para_voce!).with(anything, care, 'private_reply_failed')
    end

    it 'a Meta recusa e não há frase pública que não prometa o privado: fica com o dono, sem resposta' do
      decide('private')
      allow(rede).to receive(:privado).and_return(recusa(100, 33))

      cuidar

      expect(rede).not_to have_received(:responder)
      expect(registro).to have_received(:gravar!).with(anything, described_class::FICA_COM_O_DONO)
      expect(conversa).not_to have_received(:para_voce!)
    end

    it 'recusa sem código da Meta e falha passageira seguem a regra de hoje' do
      decide('private')
      allow(rede).to receive(:privado).and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: 'invalid_text'))
      cuidar
      expect(conversa).to have_received(:para_voce!).with(anything, care, 'private_reply_failed')

      allow(rede).to receive(:privado).and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, talvez_entregue: true, codigo: 2))
      cuidar
      expect(conversa).to have_received(:para_voce!).with(anything, care, 'private_reply_unsure')
      expect(rede).not_to have_received(:responder)
    end

    it 'um privado por pessoa continua valendo: quem já recebeu no comentário de cima não recebe outro' do
      decide('private')
      allow(registro).to receive(:reservar_pessoa!).and_return(false)

      cuidar

      expect(rede).not_to have_received(:privado)
      expect(registro).to have_received(:gravar!).with(anything, 'private_reply_already')
    end
  end

  it 'reclamação na resposta: passa para a pessoa, como no comentário de cima' do
    decide('to_you')

    cuidar

    expect(conversa).to have_received(:para_voce!).with(anything, care, 'to_you')
  end

  it 'a resposta numa caixa de outra conta: a conta não vê nada' do
    outra = create(:account)
    outra.enable_features!(described_class::FLAG)
    allow(classificador).to receive(:avaliar!)

    cuidar(resposta(account_id: outra.id))

    expect(registro).not_to have_received(:reservar!)
    expect(classificador).not_to have_received(:avaliar!)
  end
end
