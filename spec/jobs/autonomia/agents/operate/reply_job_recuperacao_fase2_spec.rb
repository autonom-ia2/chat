require 'rails_helper'

# chat#1489 × "um turno, uma ordem" (#1606, Fase 2 LIGADA): a mensagem recuperada do celular acorda a IA pelo caminho
# real (RecoveryAiWake → gatilho → settle → posse do turno → Responder → entrega) e é respondida uma vez. Se o cliente
# escreve outra durante a chamada à IA, a resposta da recuperada fica velha (turno_superado) e só a mais nova responde.
RSpec.describe Autonomia::Agents::Operate::ReplyJob, :um_turno do
  include_context 'with crm responsible agent'

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: 'false', AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before { contrato! }

  # A bolha "não suportada" já recuperada: o texto veio do celular e a IA ainda não respondeu (o listener a ignorou).
  def recuperada(texto = 'Sua fatura de outubro está disponível.')
    cliente_escreve(texto).tap do |mensagem|
      mensagem.update!(content_attributes: { 'hybrid_recovery' => 'recovered', 'recovered_via' => 'web',
                                             'whatsapp_web_id' => '3EB0AAAA' })
    end
  end

  def posse_de(mensagem)
    Redis::Alfred.get(Autonomia::Agents::Operate::PosseDoTurno.chave(conversation.id, mensagem.id, vinculo_da_porta.id))
  end

  it 'Fase 2 ligada: a recuperada pega a posse do turno, responde uma vez e a posse fica (dedupe)' do
    ia_responde!
    mensagem = recuperada

    WhatsappHybrid::RecoveryAiWake.call(mensagem)
    rodar_turno!
    WhatsappHybrid::RecoveryAiWake.call(mensagem.reload) # nova tentativa não responde de novo

    rodar_turno!
    expect(respostas.count).to eq(1)
    expect(respostas.last.content_attributes['autonomia_reply_to_message_id']).to eq(mensagem.id)
    expect(posse_de(mensagem)).to be_present
  end

  it 'turno_superado: o cliente escreve durante a IA; a resposta da recuperada é descartada e só a mais nova responde' do
    mais_nova = nil
    ia_responde!(durante: lambda { |_agente|
      next if mais_nova

      mais_nova = cliente_escreve('oi? alguém aí?')
      gatilho(mais_nova)
    })
    mensagem = recuperada

    linhas = linhas_do_log do
      WhatsappHybrid::RecoveryAiWake.call(mensagem)
      rodar_turno!
    end

    expect(respostas.count).to eq(1)
    expect(respostas.last.content_attributes['autonomia_reply_to_message_id']).to eq(mais_nova.id)
    expect(linhas.join).to include('motivo=turno_superado')
  end
end
