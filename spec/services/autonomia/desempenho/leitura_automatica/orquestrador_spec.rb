require 'rails_helper'

# Leitura automática do painel de desempenho (#2301), com a loja inventada de AutonomiaDesempenhoHelpers e a OpenAI
# simulada (stub_request). Nenhum dado de cliente.
RSpec.describe Autonomia::Desempenho::LeituraAutomatica::Orquestrador do
  let(:account) { create(:account) }
  let(:robo) { create(:agent_bot, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:equipe) { create(:user, account: account) }
  let(:ficha) do
    ficha_da_loja!(account, sujeito_id: robo.id).tap do |f|
      f.update!(chave_de_leitura: 'Leia a conversa da loja.', configuracao: f.configuracao.merge('leitura' => { 'com_teste' => true }))
    end
  end
  let(:corpos) { [] }
  let(:agora) { Time.utc(2026, 10, 22, 10, 0) }

  def conversa
    create(:conversation, account: account, inbox: inbox)
  end

  def mensagem(conversa, tipo, quando, remetente: nil, texto: 'oi')
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: tipo, sender: remetente,
                     content: texto, created_at: quando)
  end

  # Uma conversa do cliente com resposta do agente às `hora` horas UTC do dia 21/10.
  def conversa_com_agente(hora)
    conversa.tap do |c|
      mensagem(c, :incoming, Time.utc(2026, 10, 21, hora, 0))
      mensagem(c, :outgoing, Time.utc(2026, 10, 21, hora, 1), remetente: robo, texto: 'Olá!')
    end
  end

  # Todo acesso ao Redis neste arquivo roda no relógio da rodada. O MockRedis do teste vence a chave pelo `Time.now` e,
  # a cada comando, apaga o que já venceu: no relógio real, além de `agora` + a validade da chave (7 dias nos contadores,
  # 6 horas na trava), a chave da rodada já teria sumido, e o `be_nil` passaria sem conferir nada. Pelo mesmo motivo,
  # leia no instante da última rodada do exemplo, nunca antes de uma leitura mais tardia.
  def redis_get(chave, quando: agora)
    travel_to(quando) { Redis::Alfred.get(chave) }
  end

  def leitura!(conversa, ate)
    Autonomia::Desempenho::Leitura.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, conversation: conversa,
                                           lida_ate_em: ate, versao_ficha: 1, status: 'lida', lote: 'carga')
  end

  def procura_da_carga!(conversa, ate)
    Autonomia::Desempenho::Procura.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, conversation: conversa, ordem: 1,
                                           inicio_em: ate - 1.minute, fim_em: ate, versao_ficha: 1, lote: 'carga', tema_id: 'troca')
  end

  def procura(campos = {})
    { 'conversa' => 1, 'procura' => 1, 'inicio' => '10-21 13:00', 'fim' => '10-21 13:01', 'teste' => false, 'quem' => 'cliente',
      'pedido' => 'comprar', 'tema' => 'entrega', 'marcos' => ['pagou'], 'resultado' => 'comprou', 'motivos' => [],
      'perda_evitavel' => false, 'por_que' => '', 'qualidade' => 'acertou', 'regras' => [], 'teve_pessoa' => false,
      'precisava_pessoa' => false, 'origem' => 'desconhecida', 'resumo' => 'Quis saber o prazo.' }.merge(campos)
  end

  # A OpenAI devolve, em ordem, cada item de `respostas` (o último se repete): um Hash de procuras, um texto cru (200) ou
  # um número (o status do erro).
  def openai_devolve(*respostas)
    fila = respostas.dup
    stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
      corpos << JSON.parse(request.body)
      atual = fila.size > 1 ? fila.shift : fila.first
      if atual.is_a?(Integer)
        next { status: atual, body: { error: { message: 'falhou' } }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      texto = atual.is_a?(String) ? atual : atual.to_json
      payload = { id: "resp_#{corpos.size}", output_text: texto, usage: { input_tokens: 1000, output_tokens: 200 } }
      { status: 200, body: payload.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def chave_do_cliente!
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: { 'api_key' => 'chave-de-teste' })
  end

  def rodar
    travel_to(agora) { described_class.new(ficha).call }
  end

  def procuras_de(conversa)
    Autonomia::Desempenho::Procura.where(conversation_id: conversa.id)
  end

  before { chave_do_cliente! }

  describe 'quais conversas lê' do
    let!(:cresceu) { conversa_com_agente(14) }
    let!(:parada) { conversa_com_agente(15) }
    let!(:nova) { conversa_com_agente(16) }

    before do
      # A carga leu `cresceu` até antes da resposta do agente e `parada` inteira. O piso da primeira rodada é a última
      # mensagem que a carga leu (15:01); `nova` começou depois da carga.
      leitura!(cresceu, Time.utc(2026, 10, 21, 14, 0)).tap { procura_da_carga!(cresceu, Time.utc(2026, 10, 21, 14, 0)) }
      leitura!(parada, Time.utc(2026, 10, 21, 15, 1)).tap { procura_da_carga!(parada, Time.utc(2026, 10, 21, 15, 1)) }
    end

    it 'lê a conversa nova e a que ganhou mensagem, e não chama o modelo para a que não mudou' do
      openai_devolve({ 'procuras' => [procura('inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] },
                     { 'procuras' => [procura('inicio' => '10-21 16:00', 'fim' => '10-21 16:01')] })

      rodada = rodar

      expect(corpos.size).to eq(2)
      expect(rodada).to have_attributes(status: 'ok', conversas_lidas: 2, conversas_pendentes: 0, corte_em: agora)
      expect(rodada.piso_em).to eq(Time.utc(2026, 10, 21, 15, 1))
      expect(procuras_de(nova).pluck(:lote, :tema_id, :inicio_em)).to eq([['leitura_automatica', 'entrega', Time.utc(2026, 10, 21, 16, 0)]])
      # A procura da carga some: a conversa inteira foi relida.
      expect(procuras_de(cresceu).pluck(:lote, :tema_id)).to eq([%w[leitura_automatica entrega]])
      expect(procuras_de(parada).pluck(:lote)).to eq(['carga'])
      leitura = Autonomia::Desempenho::Leitura.find_by(conversation_id: cresceu.id)
      expect(leitura).to have_attributes(status: 'lida', lote: 'leitura_automatica', lida_ate_em: Time.utc(2026, 10, 21, 14, 1))
    end

    it 'lê a conversa nunca lida com mensagens só antes do piso, nos últimos 30 dias; a mais velha fica de fora' do
      antiga = conversa_com_agente(9)
      velha = conversa.tap do |c|
        mensagem(c, :incoming, agora - 40.days)
        mensagem(c, :outgoing, agora - 40.days + 1.minute, remetente: robo, texto: 'Olá!')
      end
      openai_devolve({ 'procuras' => [procura('inicio' => '10-21 09:00', 'fim' => '10-21 09:01')] },
                     { 'procuras' => [procura('inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] },
                     { 'procuras' => [procura('inicio' => '10-21 16:00', 'fim' => '10-21 16:01')] })

      expect(rodar).to have_attributes(status: 'ok', conversas_lidas: 3, conversas_pendentes: 0)
      expect(procuras_de(antiga).pluck(:lote)).to eq(['leitura_automatica'])
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: velha.id)).to be_nil
    end

    it 'a conversa nunca lida antes do piso que fica pendente não recua o pendente_desde para antes do piso' do
      conversa_com_agente(9)
      openai_devolve(503, { 'procuras' => [procura('inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] }, 503)

      rodada = rodar

      expect(rodada).to have_attributes(status: 'ok', conversas_lidas: 1, conversas_pendentes: 2)
      expect(rodada.pendente_desde).to eq(Time.utc(2026, 10, 21, 16, 0))
    end

    it 'grava os campos no formato do painel, com cortes, resumo e porquê em dados' do
      Autonomia::Desempenho::Leitura.find_by(conversation_id: cresceu.id).update!(lida_ate_em: Time.utc(2026, 10, 21, 14, 1))
      campos = { 'inicio' => '10-21 16:00', 'fim' => '10-21 16:01', 'teste' => true, 'motivos' => ['sem_estoque'], 'regras' => ['R-PRAZO'],
                 'perda_evitavel' => true, 'por_que' => 'Faltou estoque.', 'qualidade' => 'erro_leve', 'teve_pessoa' => true }
      openai_devolve({ 'procuras' => [procura(campos)] })

      rodar

      expect(procuras_de(nova).first).to have_attributes(
        ordem: 1, versao_ficha: 1, teste: true, quem_id: 'cliente', origem_id: 'desconhecida', pedido_id: 'comprar', resultado_id: 'comprou',
        qualidade_id: 'erro_leve', marcos: ['pagou'], motivo_ids: ['sem_estoque'], regra_ids: ['R-PRAZO'], perda_evitavel: true,
        teve_pessoa: true, precisava_pessoa: false, anuncio_id: nil, fim_em: Time.utc(2026, 10, 21, 16, 1),
        dados: { 'cortes' => { 'pedido' => 'comprar' }, 'resumo' => 'Quis saber o prazo.', 'por_que' => 'Faltou estoque.' }
      )
    end
  end

  describe 'a chamada' do
    let!(:nova) { conversa_com_agente(13) }

    before { leitura!(conversa_com_agente(10), Time.utc(2026, 10, 21, 12, 0)) }

    it 'usa a chave de leitura, o cache por ficha, store false e grava o consumo com a feature da leitura' do
      openai_devolve({ 'procuras' => [procura] })

      rodada = rodar

      corpo = corpos.first
      expect(corpo['instructions']).to eq("#{ficha.chave_de_leitura}#{Autonomia::Desempenho::LeituraAutomatica::Leitor::CONVERSA_E_DADO}")
      expect(corpo).to include('model' => 'gpt-6.1-sol', 'store' => false, 'prompt_cache_key' => "painel_leitura:#{account.id}:#{ficha.id}",
                               'reasoning' => { 'effort' => 'high' })
      expect(corpo.dig('input', 0, 'content', 0, 'text')).to start_with("=== CONVERSA #{nova.display_id} |")
      expect(corpo.dig('text', 'format')).to include('type' => 'json_schema', 'strict' => true, 'name' => 'procuras')
      expect(Crm::AiUsageEvent.where(account_id: account.id).pluck(:feature)).to eq(['painel_leitura'])
      expect(rodada.custo_usd).to eq(Crm::AiUsageEvent.where(account_id: account.id).sum(:cost_estimate))
      expect(Crm::Reports::AiUsage.resource_for_feature('painel_leitura')).to eq('Painel de desempenho')
    end

    it 'sem a chave do cliente não chama o modelo e fecha a rodada como sem_ia' do
      Integrations::Hook.where(account_id: account.id).destroy_all
      openai_devolve({ 'procuras' => [procura] })

      rodada = rodar

      expect(corpos).to be_empty
      expect(rodada).to have_attributes(status: 'sem_ia', conversas_lidas: 0, conversas_pendentes: 1)
    end

    it 'com a chave da instalação (quem pagaria é a plataforma) também fica sem_ia' do
      Integrations::Hook.where(account_id: account.id).destroy_all
      InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').first_or_create!(value: 'chave-da-instalacao')
      openai_devolve({ 'procuras' => [procura] })

      expect(rodar.status).to eq('sem_ia')
      expect(corpos).to be_empty
    end

    it 'passou do teto diário: para como teto, sem chamada, e a conversa fica pendente' do
      Crm::AiUsageEvent.create!(account: account, feature: 'painel_leitura', model: 'gpt-6.1-sol', cost_estimate: 1.2, created_at: agora - 1.hour)
      openai_devolve({ 'procuras' => [procura] })

      rodada = rodar

      expect(corpos).to be_empty
      expect(rodada).to have_attributes(status: 'teto', conversas_lidas: 0, conversas_pendentes: 1)
    end

    it 'o teto é o menor entre as fichas da conta: uma ficha com teto alto não libera gasto para a outra' do
      Crm::AiUsageEvent.create!(account: account, feature: 'painel_leitura', model: 'gpt-6.1-sol', cost_estimate: 1.2, created_at: agora - 1.hour)
      ficha.update!(configuracao: ficha.configuracao.merge('leitura' => { 'teto_diario_usd' => 5 }))
      outro = create(:agent_bot, account: account)
      ficha_da_loja!(account, sujeito_id: outro.id).update!(chave_de_leitura: 'Leia.')
      openai_devolve({ 'procuras' => [procura] })

      expect(rodar.status).to eq('teto')
      expect(corpos).to be_empty
    end

    it 'o teto da ficha troca o padrão' do
      Crm::AiUsageEvent.create!(account: account, feature: 'painel_leitura', model: 'gpt-6.1-sol', cost_estimate: 1.2, created_at: agora - 1.hour)
      ficha.update!(configuracao: ficha.configuracao.merge('leitura' => { 'teto_diario_usd' => 5 }))
      openai_devolve({ 'procuras' => [procura] })

      expect(rodar.status).to eq('ok')
      expect(corpos.size).to eq(1)
    end

    it 'conversa grande demais fica não lida, sem chamar o modelo' do
      ficha.update!(configuracao: ficha.configuracao.merge('leitura' => { 'max_caracteres' => 50 }))
      openai_devolve({ 'procuras' => [procura] })

      expect(rodar).to have_attributes(status: 'ok', conversas_lidas: 1)
      expect(corpos).to be_empty
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: nova.id))
        .to have_attributes(status: 'nao_lida', lida_ate_em: Time.utc(2026, 10, 21, 13, 1))
    end

    it 'não roda com outra rodada da mesma conta em andamento: levanta ContaOcupada sem abrir rodada' do
      travel_to(agora) { Redis::Alfred.set("autonomia:desempenho:leitura:#{account.id}:trava", 'outra', ex: 60) }

      expect { rodar }.to raise_error(described_class::ContaOcupada)
      expect(Autonomia::Desempenho::Rodada.count).to eq(0)
    ensure
      travel_to(agora) { Redis::Alfred.delete("autonomia:desempenho:leitura:#{account.id}:trava") }
    end

    it 'duas fichas da mesma conta: a segunda espera a primeira terminar (o teto é da conta) e roda depois' do
      account.enable_features!('agentes_painel_desempenho')
      allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
      outro = create(:agent_bot, account: account)
      configuracao_b = ficha.configuracao.merge('remetentes_do_agente' => [['AgentBot', outro.id]])
      ficha_b = ficha_da_loja!(account, sujeito_id: outro.id).tap { |f| f.update!(chave_de_leitura: 'Leia.', configuracao: configuracao_b) }
      conversa.tap do |c|
        mensagem(c, :incoming, Time.utc(2026, 10, 21, 13, 0))
        mensagem(c, :outgoing, Time.utc(2026, 10, 21, 13, 1), remetente: outro, texto: 'Olá!')
      end
      job = Autonomia::Desempenho::LeituraDaFichaJob
      durante_a = nil
      stub_request(:post, 'https://api.openai.com/v1/responses').to_return do |request|
        corpos << JSON.parse(request.body)
        # Enquanto a rodada da ficha A lê, o job da ficha B chega e encontra a conta ocupada.
        durante_a ||= Autonomia::Desempenho::Rodada.where(sujeito_id: outro.id).count.tap { job.perform_now(account.id, ficha_b.id) }
        { status: 200, body: { id: 'r', output_text: { 'procuras' => [procura] }.to_json, usage: { input_tokens: 1, output_tokens: 1 } }.to_json,
          headers: { 'Content-Type' => 'application/json' } }
      end

      with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true') do
        travel_to(agora) { job.perform_now(account.id, ficha.id) }
        expect(Autonomia::Desempenho::Rodada.where(sujeito_id: outro.id).count).to eq(0)
        expect(job).to have_been_enqueued.with(account.id, ficha_b.id)

        travel_to(agora + 10.minutes) { perform_enqueued_jobs(only: job) }
      end

      expect(durante_a).to eq(0)
      expect(Autonomia::Desempenho::Rodada.where(sujeito_id: [robo.id, outro.id]).order(:id).pluck(:sujeito_id, :status))
        .to eq([[robo.id, 'ok'], [outro.id, 'ok']])
    end
  end

  describe 'falha' do
    let!(:cresceu) { conversa_com_agente(14) }

    before do
      leitura!(conversa_com_agente(10), Time.utc(2026, 10, 21, 12, 0))
      leitura!(cresceu, Time.utc(2026, 10, 21, 14, 0))
      procura_da_carga!(cresceu, Time.utc(2026, 10, 21, 14, 0))
    end

    it 'erro passageiro (500) deixa a conversa pendente nas duas rodadas, sem contar falha nem virar não lida' do
      openai_devolve(500)

      primeira = rodar
      expect(primeira).to have_attributes(status: 'ok', conversas_lidas: 0, conversas_pendentes: 1)
      expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])

      segunda = travel_to(agora + 1.day) { described_class.new(ficha).call }
      expect(segunda).to have_attributes(status: 'ok', conversas_lidas: 0, conversas_pendentes: 1)
      expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: cresceu.id).status).to eq('lida')
      expect(redis_get("autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:falhas:#{cresceu.id}", quando: agora + 1.day)).to be_nil
    end

    it 'a OpenAI fora do ar (503) por dias seguidos nunca tira a conversa da fila: só o tempo esgotado conta contra ela' do
      openai_devolve(503)

      4.times do |dia|
        expect(travel_to(agora + dia.days) { described_class.new(ficha).call }).to have_attributes(status: 'ok', conversas_pendentes: 1)
      end
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: cresceu.id).status).to eq('lida')
      expect(redis_get("autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:passageiras:#{cresceu.id}", quando: agora + 3.days))
        .to be_nil
    end

    it 'três tempos esgotados seguidos numa rodada fecham a rodada sem contar o terceiro contra a conversa' do
      outras = [conversa_com_agente(15), conversa_com_agente(16)]
      stub_request(:post, 'https://api.openai.com/v1/responses').to_raise(Net::ReadTimeout)

      expect(rodar).to have_attributes(status: 'erro')
      chave = "autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:passageiras:"
      expect([cresceu, *outras].map { |c| redis_get("#{chave}#{c.id}") }).to eq(['1', '1', nil])
    end

    it 'resposta recusada mantém as procuras antigas; na segunda vez seguida, a conversa fica não lida e sai da fila' do
      openai_devolve({ 'procuras' => [procura('tema' => 'inventado', 'inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] })

      expect(rodar).to have_attributes(status: 'ok', conversas_lidas: 0, conversas_pendentes: 1)
      expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])

      segunda = travel_to(agora + 1.day) { described_class.new(ficha).call }
      expect(segunda).to have_attributes(status: 'ok', conversas_lidas: 1, conversas_pendentes: 0)
      expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: cresceu.id))
        .to have_attributes(status: 'nao_lida', lida_ate_em: Time.utc(2026, 10, 21, 14, 1))

      chamadas = corpos.size
      travel_to(agora + 2.days) { described_class.new(ficha).call }
      expect(corpos.size).to eq(chamadas)
    end

    it 'recusa id fora do catálogo, JSON quebrado e horário que não é de mensagem, sem tocar nas procuras antigas' do
      [{ 'procuras' => [procura('tema' => 'inventado', 'inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] },
       { 'procuras' => [procura('inicio' => '10-21 09:00', 'fim' => '10-21 14:01')] },
       { 'procuras' => [procura('inicio' => '10-21 14:01', 'fim' => '10-21 14:00')] },
       { 'procuras' => [] }, '{"procuras": ['].each do |resposta|
        travel_to(agora) { Redis::Alfred.delete("autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:falhas:#{cresceu.id}") }
        openai_devolve(resposta)

        expect(rodar).to have_attributes(conversas_lidas: 0, conversas_pendentes: 1)
        expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])
      end
    end
  end

  describe 'erro da chamada e da conversa' do
    let!(:primeira) { conversa_com_agente(14) }
    let!(:segunda) { conversa_com_agente(15) }

    before { leitura!(conversa_com_agente(10), Time.utc(2026, 10, 21, 12, 0)) }

    def falhas_de(conversa, quando: agora)
      redis_get("autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:falhas:#{conversa.id}", quando: quando)
    end

    it 'chave recusada (401 e 403) fecha a rodada como chave_recusada na hora, sem contar falha da conversa' do
      [401, 403].each_with_index do |status, dia|
        corpos.clear
        openai_devolve(status)

        rodada = travel_to(agora + dia.days) { described_class.new(ficha).call }

        expect(corpos.size).to eq(1)
        expect(rodada).to have_attributes(status: 'chave_recusada', conversas_lidas: 0, conversas_pendentes: 2)
        expect([falhas_de(primeira, quando: agora + dia.days), falhas_de(segunda, quando: agora + dia.days)]).to eq([nil, nil])
      end
    end

    it 'outro erro permanente (404) fecha como erro na hora' do
      openai_devolve(404)

      expect(rodar).to have_attributes(status: 'erro', conversas_pendentes: 2)
      expect(corpos.size).to eq(1)
    end

    it 'três falhas passageiras seguidas fecham a rodada como erro' do
      terceira = conversa_com_agente(16)
      conversa_com_agente(17)
      openai_devolve(503)

      rodada = rodar

      expect(corpos.size).to eq(3)
      expect(rodada).to have_attributes(status: 'erro', conversas_lidas: 0, conversas_pendentes: 4)
      # A pendente mais antiga: a mensagem do cliente de `primeira`, 14:00.
      expect(rodada.pendente_desde).to eq(Time.utc(2026, 10, 21, 14, 0))
      # Erro passageiro não é culpa da conversa: nenhuma conta falha.
      expect([falhas_de(primeira), falhas_de(segunda), falhas_de(terceira)]).to eq([nil, nil, nil])
    end

    it 'bug do sistema na gravação fecha a rodada como erro no terceiro seguido, sem contar falha das conversas' do
      4.times { |i| conversa_com_agente(16 + i) }
      openai_devolve({ 'procuras' => [procura] })
      allow(Autonomia::Desempenho::LeituraAutomatica::Gravacao).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap { |gravacao| allow(gravacao).to receive(:gravar!).and_raise(NoMethodError) }
      end

      rodada = rodar

      expect(corpos.size).to eq(3)
      expect(rodada).to have_attributes(status: 'erro', conversas_lidas: 0, conversas_pendentes: 6)
      expect([falhas_de(primeira), falhas_de(segunda)]).to eq([nil, nil])
      expect(Autonomia::Desempenho::Leitura.where(conversation_id: [primeira.id, segunda.id]).count).to eq(0)
    end

    it 'sem retry interno: 503 e timeout custam uma chamada por conversa' do
      url = 'https://api.openai.com/v1/responses'
      stub_request(:post, url).to_return(status: 503, body: { error: { message: 'falhou' } }.to_json,
                                         headers: { 'Content-Type' => 'application/json' })
      expect(rodar).to have_attributes(status: 'ok', conversas_pendentes: 2)
      expect(a_request(:post, url)).to have_been_made.times(2)

      WebMock.reset!
      stub_request(:post, url).to_timeout
      expect(travel_to(agora + 1.day) { described_class.new(ficha).call }).to have_attributes(status: 'ok', conversas_pendentes: 2)
      expect(a_request(:post, url)).to have_been_made.times(2)
    end

    it 'um erro inesperado isolado deixa só aquela conversa pendente, sem contar falha, e segue para a próxima' do
      openai_devolve({ 'procuras' => [procura('inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] },
                     { 'procuras' => [procura('inicio' => '10-21 15:00', 'fim' => '10-21 15:01')] })
      gravar = Autonomia::Desempenho::LeituraAutomatica::Gravacao.instance_method(:gravar!)
      allow(Autonomia::Desempenho::LeituraAutomatica::Gravacao).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap do |gravacao|
          allow(gravacao).to receive(:gravar!) do |procuras|
            raise ActiveRecord::RecordInvalid, Autonomia::Desempenho::Procura.new if argumentos[:conversa].id == primeira.id

            gravar.bind_call(gravacao, procuras)
          end
        end
      end

      expect(rodar).to have_attributes(status: 'ok', conversas_lidas: 1, conversas_pendentes: 1)
      expect(procuras_de(segunda).count).to eq(1)
      expect(falhas_de(primeira)).to be_nil
    end

    it 'a mesma conversa com erro inesperado na 5ª rodada seguida fica não lida e sai da fila' do
      openai_devolve({ 'procuras' => [procura('inicio' => '10-21 15:00', 'fim' => '10-21 15:01')] })
      gravar = Autonomia::Desempenho::LeituraAutomatica::Gravacao.instance_method(:gravar!)
      allow(Autonomia::Desempenho::LeituraAutomatica::Gravacao).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap do |gravacao|
          allow(gravacao).to receive(:gravar!) do |procuras|
            raise NoMethodError if argumentos[:conversa].id == primeira.id

            gravar.bind_call(gravacao, procuras)
          end
        end
      end

      4.times do |dia|
        expect(travel_to(agora + dia.days) { described_class.new(ficha).call }).to have_attributes(status: 'ok', conversas_pendentes: 1)
      end
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: primeira.id)).to be_nil

      quinta = travel_to(agora + 4.days) { described_class.new(ficha).call }

      expect(quinta).to have_attributes(status: 'ok', conversas_lidas: 1, conversas_pendentes: 0, pendente_desde: nil)
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: primeira.id).status).to eq('nao_lida')
      expect(falhas_de(primeira, quando: agora + 4.days)).to be_nil
      chamadas = corpos.size
      travel_to(agora + 5.days) { described_class.new(ficha).call }
      expect(corpos.size).to eq(chamadas)
    end

    it 'ficha com faixa quebrada fecha a rodada como erro antes de qualquer chamada' do
      cortes = ficha.configuracao['cortes'] + [{ 'id' => 'itens', 'campo' => 'itens', 'faixas' => [[5, 1, 'ao contrário']] }]
      ficha.update!(configuracao: ficha.configuracao.merge('cortes' => cortes))
      openai_devolve({ 'procuras' => [procura] })

      expect(rodar).to have_attributes(status: 'erro')
      expect(corpos).to be_empty
    end

    it 'erro inesperado fora de uma conversa grava erro na rodada e sobe como RodadaComErro, com a causa' do
      allow(Autonomia::Desempenho::LeituraAutomatica::Candidatas).to receive(:new).and_raise(ActiveRecord::StatementInvalid)

      expect { rodar }.to raise_error(described_class::RodadaComErro) { |erro| expect(erro.cause).to be_a(ActiveRecord::StatementInvalid) }
      expect(Autonomia::Desempenho::Rodada.last.status).to eq('erro')
    end

    it 'rodada interrompida no meio (deploy) fecha como erro e solta a trava' do
      allow(Autonomia::Desempenho::LeituraAutomatica::Leitor).to receive(:new).and_wrap_original do |original, **argumentos|
        original.call(**argumentos).tap { |leitor| allow(leitor).to receive(:ler).and_raise(Interrupt) }
      end

      expect { rodar }.to raise_error(Interrupt)
      expect(Autonomia::Desempenho::Rodada.last).to have_attributes(status: 'erro', terminada_em: be_present)
      expect(redis_get("autonomia:desempenho:leitura:#{account.id}:trava")).to be_nil
    end

    it 'o update! da rodada que falha não engana a interrompida!: o status do banco segue rodando e ela fecha erro' do
      rodada = Autonomia::Desempenho::Rodada.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, corte_em: agora,
                                                     piso_em: agora - 1.day, iniciada_em: agora, status: 'rodando', lote: 'spec')
      rodada.status = 'ok'

      rodada.interrompida!

      expect(rodada.reload.status).to eq('erro')
    end

    it 'a conversa com erro passageiro (tempo esgotado) na 3ª rodada seguida fica não lida e sai da fila' do
      url = 'https://api.openai.com/v1/responses'
      stub_request(:post, url).to_return do |request|
        corpo = JSON.parse(request.body)
        corpos << corpo
        raise Net::ReadTimeout if corpo.dig('input', 0, 'content', 0, 'text').include?("CONVERSA #{primeira.display_id} ")

        { status: 200, body: { id: 'r', output_text: { 'procuras' => [procura('inicio' => '10-21 15:00', 'fim' => '10-21 15:01')] }.to_json,
                               usage: { input_tokens: 1, output_tokens: 1 } }.to_json, headers: { 'Content-Type' => 'application/json' } }
      end

      2.times do |dia|
        expect(travel_to(agora + dia.days) { described_class.new(ficha).call }).to have_attributes(status: 'ok', conversas_pendentes: 1)
      end
      terceira = travel_to(agora + 2.days) { described_class.new(ficha).call }

      expect(terceira).to have_attributes(status: 'ok', conversas_lidas: 1, conversas_pendentes: 0)
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: primeira.id).status).to eq('nao_lida')
      chamadas = corpos.size
      travel_to(agora + 3.days) { described_class.new(ficha).call }
      expect(corpos.size).to eq(chamadas)
    end

    it 'pula a conversa apagada depois de entrar na fila' do
      candidatas = instance_double(Autonomia::Desempenho::LeituraAutomatica::Candidatas, ids: [primeira.id + 10_000])
      allow(Autonomia::Desempenho::LeituraAutomatica::Candidatas).to receive(:new).and_return(candidatas)

      expect(rodar).to have_attributes(status: 'ok', conversas_lidas: 0, conversas_pendentes: 0)
      expect(corpos).to be_empty
    end

    it 'rodada ok sem pendentes leva o piso da próxima para o corte dela menos a margem' do
      openai_devolve({ 'procuras' => [procura('inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] },
                     { 'procuras' => [procura('inicio' => '10-21 15:00', 'fim' => '10-21 15:01')] })
      primeira_rodada = rodar
      expect(primeira_rodada).to have_attributes(status: 'ok', conversas_pendentes: 0, piso_em: Time.utc(2026, 10, 21, 12, 0))

      proxima = travel_to(agora + 1.day) { described_class.new(ficha).call }

      expect(described_class::MARGEM_DO_PISO).to eq(1.hour)
      expect(proxima.piso_em).to eq(primeira_rodada.corte_em - 1.hour)
    end
  end
end
