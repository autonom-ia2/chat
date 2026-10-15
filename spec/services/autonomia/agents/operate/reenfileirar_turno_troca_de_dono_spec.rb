require 'rails_helper'

# "Um turno, uma ordem" (#1606), ponto 2, cenários 5 a 9 e 13 da bateria: o dono muda no meio do turno. O dono antigo
# cala com `dono_mudou` e o turno é refeito pelo dono novo, uma vez só (SET NX por destino), no caminho clássico e na
# entrega em pedaços. Pessoa que assume vence: silêncio `nao_elegivel`, sem refazer.
RSpec.describe Autonomia::Agents::Operate::ReenfileirarTurno, :um_turno do
  include_context 'with crm responsible agent'

  let(:humanizado) { 'false' }
  let(:vinculo_area) { Autonomia::Agents::Areas.vincular!(agent: area, inbox: inbox) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true', AI_HUMANIZE_DELIVERY: humanizado, AI_AGENT_MEDIA: 'false' do
      example.run
    end
  end

  before do
    contrato!
    clear_enqueued_jobs
  end

  def turno_do_cliente(texto = 'preciso de ajuda')
    cliente_escreve(texto).tap { |mensagem| gatilho(mensagem) }
  end

  # A troca sem o evento do CRM: a atribuição de robô pela tela (Conversations::AssignmentService).
  def atribuir_sem_evento!(robo)
    Conversations::AssignmentService.new(conversation: conversation.reload, assignee_id: robo.id, assignee_type: 'AgentBot').perform
  end

  def posse
    Autonomia::Agents::Operate::PosseDoTurno
  end

  def silencios(linhas, motivo)
    linhas.grep(/\[autonomia\]\[operate\] silencio .*motivo=#{motivo}\b/)
  end

  it 'cenário 5: troca de dono durante a IA (clássico): o antigo cala com dono_mudou e o novo responde uma vez' do
    ia_responde!(durante: ->(agente) { trocar_dono!(espelho_area) if agente == agente_da_porta })
    mensagem = turno_do_cliente

    linhas = linhas_do_log { rodar_turno! }

    expect(respostas.sole).to have_attributes(sender_id: espelho_area.id, content: 'Resposta de Área Suporte.')
    expect(silencios(linhas, 'dono_mudou').size).to eq(1)
    expect(linhas.grep(/turno_reenfileirado conv=#{conversation.id} msg=#{mensagem.id} origem=evento_troca/).size).to eq(1)
    # O Responder da porta também tentou refazer o turno, e o SET NX barrou.
    expect(linhas.grep(/reenfileiramento_barrado conv=#{conversation.id} msg=#{mensagem.id} origem=responder/).size).to eq(1)
  end

  describe 'entrega em pedaços (humanizada)' do
    let(:humanizado) { 'true' }
    let(:texto_longo) do
      ['Primeiro ponto do atendimento: confirmei aqui o seu cadastro e está tudo certo com ele.',
       'Segundo ponto: o pedido saiu ontem à tarde e chega em até dois dias úteis no seu endereço.',
       'Terceiro ponto: se quiser trocar o endereço de entrega, me avise ainda hoje por aqui mesmo.'].join("\n\n")
    end

    it 'o texto vira mais de um pedaço (senão os cenários não testam a cadeia)' do
      expect(Autonomia::Agents::Operate::ReplyChunker.call(texto_longo).size).to be >= 2
    end

    def cadeias
      respostas.pluck(:sender_id).uniq
    end

    it 'cenário 6a: troca durante a IA, antes do 1º pedaço: no máximo uma cadeia, a do dono novo' do
      ia_responde!(texto: texto_longo, durante: ->(agente) { trocar_dono!(espelho_area) if agente == agente_da_porta })
      turno_do_cliente

      rodar_turno!
      rodar_turno!(UmTurnoHelper::CHUNK_JOB)

      expect(cadeias).to eq([espelho_area.id])
      expect(respostas.count).to eq(Autonomia::Agents::Operate::ReplyChunker.call(texto_longo).size)
      expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
    end

    it 'troca sem evento (robô atribuído pela tela) depois da IA e antes do 1º pedaço: o dono novo refaz o turno' do
      ia_responde!(texto: texto_longo)
      turno_do_cliente
      rodar_turno! # a porta responde e enfileira a cadeia
      atribuir_sem_evento!(espelho_area)

      linhas = linhas_do_log do
        rodar_rodada!(UmTurnoHelper::CHUNK_JOB) # o 1º pedaço da porta vê o dono novo e não posta
        rodar_turno!
        rodar_turno!(UmTurnoHelper::CHUNK_JOB)
      end

      expect(cadeias).to eq([espelho_area.id])
      expect(respostas.count).to eq(Autonomia::Agents::Operate::ReplyChunker.call(texto_longo).size)
      expect(linhas.grep(/turno_reenfileirado conv=#{conversation.id} .*origem=responder/).size).to eq(1)
    end

    it 'retry do 1º pedaço já postado, com o dono trocado depois: não refaz o turno nem solta a posse' do
      ia_responde!(texto: texto_longo)
      mensagem = turno_do_cliente
      rodar_turno! # a porta responde e enfileira a cadeia
      primeiro = jobs_de(UmTurnoHelper::CHUNK_JOB).sole
      rodar_rodada!(UmTurnoHelper::CHUNK_JOB) # o 1º pedaço da porta entra
      expect(respostas.count).to eq(1)
      clear_enqueued_jobs
      atribuir_sem_evento!(espelho_area)

      linhas = linhas_do_log { primeiro[:job].perform_now(*ActiveJob::Arguments.deserialize(primeiro[:args])) }

      expect(linhas.grep(/turno_reenfileirado|reenfileiramento_barrado/)).to be_empty
      expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
      expect(respostas.pluck(:sender_id)).to eq([porta.id])
      expect(Redis::Alfred.exists?(posse.chave(conversation.id, mensagem.id, vinculo_da_porta.id))).to be(true)
    end

    it 'cenário 6b: troca no meio da cadeia: a cadeia para e o dono novo não começa outra (resposta parcial, aceita)' do
      ia_responde!(texto: texto_longo)
      turno_do_cliente
      rodar_turno! # a porta começa a cadeia
      rodar_rodada!(UmTurnoHelper::CHUNK_JOB) # 1º pedaço da porta
      expect(respostas.count).to eq(1)

      trocar_dono!(espelho_area)
      rodar_turno! # o turno refeito pela área: já há resposta a esta mensagem, então não começa outra cadeia
      rodar_turno!(UmTurnoHelper::CHUNK_JOB)

      expect(cadeias).to eq([porta.id])
      expect(respostas.count).to eq(1)
    end
  end

  it 'IA que passa da janela do debounce mais a folga: o dono antigo cala e o novo refaz o turno mesmo assim' do
    ia_responde!(durante: lambda do |agente|
      next unless agente == agente_da_porta

      travel 4.minutes
      atribuir_sem_evento!(espelho_area)
    end)
    turno_do_cliente

    linhas = linhas_do_log { rodar_turno! }

    expect(respostas.sole.sender_id).to eq(espelho_area.id)
    expect(silencios(linhas, 'dono_mudou').size).to eq(1)
  end

  it 'evento de troca muito depois do turno (fora da janela) não refaz turno velho' do
    ia_responde!
    mensagem = turno_do_cliente
    clear_enqueued_jobs
    travel 4.minutes
    conversation.update!(ai_assignee: espelho_area)

    expect(described_class.ao_trocar_dono(conversation: conversation)).to be(false)
    expect(described_class.call(conversation: conversation, message_id: mensagem.id, origem: :evento_troca)).to be(false)
    expect(settles_na_fila).to be_empty
  end

  describe 'a posse do turno (PosseDoTurno)' do
    let(:janela) { Autonomia::Agents::Config.debounce_seconds_for(agente_da_porta) + Autonomia::Agents::AgentInbox::FOLGA_DO_TURNO }

    it 'a posse repassada dura mais que a janela do debounce com a folga, e um pedaço 0 atrasado não a toma de novo' do
      mensagem = turno_do_cliente
      conversation.update!(ai_assignee: espelho_area)

      expect(described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder,
                                  quem_perdeu: vinculo_da_porta)).to be(true)
      expect(Redis::Alfred.ttl(posse.chave(conversation.id, mensagem.id, vinculo_area.id))).to be > janela.to_i

      travel janela + 1.minute # o pedaço 0 atrasado da porta, com a área já tendo respondido
      expect(described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder,
                                  quem_perdeu: vinculo_da_porta)).to be(false)
      expect(settles_na_fila.count { |job| ActiveJob::Arguments.deserialize(job[:args])[3].present? }).to eq(1)
    end

    it 'pelo Responder, turno mais velho que a vida da posse não é refeito' do
      mensagem = turno_do_cliente
      conversation.update!(ai_assignee: espelho_area)
      travel posse::TTL + 1.minute

      expect(described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder,
                                  quem_perdeu: vinculo_da_porta)).to be(false)
    end

    it 'solta a chave de quem perdeu só se ela ainda tiver o valor dele' do
      mensagem = turno_do_cliente
      chave = posse.chave(conversation.id, mensagem.id, vinculo_da_porta.id)
      Redis::Alfred.set(chave, 'job-novo')
      conversation.update!(ai_assignee: espelho_area)

      described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder,
                           quem_perdeu: vinculo_da_porta, posse_de_quem_perdeu: 'job-velho')
      expect(Redis::Alfred.get(chave)).to eq('job-novo')

      described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder,
                           quem_perdeu: vinculo_da_porta)
      expect(Redis::Alfred.get(chave)).to eq('job-novo')

      described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder,
                           quem_perdeu: vinculo_da_porta, posse_de_quem_perdeu: 'job-novo')
      expect(Redis::Alfred.exists?(chave)).to be(false)
    end
  end

  describe 'turno que falhou pode ser retomado' do
    # Porta: a 1ª chamada levanta (falha_no_turno), a 2ª responde. Área: a IA não devolve resultado (silêncio ia_falhou).
    def ia_falha_primeiro!
      chamadas = Hash.new(0)
      allow(Autonomia::Agents::Answerer).to receive(:new) do |agent:, **|
        resposta = double('Answerer') # rubocop:disable RSpec/VerifiedDoubles
        allow(resposta).to receive(:answer) do
          chamadas[agent.id] += 1
          raise 'a IA caiu' if agent == agente_da_porta && chamadas[agent.id] == 1
          next nil if agent == area

          Autonomia::Agents::AnswerResult.new(reply: "Resposta de #{agent.name}.", confidence: 0.9,
                                              handoff: { should: false, reason: nil }, used_knowledge: [],
                                              answered_from_knowledge: false)
        end
        resposta
      end
      chamadas
    end

    it 'falha da IA na porta, falha na área, volta à porta: a porta retoma a mesma mensagem e responde' do
      chamadas = ia_falha_primeiro!
      mensagem = turno_do_cliente
      rodar_turno! # a porta falha
      expect(respostas).to be_empty
      expect(Redis::Alfred.exists?(posse.chave(conversation.id, mensagem.id, vinculo_da_porta.id))).to be(false)

      trocar_dono!(espelho_area)
      rodar_turno! # a área não devolve resultado
      expect(respostas).to be_empty
      expect(Redis::Alfred.exists?(posse.chave(conversation.id, mensagem.id, vinculo_area.id))).to be(false)

      trocar_dono!(porta)
      rodar_turno!

      expect(respostas.sole).to have_attributes(sender_id: porta.id, content: 'Resposta de Porta.')
      expect(chamadas[agente_da_porta.id]).to eq(2)
    end

    it 'o turno respondido segue com a chave: a volta ao mesmo dono não responde de novo' do
      ia_responde!
      mensagem = turno_do_cliente
      rodar_turno!
      expect(respostas.count).to eq(1)

      trocar_dono!(porta)
      rodar_turno!

      expect(respostas.count).to eq(1)
      expect(Redis::Alfred.exists?(posse.chave(conversation.id, mensagem.id, vinculo_da_porta.id))).to be(true)
    end
  end

  it 'cenário 7: Responder e assinante disparando juntos enfileiram um ReplyJob só' do
    ia_responde!
    mensagem = turno_do_cliente
    conversation.update!(ai_assignee: espelho_area)

    pelo_responder = described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder,
                                          quem_perdeu: vinculo_da_porta)
    pelo_evento = described_class.ao_trocar_dono(conversation: conversation)

    expect([pelo_responder, pelo_evento]).to contain_exactly(true, false)
    retomadas = settles_na_fila.map { |job| ActiveJob::Arguments.deserialize(job[:args]) }
                               .select { |args| args[3].present? }
    expect(retomadas).to eq([[conversation.id, mensagem.id, 'settle', vinculo_area.id]])
  end

  describe 'cenário 8: A→B→A no mesmo turno' do
    it 'volta antes de A terminar: uma resposta, de A, e a fila esvazia' do
      ia_responde!(durante: lambda do |agente|
        next unless agente == agente_da_porta

        trocar_dono!(espelho_area)
        trocar_dono!(porta)
      end)
      turno_do_cliente

      rodar_turno!

      expect(respostas.sole.sender_id).to eq(porta.id)
      expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
    end

    it 'volta depois de A calar: B perde no meio e A responde, uma vez, sem laço' do
      # Cada troca acontece uma vez: a porta perde para a área na 1ª chamada, a área devolve na dela.
      chamadas = Hash.new(0)
      ia_responde!(durante: lambda do |agente|
        chamadas[agente.id] += 1
        trocar_dono!(espelho_area) if agente == agente_da_porta && chamadas[agente.id] == 1
        trocar_dono!(porta) if agente == area && chamadas[agente.id] == 1
      end)
      turno_do_cliente

      expect(rodar_turno!).to be <= 4

      expect(respostas.count).to eq(1)
      expect(respostas.first.sender_id).to eq(porta.id)
      expect(chamadas.values).to eq([2, 1]) # porta, área, porta de novo
    end
  end

  it 'cenário 9: pessoa assume durante a IA: silêncio nao_elegivel, sem refazer o turno' do
    pessoa = create(:user, account: account, role: :agent)
    ia_responde!(durante: ->(_agente) { conversation.update!(assignee: pessoa) })
    turno_do_cliente

    linhas = linhas_do_log { rodar_turno! }

    expect(respostas).to be_empty
    expect(silencios(linhas, 'nao_elegivel').size).to eq(1)
    expect(linhas.grep(/turno_reenfileirado/)).to be_empty
    expect(jobs_de(UmTurnoHelper::REPLY_JOB)).to be_empty
  end

  # A Lia com cotação assíncrona aceita no turno e a troca de dono: o despacho segue como hoje (`replied: false`, o
  # próprio job avisa o cliente e escala) e o turno tem uma resposta só, do dono novo.
  it 'cenário 13: cotação assíncrona aceita e troca de dono: despacho como hoje, sem duas respostas' do
    despachante = instance_double(Autonomia::Agents::Tools::AsyncDispatcher, dispatch!: true)
    allow(Autonomia::Agents::Tools::AsyncDispatcher).to receive(:new).and_return(despachante)
    allow_any_instance_of(Autonomia::Agents::Tools::Delivery).to receive(:any_runs?) do |entrega| # rubocop:disable RSpec/AnyInstance
      entrega.instance_variable_get(:@agent_inbox) == vinculo_da_porta
    end
    ia_responde!(durante: ->(agente) { trocar_dono!(espelho_area) if agente == agente_da_porta })
    turno_do_cliente

    rodar_turno!

    expect(despachante).to have_received(:dispatch!).with(replied: false, expected_chunks: 0).once
    expect(respostas.sole.sender_id).to eq(espelho_area.id)
  end

  describe 'conta fora da Fase 2' do
    before { Autonomia::Agents::Fase2.desligar!(account) }

    it 'não refaz turno, nem pelo Responder nem pelo evento' do
      ia_responde!
      mensagem = turno_do_cliente

      expect(described_class.call(conversation: conversation, message_id: mensagem.id, origem: :responder)).to be(false)
      expect(described_class.ao_trocar_dono(conversation: conversation)).to be(false)
      expect(settles_na_fila.size).to eq(1) # só o do debounce
    end

    it 'o assinante nem lê a última mensagem' do
      allow(described_class).to receive(:ultima_mensagem_publica).and_call_original

      expect(described_class.ao_trocar_dono(conversation: conversation.reload)).to be(false)
      expect(described_class).not_to have_received(:ultima_mensagem_publica)
    end
  end

  it 'recusa origem fora da lista' do
    expect { described_class.call(conversation: conversation, message_id: 1, origem: :outra) }.to raise_error(ArgumentError)
  end

  it 'o assinante escuta o mesmo evento que o Sync publica' do
    turno_do_cliente
    allow(described_class).to receive(:ao_trocar_dono).and_call_original

    trocar_dono!(espelho_area)

    expect(described_class).to have_received(:ao_trocar_dono).once
  end
end
