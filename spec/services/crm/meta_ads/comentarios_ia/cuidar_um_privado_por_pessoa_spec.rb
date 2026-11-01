require 'rails_helper'

# Um privado por pessoa em cada post, com o Registro de verdade (índices únicos no banco): a reserva da pessoa nasce
# antes da Meta, então nem dois jobs ao mesmo tempo nem um envio sem conversa gravada levam a um segundo privado.
RSpec.describe Crm::MetaAds::ComentariosIa::Cuidar do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:rede) { instance_double(Crm::MetaAds::ComentariosIa::Rede::Instagram, responder: true, privado_disponivel?: true) }
  let(:avaliacao) { Crm::MetaAds::ComentariosIa::Classificador::Avaliacao.new(chave: 'private', escolha: 'private', certeza: 0.91) }
  let(:classificador) { instance_double(Crm::MetaAds::ComentariosIa::Classificador, avaliar!: avaliacao) }
  let(:conversa) { class_double(Crm::MetaAds::ComentariosIa::Conversa, anotar!: nil) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:enviado) { Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: conversation) }

  def comentario(comment_id, from_id: 'igsid-1')
    Crm::MetaAds::ComentariosIa::Comentario.new(network: 'instagram', account_id: account.id, inbox_id: inbox.id, post_id: '1790',
                                                comment_id: comment_id, from_id: from_id, created_time: 1.minute.ago)
  end

  def cuidar(item)
    described_class.new(item, rede: rede, classificador: classificador, conversa: conversa).call
  end

  before do
    account.enable_features!(described_class::FLAG)
    create(:crm_meta_ads_comment_care, account: account, target_id: '1790')
    allow(rede).to receive_messages(ler: { text: 'Quanto custa?', from_name: 'carla' }, privado: enviado)
  end

  it 'dois comentários da mesma pessoa em jobs ao mesmo tempo: um privado só' do
    # O segundo job roda enquanto o primeiro está na chamada à Meta.
    segundo = false
    allow(rede).to receive(:privado) do
      unless segundo
        segundo = true
        cuidar(comentario('c-2'))
      end
      enviado
    end

    cuidar(comentario('c-1'))

    expect(rede).to have_received(:privado).once
    expect(Crm::MetaAdsCommentPerson.sole).to have_attributes(account_id: account.id, post_id: '1790', from_id: 'igsid-1', comment_id: 'c-1')
  end

  it 'a escolha da IA, a certeza e o motivo ficam na linha ai_seen do comentário, e só nela (#2424)' do
    cuidar(comentario('c-1'))

    acoes = Crm::MetaAdsCommentAction.where(account_id: account.id, comment_id: 'c-1')
    expect(acoes.find_by(action: 'ai_seen')).to have_attributes(ai_decision: 'private', ai_confidence: BigDecimal('0.91'))
    expect(acoes.where.not(action: 'ai_seen').pluck(:ai_decision)).to all(be_nil)
  end

  it 'a Meta aceitou e a conversa não foi gravada: o próximo comentário da pessoa não recebe outro privado' do
    allow(rede).to receive(:privado).and_return(Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: true, conversation: nil))

    cuidar(comentario('c-1'))
    cuidar(comentario('c-2'))

    expect(rede).to have_received(:privado).once
  end

  it 'o reenvio do mesmo comentário (webhook repetido, job de novo) não manda de novo nem pergunta à IA' do
    cuidar(comentario('c-1'))
    cuidar(comentario('c-1'))

    expect(rede).to have_received(:privado).once
    expect(classificador).to have_received(:avaliar!).once
  end

  it 'privado recusado pela Meta: a reserva sai, e o próximo comentário da pessoa pode receber' do
    allow(conversa).to receive(:para_voce!).and_return(conversation)
    recusa = Crm::MetaAds::ComentariosIa::Rede::Envio.new(ok: false, erro: 'meta_refused')
    allow(rede).to receive(:privado).and_return(recusa, enviado)

    cuidar(comentario('c-1'))
    cuidar(comentario('c-2'))

    expect(rede).to have_received(:privado).twice
    expect(Crm::MetaAdsCommentPerson.sole.comment_id).to eq('c-2')
  end

  it 'a pessoa já recebeu o privado de alguém na tela (#2196): a IA não manda outro e o painel diz por quê' do
    Crm::MetaAdsCommentPerson.create!(account: account, network: 'instagram', post_id: '1790', from_id: 'igsid-1', comment_id: 'c-0')

    cuidar(comentario('c-1'))

    expect(rede).not_to have_received(:privado)
    expect(Crm::MetaAdsCommentAction.find_by(comment_id: 'c-1', action: 'private_reply_already')).to be_present
  end

  it 'outra pessoa no mesmo post recebe o seu' do
    cuidar(comentario('c-1'))
    cuidar(comentario('c-2', from_id: 'igsid-2'))

    expect(rede).to have_received(:privado).twice
  end
end
