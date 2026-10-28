require 'rails_helper'

# Leitura automática do painel de desempenho (#2301), com a loja inventada de AutonomiaDesempenhoHelpers e a OpenAI
# simulada (stub_request). Nenhum dado de cliente.
RSpec.describe Autonomia::Desempenho::LeituraAutomatica::Orquestrador do
  let(:account) { create(:account) }
  let(:robo) { create(:agent_bot, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:equipe) { create(:user, account: account) }
  let(:ficha) do
    ficha_da_loja!(account, sujeito_id: robo.id).tap { |f| f.update!(chave_de_leitura: 'Leia a conversa da loja. Marque `teste` quando for teste.') }
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

    it 'não roda duas vezes ao mesmo tempo para o mesmo agente' do
      Redis::Alfred.set("autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:trava", 'outra', ex: 60)

      expect(rodar).to be_nil
      expect(Autonomia::Desempenho::Rodada.count).to eq(0)
    ensure
      Redis::Alfred.delete("autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:trava")
    end
  end

  describe 'falha' do
    let!(:cresceu) { conversa_com_agente(14) }

    before do
      leitura!(conversa_com_agente(10), Time.utc(2026, 10, 21, 12, 0))
      leitura!(cresceu, Time.utc(2026, 10, 21, 14, 0))
      procura_da_carga!(cresceu, Time.utc(2026, 10, 21, 14, 0))
    end

    it 'mantém as procuras antigas; na segunda falha seguida, a conversa fica não lida' do
      openai_devolve(500)

      primeira = rodar
      expect(primeira).to have_attributes(status: 'ok', conversas_lidas: 0, conversas_pendentes: 1)
      expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: cresceu.id).status).to eq('lida')

      segunda = travel_to(agora + 1.day) { described_class.new(ficha).call }
      expect(segunda).to have_attributes(status: 'ok', conversas_lidas: 1, conversas_pendentes: 0)
      expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])
      expect(Autonomia::Desempenho::Leitura.find_by(conversation_id: cresceu.id))
        .to have_attributes(status: 'nao_lida', lida_ate_em: Time.utc(2026, 10, 21, 14, 1))
    end

    it 'recusa id fora do catálogo, JSON quebrado e horário que não é de mensagem, sem tocar nas procuras antigas' do
      [{ 'procuras' => [procura('tema' => 'inventado', 'inicio' => '10-21 14:00', 'fim' => '10-21 14:01')] },
       { 'procuras' => [procura('inicio' => '10-21 09:00', 'fim' => '10-21 14:01')] },
       { 'procuras' => [procura('inicio' => '10-21 14:01', 'fim' => '10-21 14:00')] },
       { 'procuras' => [] }, '{"procuras": ['].each do |resposta|
        Redis::Alfred.delete("autonomia:desempenho:leitura:#{account.id}:robo:#{robo.id}:falhas:#{cresceu.id}")
        openai_devolve(resposta)

        expect(rodar).to have_attributes(conversas_lidas: 0, conversas_pendentes: 1)
        expect(procuras_de(cresceu).pluck(:lote)).to eq(['carga'])
      end
    end
  end
end
