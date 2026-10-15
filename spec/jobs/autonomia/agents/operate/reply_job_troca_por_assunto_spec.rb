require 'rails_helper'

# #1606, critério "d" do eval Clara → Lia → Clara: a troca de dono pelo assunto (o Sync do CRM, que troca só pelo
# PassarParaIa) durante o turno de UMA mensagem do cliente dá UMA resposta, do dono novo, com uma passagem e um evento.
# A IA é dublada (UmTurnoHelper); o Sync, o PassarParaIa, o registro de passagens e o reenfileiramento são os de verdade.
RSpec.describe Autonomia::Agents::Operate::ReplyJob, :um_turno do
  include_context 'with crm responsible agent'

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!(ordem: true)
    clear_enqueued_jobs
  end

  def sync!
    Crm::Ai::ResponsibleAgentSync.new(conversation: conversation.reload, motivo: Crm::Ai::ResponsibleAgentSync::FOCO).perform
  end

  def marco!(mensagem)
    allow(contrato).to receive(:decidido_ate).with(conversation.id).and_return(mensagem.id)
  end

  def passagens
    Crm::Passagem.where(conversation_id: conversation.id).order(:id)
  end

  def com_eventos(&)
    eventos = []
    ActiveSupport::Notifications.subscribed(->(*, payload) { eventos << payload }, Crm::Ai::ResponsibleAgentSync::EVENTO_TROCA, &)
    eventos
  end

  it 'ida: o assunto passa da porta para a área antes do marco = 1 resposta, da área' do
    ia_responde!
    mensagem = cliente_escreve('o sistema caiu')
    gatilho(mensagem)
    rodar_rodada! # o settle do debounce: sem marco, espera

    eventos = com_eventos do
      create_card(pipeline: suporte)
      sync!
      marco!(mensagem)
      rodar_turno!
    end

    expect(respostas.sole).to have_attributes(sender_id: espelho_area.id, content: 'Resposta de Área Suporte.')
    expect(eventos.size).to eq(1)
    expect(passagens.sole).to have_attributes(de_id: agente_da_porta.id, para_id: area.id, motivo: 'foco')
  end

  it 'troca no meio da resposta da porta: a resposta velha é descartada e sai 1 resposta, da área' do
    marco_da = nil
    trocou = false
    ia_responde!(durante: lambda do |agente|
      next if trocou || agente != agente_da_porta

      trocou = true
      create_card(pipeline: suporte)
      sync!
      marco!(marco_da)
    end)
    mensagem = cliente_escreve('o sistema caiu')
    marco_da = mensagem
    marco!(mensagem)
    gatilho(mensagem)

    eventos = com_eventos { rodar_turno! }

    expect(trocou).to be(true)
    expect(respostas.sole.sender_id).to eq(espelho_area.id)
    expect(eventos.size).to eq(1)
    expect(passagens.count).to eq(1)
  end

  it 'volta: o foco passa para um funil sem responsável = 1 resposta, da porta, com a devolução gravada' do
    ia_responde!
    create_card(pipeline: suporte)
    sync!
    expect(conversation.reload.ai_assignee).to eq(espelho_area)

    mensagem = cliente_escreve('qual o endereço da loja?')
    gatilho(mensagem)
    rodar_rodada!

    eventos = com_eventos do
      create_card(pipeline: comercial)
      sync!
      marco!(mensagem)
      rodar_turno!
    end

    expect(respostas.sole.sender_id).to eq(porta.id)
    expect(eventos.size).to eq(1)
    ida, volta = passagens.to_a
    expect(ida).to have_attributes(para_id: area.id, devolvida_em: be_present)
    expect(volta).to have_attributes(de_id: area.id, para_id: agente_da_porta.id, motivo: 'foco', devolvida_em: nil)
  end
end
