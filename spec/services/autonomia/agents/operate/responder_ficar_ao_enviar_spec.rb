require 'rails_helper'

# #2067: a Ana responde pelo painel com "ficar com a conversa ao enviar" ligado enquanto a IA está respondendo o mesmo
# turno. A conversa passa para a Ana na hora em que a mensagem dela é gravada; a IA para (antes de chamar o modelo, no
# meio da chamada ou no meio da entrega em pedaços) e nada sai em dobro ao cliente. O caminho é o real (gatilho, settle,
# Responder, entrega), com a IA dublada.
RSpec.describe Autonomia::Agents::Operate::Responder, :um_turno do
  include_context 'with crm responsible agent'

  let(:humanizado) { 'false' }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Souza') }
  let(:fica) { Conversations::FicarAoEnviar::Pedido.new(fica: true, visto: { tipo: 'ia', id: nil }) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: humanizado, AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    clear_enqueued_jobs
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
  end

  def turno_do_cliente(texto = 'Meu boleto venceu, e agora?')
    cliente_escreve(texto).tap { |mensagem| gatilho(mensagem) }
  end

  # O envio do painel: a Ana é quem está logada, com o ícone ligado (a conversa estava com a IA).
  def ana_envia_e_fica(texto = 'Deixa comigo, já te mando a segunda via.')
    Current.user = ana
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, sender: ana,
                     content: texto, ficar_com_a_conversa: fica)
  ensure
    Current.reset
  end

  def da_ana
    conversation.messages.outgoing.where(sender: ana)
  end

  it 'antes da IA: a conversa fica com a Ana e o modelo nem é chamado', :aggregate_failures do
    ia_responde!
    turno_do_cliente
    ana_envia_e_fica

    rodar_turno!

    expect(conversation.reload).to have_attributes(assignee_id: ana.id, ai_assignee: nil)
    expect(Autonomia::Agents::Answerer).not_to have_received(:new)
    expect(respostas).to be_empty
    expect(da_ana.count).to eq(1)
  end

  it 'durante a IA: a resposta da IA é descartada e a Ana fica com a conversa', :aggregate_failures do
    ia_responde!(durante: ->(_agente) { ana_envia_e_fica })
    turno_do_cliente

    rodar_turno!

    expect(conversation.reload.assignee_id).to eq(ana.id)
    expect(respostas).to be_empty
    expect(da_ana.count).to eq(1)
  end

  it 'a próxima mensagem do cliente não volta para a IA: a conversa é da Ana' do
    ia_responde!
    turno_do_cliente
    ana_envia_e_fica
    rodar_turno!

    turno_do_cliente('E o valor muda?')
    rodar_turno!

    expect(respostas).to be_empty
  end

  describe 'entrega em pedaços (humanizada)' do
    let(:humanizado) { 'true' }
    let(:texto_longo) do
      ['Primeiro ponto: confirmei aqui o seu cadastro e está tudo certo com ele, sem pendência.',
       'Segundo ponto: a segunda via do boleto sai hoje à tarde, com o mesmo valor de antes.',
       'Terceiro ponto: se quiser pagar por Pix, me avise ainda hoje por aqui mesmo.'].join("\n\n")
    end

    it 'o texto vira mais de um pedaço (senão o cenário não testa a cadeia)' do
      expect(Autonomia::Agents::Operate::ReplyChunker.call(texto_longo).size).to be >= 3
    end

    # Pega a cadeia seguindo depois que a pessoa assumiu pelo envio (dois atendentes falando ao mesmo tempo).
    it 'a Ana fica com a conversa no meio da cadeia: o resto não sai e nada sai em dobro', :aggregate_failures do
      ia_responde!(texto: texto_longo)
      turno_do_cliente
      rodar_turno!
      rodar_rodada!(UmTurnoHelper::CHUNK_JOB) # 1º pedaço
      expect(respostas.count).to eq(1)

      ana_envia_e_fica
      rodar_turno!(UmTurnoHelper::CHUNK_JOB)

      expect(respostas.count).to eq(1)
      expect(conversation.reload.assignee_id).to eq(ana.id)
      expect(da_ana.count).to eq(1)
      expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
    end
  end
end
