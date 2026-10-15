require 'rails_helper'

# "Um turno, uma ordem" (#1606), ponto 1, cenários 1 a 4 e 14 da bateria: o settle espera o assunto ser decidido (o
# marco) antes de responder, com teto de 20 s, e lê quem responde na hora. Os leitores do Multifunnel são dublados pelo
# adaptador; o Sync que troca o dono é o de verdade (Crm::Ai::ResponsibleAgentSync).
RSpec.describe Autonomia::Agents::Operate::ReplyJob, :um_turno do
  include_context 'with crm responsible agent'

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    ia_responde!
    clear_enqueued_jobs
  end

  def sync!
    Crm::Ai::ResponsibleAgentSync.new(conversation: conversation.reload, motivo: Crm::Ai::ResponsibleAgentSync::FOCO).perform
  end

  def marco!(mensagem)
    allow(contrato).to receive(:decidido_ate).with(conversation.id).and_return(mensagem.id)
  end

  def eventos_de_atraso
    Autonomia::Agents::AgentEvent.skipped_assunto_atrasou.where(conversation_id: conversation.id)
  end

  it 'cenário 1: rajada de 3 mensagens com o assunto mudando na 2ª gera uma resposta só, do dono novo' do
    contrato!(ordem: true)
    m1 = cliente_escreve('oi')
    gatilho(m1)
    m2 = cliente_escreve('preciso de suporte')
    gatilho(m2)
    create_card(pipeline: suporte)
    sync! # o assunto da 2ª decide: a área vira dona, e o evento tenta refazer o turno da 2ª
    m3 = cliente_escreve('o sistema caiu')
    gatilho(m3)
    marco!(m3)

    rodar_turno!

    expect(respostas.count).to eq(1)
    expect(respostas.first).to have_attributes(sender_id: espelho_area.id, content: 'Resposta de Área Suporte.')
  end

  it 'cenário 2: marco que chega a T+8 s faz responder depois dele, sem assunto_atrasou' do
    contrato!(ordem: true)
    mensagem = cliente_escreve('quero o boleto')
    gatilho(mensagem)

    rodar_rodada! # o settle do debounce (T+6 s): sem marco, reagenda
    expect(respostas).to be_empty
    espera = settles_na_fila.sole
    expect(Time.zone.at(espera[:at])).to be_within(0.5.seconds).of(3.seconds.from_now)

    travel 2.seconds
    marco!(mensagem)
    rodar_turno!

    expect(respostas.count).to eq(1)
    expect(respostas.first.created_at - mensagem.created_at).to be < 12.seconds
    expect(eventos_de_atraso).to be_empty
  end

  it 'cenário 3: marco que nunca chega responde perto de 20 s, com o dono de agora, e grava assunto_atrasou uma vez' do
    contrato!(ordem: true)
    mensagem = cliente_escreve('alô?')
    gatilho(mensagem)

    linhas = linhas_do_log { rodar_turno! }

    resposta = respostas.sole
    expect(resposta.sender_id).to eq(porta.id)
    expect(resposta.created_at - mensagem.created_at).to be_between(20.seconds, 24.seconds)
    expect(linhas.grep(/\[autonomia\]\[turno\] assunto_atrasou conv=#{conversation.id} msg=#{mensagem.id} ms=\d+/).size).to eq(1)
    expect(eventos_de_atraso.count).to eq(1)

    # O segundo turno atrasado da mesma conversa não repete o evento no painel.
    outra = cliente_escreve('e agora?')
    gatilho(outra)
    rodar_turno!
    expect(eventos_de_atraso.count).to eq(1)
    expect(respostas.count).to eq(2)
  end

  it 'cenário 4: sem marco (Sync ainda na fila) não responde com o dono antigo; com o marco, responde o dono novo' do
    contrato!(ordem: true)
    create_card(pipeline: suporte)
    mensagem = cliente_escreve('o sistema caiu')
    gatilho(mensagem)

    3.times { rodar_rodada! } # T+6, T+9, T+12: sem marco, nada sai
    expect(respostas).to be_empty

    sync!
    marco!(mensagem)
    rodar_turno!

    expect(respostas.sole.sender_id).to eq(espelho_area.id)
    expect(respostas.where(sender_id: porta.id)).to be_empty
  end

  describe 'cenário 14: sem a ordem do turno, nenhuma espera e nenhuma leitura do marco' do
    it 'caixa sem CRM ou sem a IA de assunto (a regra do CRM diz não): responde no settle do debounce' do
      contrato!(ordem: false)
      mensagem = cliente_escreve('oi')
      gatilho(mensagem)

      expect(rodar_turno!).to eq(1)

      expect(respostas.count).to eq(1)
      expect(contrato).not_to have_received(:decidido_ate)
    end

    it 'conta fora da Fase 2: nem pergunta ao CRM' do
      Autonomia::Agents::Fase2.desligar!(account)
      contrato!(ordem: true)
      mensagem = cliente_escreve('oi')
      gatilho(mensagem)

      expect(rodar_turno!).to eq(1)

      expect(respostas.sole.sender_id).to eq(porta.id)
      expect(contrato).not_to have_received(:ordem_do_turno?)
      expect(contrato).not_to have_received(:decidido_ate)
    end
  end
end
