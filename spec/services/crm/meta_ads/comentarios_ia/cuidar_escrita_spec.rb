require 'rails_helper'

# #2458 (PR 2 do #2436): com a flag meta_ads_comentarios_ia_escreve, o privado e a frase do comentário são escritos pela
# IA (Escrita), os dois antes de qualquer envio. O que o agente não sabe, e o assunto proibido do dono, ficam com o dono.
# Sem agente que possa escrever, as frases fixas de hoje.
RSpec.describe Crm::MetaAds::ComentariosIa::Cuidar do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:care) { create(:crm_meta_ads_comment_care, account: account, target_id: '1790') }
  let(:rede) do
    instance_double(Crm::MetaAds::ComentariosIa::Rede::Instagram, responder: true, esconder: true, privado_disponivel?: true,
                                                                  legenda: 'Seguro viagem')
  end
  let(:classificador) { instance_double(Crm::MetaAds::ComentariosIa::Classificador) }
  let(:conversa) { class_double(Crm::MetaAds::ComentariosIa::Conversa) }
  let(:registro) { class_double(Crm::MetaAds::ComentariosIa::Registro) }
  let(:conversation) { instance_double(Conversation, id: 77, created_at: 1.minute.from_now) }
  let(:enviado) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: conversation) }
  let(:escrita) { instance_double(Crm::MetaAds::ComentariosIa::Escrita) }

  def comentario
    Crm::MetaAds::ComentariosIa::Comentario.new(
      network: 'instagram', account_id: account.id, inbox_id: inbox.id, owner_id: 'ig-1', post_id: '1790', ad_id: nil,
      comment_id: 'c-1', parent_id: nil, from_id: 'igsid-1', created_time: 1.minute.ago
    )
  end

  def cuidar
    described_class.new(comentario, rede: rede, classificador: classificador, conversa: conversa, registro: registro).call
  end

  def decide(decisao)
    avaliacao = Crm::MetaAds::ComentariosIa::Classificador::Avaliacao.new(chave: decisao, escolha: decisao, certeza: 0.9)
    allow(classificador).to receive(:avaliar!).and_return(avaliacao)
  end

  before do
    account.enable_features!(described_class::FLAG, Crm::MetaAds::ComentariosIa::Escrita::FLAG)
    allow(registro).to receive_messages(reservar!: true, vez: 0, gravar!: true, vincular!: 1, soltar!: 1,
                                        reservar_pessoa!: true, soltar_pessoa!: 1, decisao!: 1)
    allow(conversa).to receive_messages(anotar!: conversation, para_voce!: conversation)
    allow(rede).to receive_messages(privado: enviado, ler_pai: nil, ler: { text: 'Quanto custa?', from_name: 'carla.mendes' })
    allow(Crm::MetaAds::ComentariosIa::Escrita).to receive(:new).and_return(escrita)
  end

  it 'manda o privado e a frase escritos pela IA, pela caixa do comentário', :aggregate_failures do
    decide('private')
    ordem = []
    allow(escrita).to receive(:textos) do
      ordem << :escreveu
      { privado: 'Oi! O seguro sai R$ 39.', publico: 'Te mandei no direct!' }
    end
    allow(rede).to receive(:privado) { (ordem << :privado) && enviado }
    allow(rede).to receive(:responder) { (ordem << :responder) && true }

    cuidar

    expect(Crm::MetaAds::ComentariosIa::Escrita).to have_received(:new)
      .with(care: care, inbox: inbox, legenda: 'Seguro viagem', foto: nil)
    expect(escrita).to have_received(:textos).with('private', comentario: 'Quanto custa?', pai: nil)
    expect(rede).to have_received(:privado).with(care, texto: 'Oi! O seguro sai R$ 39.')
    expect(rede).to have_received(:responder).with('Te mandei no direct!')
    expect(ordem).to eq(%i[escreveu privado responder])
  end

  it 'o preço do dono vale no lugar da frase pública' do
    decide('price')
    allow(escrita).to receive(:textos).and_return(privado: 'Oi! O seguro sai R$ 39.')

    cuidar

    expect(rede).to have_received(:responder).with(care.price_reply)
  end

  it 'o agente não sabe: fica com o dono, sem privado e sem frase', :aggregate_failures do
    decide('private')
    allow(escrita).to receive(:textos).and_return(dono: 'no_knowledge')

    cuidar

    expect(registro).to have_received(:gravar!).with(an_object_having_attributes(comment_id: 'c-1'), described_class::FICA_COM_O_DONO)
    expect(registro).not_to have_received(:reservar_pessoa!)
    expect(rede).not_to have_received(:privado)
    expect(rede).not_to have_received(:responder)
  end

  it 'o assunto proibido do dono: fica com ele, sem escrever nada', :aggregate_failures do
    decide(Crm::MetaAds::ComentariosIa::Classificador::DONO)

    cuidar

    expect(registro).to have_received(:gravar!).with(an_object_having_attributes(comment_id: 'c-1'), described_class::FICA_COM_O_DONO)
    expect(Crm::MetaAds::ComentariosIa::Escrita).not_to have_received(:new)
    expect(rede).not_to have_received(:privado)
  end

  it 'frases fixas (sem agente que possa escrever): manda a mensagem e a frase do dono, como hoje', :aggregate_failures do
    decide('private')
    allow(escrita).to receive(:textos).and_return({})

    cuidar

    expect(rede).to have_received(:privado).with(care, texto: nil)
    expect(rede).to have_received(:responder).with(care.phrases.first)
  end

  it 'IA fora do ar ao escrever: nada sai, e o erro sobe para o job tentar de novo', :aggregate_failures do
    decide('private')
    allow(escrita).to receive(:textos).and_raise(Crm::MetaAds::ComentariosIa::Classificador::Indisponivel, 'writing_unavailable')

    expect { cuidar }.to raise_error(Crm::MetaAds::ComentariosIa::Classificador::Indisponivel)
    expect(rede).not_to have_received(:privado)
    expect(registro).not_to have_received(:reservar_pessoa!)
  end

  it 'flag da escrita desligada: as frases fixas, sem chamar a Escrita', :aggregate_failures do
    account.disable_features!(Crm::MetaAds::ComentariosIa::Escrita::FLAG)
    decide('private')

    cuidar

    expect(Crm::MetaAds::ComentariosIa::Escrita).not_to have_received(:new)
    expect(rede).to have_received(:privado).with(care, texto: nil)
  end
end
