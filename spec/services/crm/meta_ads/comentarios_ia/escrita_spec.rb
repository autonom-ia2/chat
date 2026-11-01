require 'rails_helper'

# #2458 (PR 2 do #2436): a IA escreve a frase do comentário e a mensagem do privado, pelo agente da porta da caixa em que
# o comentário chegou. Sem agente que possa escrever, as frases fixas, nunca mudo: o motivo vai ao log, só com ids.
RSpec.describe Crm::MetaAds::ComentariosIa::Escrita do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:care) do
    create(:crm_meta_ads_comment_care, account: account, target_id: '1790', note: 'Atendo de segunda a sexta',
                                       tom: 'mais formal', offer: { 'offer' => 'Seguro viagem', 'price' => 'R$ 39' })
  end
  let(:formato) { Autonomia::Agents::Answerer::FormatoDoComentario }
  let(:chamadas) { [] }
  let(:resultado) { Autonomia::Agents::AnswerResult.new(reply: 'Te mandei no direct!', confidence: 0.9, handoff: { should: false }) }

  def agente(**atributos)
    Autonomia::Agents::Agent.create!(account: account, name: 'Porta', agent_type: 'custom', status: :active, enabled: true,
                                     **atributos)
  end

  def na_porta(agent, caixa = inbox)
    Autonomia::Agents::Operate::InboxConnector.new(agent: agent, inbox: caixa).perform(connect: true)
    agent
  end

  def escrita(caixa = inbox)
    described_class.new(care: care, inbox: caixa, legenda: 'Seguro viagem para a Europa', foto: 'Uma mala e um avião')
  end

  def com_chave!
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-da-conta' })
  end

  before do
    allow(Rails.logger).to receive(:info)
    allow(Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      chamadas << kwargs
      instance_double(Autonomia::Agents::Answerer, answer: resultado)
    end
  end

  describe 'agente da porta que pode falar com cliente' do
    before do
      com_chave!
      na_porta(agente)
    end

    it 'escreve no formato pedido, sem ferramenta nem busca, com o comentário como dado de terceiro', :aggregate_failures do
      escrito = escrita.escrever(formato::PUBLICO, comentario: 'Quanto custa?', pai: 'Alguém já fez?')

      expect(escrito).to have_attributes(status: :escrito, texto: 'Te mandei no direct!')
      chamada = chamadas.sole
      codigo = formato.codigo(care.id)
      expect(chamada).to include(formato: formato::PUBLICO, trust_instruction: false, allow_web_search: false, delivery: nil,
                                 audience: :customer, feature: described_class::FEATURE, retrieval_query: 'Quanto custa?')
      expect(chamada[:query]).to start_with("[COMENTARIO##{codigo}]")
      expect(JSON.parse(chamada[:query].split(': ', 2).last)).to eq(
        'comentario' => 'Quanto custa?', 'comentario_de_cima' => 'Alguém já fez?',
        'legenda_do_post' => 'Seguro viagem para a Europa', 'o_que_se_ve_na_foto' => 'Uma mala e um avião'
      )
      expect(chamada[:contexto_do_turno]).to include(formato.regra_do_dado(codigo), 'Seguro viagem', 'R$ 39',
                                                     'Atendo de segunda a sexta', 'mais formal')
    end

    it 'textos: o privado e o público, os dois escritos antes de qualquer envio' do
      expect(escrita.textos('private', comentario: 'Quanto custa?')).to eq(privado: 'Te mandei no direct!', publico: 'Te mandei no direct!')
      expect(chamadas.pluck(:formato)).to eq([formato::PRIVADO, formato::PUBLICO])
    end

    it 'textos: o preço que o dono escreveu vale no lugar da frase pública: só o privado é escrito', :aggregate_failures do
      care.update!(price_reply: 'R$ 39 no direct')

      expect(escrita.textos('price', comentario: 'Quanto custa?')).to eq(privado: 'Te mandei no direct!')
      expect(chamadas.pluck(:formato)).to eq([formato::PRIVADO])
    end

    it 'o agente não sabe: fica com o dono, com o motivo' do
      allow(resultado).to receive_messages(reply: 'fallback', handoff: { should: true, reason: 'no_knowledge' })

      expect(escrita.textos('private', comentario: 'Tem para Marte?')).to eq(dono: 'no_knowledge')
    end

    it 'a resposta fora do formato (longa, com o código) fica com o dono' do
      allow(resultado).to receive(:reply).and_return('a' * 301)

      expect(escrita.escrever(formato::PUBLICO, comentario: 'Quanto custa?')).to have_attributes(status: :fica_com_o_dono,
                                                                                                 motivo: 'reply_out_of_format')
    end

    it 'IA fora do ar: Indisponivel, para o job tentar de novo antes de qualquer envio' do
      allow(resultado).to receive(:error).and_return('timeout')

      expect { escrita.escrever(formato::PRIVADO, comentario: 'Quanto custa?') }
        .to raise_error(Crm::MetaAds::ComentariosIa::Classificador::Indisponivel)
    end
  end

  describe 'recuo para as frases fixas, nunca mudo' do
    def expect_frases_fixas(motivo, caixa = inbox)
      escrito = escrita(caixa).escrever(formato::PRIVADO, comentario: 'Quanto custa?')

      expect(escrito).to have_attributes(status: :frases_fixas, motivo: motivo)
      expect(escrita(caixa).textos('private', comentario: 'Quanto custa?')).to eq({})
      expect(Autonomia::Agents::Answerer).not_to have_received(:new)
      expect(Rails.logger).to have_received(:info).with("[comentarios_ia] frases fixas motivo=#{motivo} account=#{account.id} care=#{care.id}")
                                                  .at_least(:once)
    end

    it 'sem caixa' do
      com_chave!
      expect_frases_fixas('sem_caixa', nil)
    end

    it 'caixa de outra conta, mesmo com agente na porta dela' do
      com_chave!
      outra = create(:inbox)
      Autonomia::Agents::Agent.create!(account: outra.account, name: 'Porta', agent_type: 'custom', status: :active, enabled: true)
                              .then { |agent| na_porta(agent, outra) }

      expect_frases_fixas('outra_conta', outra)
    end

    it 'conta sem a chave dela' do
      na_porta(agente)
      expect_frases_fixas('sem_chave')
    end

    it 'caixa sem agente na porta' do
      com_chave!
      expect_frases_fixas('sem_porta')
    end

    it 'a Lia na porta: insurance_quote não fala em comentário público' do
      com_chave!
      na_porta(agente(agent_type: 'insurance_quote'))
      expect_frases_fixas('lia')
    end

    it 'agente da porta parado (pausado ou desligado)' do
      com_chave!
      na_porta(agente).update!(enabled: false)
      expect_frases_fixas('porta_parada')
    end

    it 'agente da porta interno (copiloto): não fala com cliente' do
      com_chave!
      agent = na_porta(agente)
      allow(agent).to receive(:atende_cliente?).and_return(false)
      allow(Autonomia::Agents::QuemResponde).to receive(:porta_da_caixa).and_return(instance_double(Autonomia::Agents::AgentInbox, agent: agent))
      expect_frases_fixas('porta_parada')
    end
  end
end
