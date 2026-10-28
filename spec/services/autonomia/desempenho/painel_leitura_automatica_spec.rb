require 'rails_helper'

# O que a leitura automática (#2301) acrescenta ao painel: "Lido até", a situação da última rodada, o aviso de
# instrução mudada e as sugestões de outro período com as datas delas. Loja inventada.
RSpec.describe Autonomia::Desempenho::Painel do
  let(:account) { create(:account) }
  let(:robo) { create(:agent_bot, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:painel) { described_class.new(account: account, sujeito_type: 'robo', sujeito_id: robo.id) }

  def rodada!(status, corte, tipo: 'robo', id: robo.id)
    Autonomia::Desempenho::Rodada.create!(account: account, sujeito_type: tipo, sujeito_id: id, corte_em: corte, piso_em: corte - 1.day,
                                          iniciada_em: corte, status: status, lote: 'spec')
  end

  before do
    ficha_da_loja!(account, sujeito_id: robo.id)
    procura_da_loja!(conversa, sujeito_id: robo.id, inicio: '2026-10-20 10:00')
    leitura_da_loja!(conversa, sujeito_id: robo.id, ate: '2026-10-22 18:00')
  end

  it 'sem rodada: nada de lido_ate nem de situação' do
    meta = painel.call('7')['meta']

    expect(meta).to include('lido_ate' => nil, 'situacao' => nil, 'instrucao_mudou' => nil, 'recomendacoes_de' => nil)
  end

  it 'lido_ate é o corte da última rodada que leu, no fuso; a situação vem da última rodada que parou' do
    rodada!('ok', Time.utc(2026, 10, 22, 10, 0))
    rodada!('teto', Time.utc(2026, 10, 23, 10, 0))
    rodada!('sem_ia', Time.utc(2026, 10, 24, 10, 0))

    meta = painel.call('7')['meta']

    expect(meta).to include('lido_ate' => '2026-10-23T07:00', 'situacao' => 'sem_ia')
  end

  it 'teto na última rodada vira a situação; ok depois limpa' do
    rodada!('teto', Time.utc(2026, 10, 23, 10, 0))
    expect(painel.call('7')['meta']['situacao']).to eq('teto')

    rodada!('ok', Time.utc(2026, 10, 24, 10, 0))
    expect(painel.call('7')['meta']).to include('situacao' => nil, 'lido_ate' => '2026-10-24T07:00')
  end

  it 'sem as sugestões do período exato, mostra as últimas do mesmo período com as datas delas' do
    Autonomia::Desempenho::Recomendacao.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, periodo: '7',
                                                inicio: Date.new(2026, 10, 10), fim: Date.new(2026, 10, 16), versao_ficha: 1,
                                                cartoes: [{ 'id' => 'r1' }], gerada_em: Time.current, lote: 'spec')

    resultado = painel.call('7')

    expect(resultado['recomendacoes']).to eq([{ 'id' => 'r1' }])
    expect(resultado['meta']['recomendacoes_de']).to eq('inicio' => '2026-10-10', 'fim' => '2026-10-16')
  end

  describe 'aviso de instrução' do
    let(:agente) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Atendente', agent_type: 'custom', status: :active, enabled: true,
                                       instruction: 'Responda com o prazo.')
    end
    let(:ficha) do
      base = Autonomia::Desempenho::Ficha.do_sujeito(account, 'robo', robo.id).first
      Autonomia::Desempenho::Ficha.create!(base.attributes.except('id', 'created_at', 'updated_at')
                                               .merge('sujeito_type' => 'agente', 'sujeito_id' => agente.id))
    end
    let(:painel_do_agente) { described_class.new(account: account, sujeito_type: 'agente', sujeito_id: agente.id) }

    before do
      Autonomia::Desempenho::Procura.create!(account: account, sujeito_type: 'agente', sujeito_id: agente.id, conversation: conversa, ordem: 1,
                                             inicio_em: Time.utc(2026, 10, 20, 13), fim_em: Time.utc(2026, 10, 20, 13, 5), versao_ficha: 1,
                                             lote: 'spec')
      Autonomia::Desempenho::Leitura.create!(account: account, sujeito_type: 'agente', sujeito_id: agente.id, conversation: conversa,
                                             lida_ate_em: Time.utc(2026, 10, 22, 21), versao_ficha: 1, status: 'lida', lote: 'spec')
    end

    it 'avisa quando a instrução do agente mudou depois da chave de leitura' do
      ficha.update!(instrucao_hash: Autonomia::Desempenho::Ficha.hash_da_instrucao(account, 'agente', agente.id))
      expect(painel_do_agente.call('7')['meta']['instrucao_mudou']).to be(false)

      agente.update!(instruction: 'Responda com o prazo e o preço.')
      expect(described_class.new(account: account, sujeito_type: 'agente', sujeito_id: agente.id).call('7')['meta']['instrucao_mudou']).to be(true)
    end

    it 'sem hash guardado, e para o robô de outro sistema, não avisa' do
      ficha
      expect(painel_do_agente.call('7')['meta']['instrucao_mudou']).to be_nil
      expect(painel.call('7')['meta']['instrucao_mudou']).to be_nil
    end
  end
end
