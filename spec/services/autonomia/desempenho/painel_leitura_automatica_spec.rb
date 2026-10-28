require 'rails_helper'

# O que a leitura automática (#2301) acrescenta ao painel: "Lido até", a situação da última rodada, o aviso de
# instrução mudada, as sugestões de outro período com as datas delas, as conversas não lidas e o período que termina
# no "Lido até". Tudo só com a ENV ligada e a ficha com chave de leitura. Loja inventada.
RSpec.describe Autonomia::Desempenho::Painel do
  let(:account) { create(:account) }
  let(:robo) { create(:agent_bot, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:painel) { described_class.new(account: account, sujeito_type: 'robo', sujeito_id: robo.id) }

  # `lidas`: a rodada `teto` que não leu nada não conta como leitura (Rodada.leram).
  def rodada!(status, corte, pendentes: 0, pendente_desde: nil, lidas: 1)
    Autonomia::Desempenho::Rodada.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, corte_em: corte, piso_em: corte - 1.day,
                                          iniciada_em: corte, status: status, lote: 'spec', conversas_pendentes: pendentes, conversas_lidas: lidas,
                                          pendente_desde: pendente_desde)
  end

  around { |exemplo| with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'true') { exemplo.run } }

  before do
    ficha_da_loja!(account, sujeito_id: robo.id).update!(chave_de_leitura: 'Leia a conversa da loja.')
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

  it 'com pendentes, lido_ate é antes da mensagem pendente mais antiga gravada na rodada, mesmo com leitura mais recente' do
    rodada!('teto', Time.utc(2026, 10, 23, 10, 0), pendentes: 1, pendente_desde: Time.utc(2026, 10, 22, 12, 0))
    allow(Autonomia::Desempenho::LeituraAutomatica::Candidatas).to receive(:new)

    # A leitura de `conversa` vai até 22/10 18:00; a pendente espera desde 22/10 09:00 (fuso da loja).
    expect(painel.call('7')['meta']).to include('lido_ate' => '2026-10-22T08:59', 'situacao' => 'teto')
    # O painel não refaz a consulta da fila.
    expect(Autonomia::Desempenho::LeituraAutomatica::Candidatas).not_to have_received(:new)
  end

  it 'com pendentes sem a mensagem gravada, lido_ate é o piso da rodada, nunca a leitura mais recente' do
    rodada!('teto', Time.utc(2026, 10, 23, 10, 0), pendentes: 3)

    expect(painel.call('7')['meta']).to include('lido_ate' => '2026-10-22T07:00', 'situacao' => 'teto')
  end

  it 'a rodada que caiu antes de ler aparece como erro e não move o lido_ate' do
    rodada!('ok', Time.utc(2026, 10, 22, 10, 0))
    rodada!('erro', Time.utc(2026, 10, 23, 10, 0), lidas: 0)

    expect(painel.call('7')['meta']).to include('situacao' => 'erro', 'lido_ate' => '2026-10-22T07:00')
  end

  it 'a rodada que caiu depois de ler move o lido_ate até antes da pendente: os números mostram o que ela leu' do
    rodada!('ok', Time.utc(2026, 10, 22, 10, 0))
    rodada!('erro', Time.utc(2026, 10, 23, 10, 0), pendentes: 2, pendente_desde: Time.utc(2026, 10, 22, 21, 0))

    expect(painel.call('7')['meta']).to include('situacao' => 'erro', 'lido_ate' => '2026-10-22T17:59', 'pendentes' => 2)
  end

  it 'teto na última rodada vira a situação; ok depois limpa' do
    rodada!('teto', Time.utc(2026, 10, 23, 10, 0))
    expect(painel.call('7')['meta']['situacao']).to eq('teto')

    rodada!('ok', Time.utc(2026, 10, 24, 10, 0))
    expect(painel.call('7')['meta']).to include('situacao' => nil, 'lido_ate' => '2026-10-24T07:00')
  end

  it 'a rodada teto que não leu nada não move o lido_ate, mas a situação é teto' do
    rodada!('ok', Time.utc(2026, 10, 22, 10, 0))
    rodada!('teto', Time.utc(2026, 10, 23, 10, 0), lidas: 0, pendentes: 2)

    expect(painel.call('7')['meta']).to include('lido_ate' => '2026-10-22T07:00', 'situacao' => 'teto')
  end

  it 'com uma rodada rodando agora, a parada de antes não aparece' do
    rodada!('teto', Time.utc(2026, 10, 22, 10, 0))
    rodada!('rodando', Time.utc(2026, 10, 23, 10, 0), lidas: 0)

    expect(painel.call('7')['meta']['situacao']).to be_nil
  end

  it 'com uma rodada rodando agora, as pendentes da última fechada continuam no aviso' do
    rodada!('teto', Time.utc(2026, 10, 22, 10, 0), pendentes: 3)
    rodada!('rodando', Time.utc(2026, 10, 23, 10, 0), lidas: 0)

    expect(painel.call('7')['meta']['pendentes']).to eq(3)
  end

  it 'as pendentes da última rodada que leu vão em pendentes e, com a parada, em avisos para as exportações' do
    rodada!('teto', Time.utc(2026, 10, 23, 10, 0), pendentes: 3)

    resultado = painel.call('7')

    expect(resultado['meta']['pendentes']).to eq(3)
    expect(resultado['avisos']).to include({ 'id' => 'leitura_teto', 'valores' => {} },
                                           { 'id' => 'leitura_pendentes', 'valores' => { 'n' => 3 } })
  end

  it 'a chave recusada pela IA vira a situação própria' do
    rodada!('chave_recusada', Time.utc(2026, 10, 23, 10, 0))

    expect(painel.call('7')['meta']['situacao']).to eq('chave_recusada')
  end

  it 'o período termina no dia do lido_ate quando ele vem antes da última mensagem lida' do
    # A leitura de `conversa` vai até 22/10 18:00 (fuso da loja); a rodada leu só até 20/10 09:00, com pendentes.
    rodada!('teto', Time.utc(2026, 10, 21, 10, 0), pendentes: 4, pendente_desde: Time.utc(2026, 10, 20, 12, 0, 1))

    meta = painel.call('7')['meta']

    expect(meta).to include('lido_ate' => '2026-10-20T09:00', 'dados_ate' => '2026-10-20T09:00')
    expect(meta['periodo']).to include('fim' => '2026-10-20')
  end

  it 'com a ENV desligada (o rollback), as rodadas antigas não mudam nada' do
    rodada!('teto', Time.utc(2026, 10, 21, 10, 0), pendentes: 4, pendente_desde: Time.utc(2026, 10, 20, 12, 0, 1))
    rodada!('erro', Time.utc(2026, 10, 22, 10, 0))

    meta = with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'false') { painel.call('7')['meta'] }

    expect(meta).to include('lido_ate' => nil, 'situacao' => nil, 'nao_lidas' => 0, 'dados_ate' => '2026-10-22T18:00')
    expect(meta['periodo']).to include('fim' => '2026-10-22')
  end

  it 'sem a chave de leitura na ficha, as rodadas antigas também não mudam nada' do
    Autonomia::Desempenho::Ficha.do_sujeito(account, 'robo', robo.id).update_all(chave_de_leitura: nil) # rubocop:disable Rails/SkipsModelValidations
    rodada!('erro', Time.utc(2026, 10, 22, 10, 0))

    expect(painel.call('7')['meta']).to include('lido_ate' => nil, 'situacao' => nil)
  end

  it 'conta as conversas que a leitura automática deixou como não lidas' do
    outra = create(:conversation, account: account, inbox: inbox)
    Autonomia::Desempenho::Leitura.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, conversation: outra,
                                           lida_ate_em: Time.utc(2026, 10, 21, 18), versao_ficha: 1, status: 'nao_lida',
                                           lote: 'leitura_automatica')
    rodada!('ok', Time.utc(2026, 10, 22, 10, 0))

    expect(painel.call('7')['meta']['nao_lidas']).to eq(1)
  end

  it 'as não lidas contam só as do período e sem procura de teste' do
    [Time.utc(2026, 10, 21, 18), Time.utc(2026, 9, 1, 18), Time.utc(2026, 10, 21, 19)].each_with_index do |ate, indice|
      outra = create(:conversation, account: account, inbox: inbox)
      Autonomia::Desempenho::Leitura.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, conversation: outra,
                                             lida_ate_em: ate, versao_ficha: 1, status: 'nao_lida', lote: 'leitura_automatica')
      next unless indice == 2

      Autonomia::Desempenho::Procura.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, conversation: outra, ordem: 1,
                                             inicio_em: ate - 1.hour, fim_em: ate, versao_ficha: 1, lote: 'spec', teste: true)
    end
    rodada!('ok', Time.utc(2026, 10, 22, 10, 0))

    resultado = painel.call('7')

    expect(resultado['meta']['nao_lidas']).to eq(1)
    expect(resultado['avisos']).to include({ 'id' => 'leitura_nao_lidas', 'valores' => { 'n' => 1 } })
  end

  it 'sem as sugestões do período exato, mostra as últimas do mesmo período com as datas delas' do
    rodada!('ok', Time.utc(2026, 10, 22, 10, 0))
    Autonomia::Desempenho::Recomendacao.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, periodo: '7',
                                                inicio: Date.new(2026, 10, 10), fim: Date.new(2026, 10, 16), versao_ficha: 1,
                                                cartoes: [{ 'id' => 'r1' }], gerada_em: Time.current, lote: 'spec')

    resultado = painel.call('7')

    expect(resultado['recomendacoes']).to eq([{ 'id' => 'r1' }])
    expect(resultado['meta']['recomendacoes_de']).to eq('inicio' => '2026-10-10', 'fim' => '2026-10-16')
  end

  it 'só rodadas que não leram nada (sem_ia, erro) não trazem sugestões de outras datas' do
    rodada!('sem_ia', Time.utc(2026, 10, 22, 10, 0), lidas: 0)
    rodada!('erro', Time.utc(2026, 10, 23, 10, 0), lidas: 0)
    Autonomia::Desempenho::Recomendacao.create!(account: account, sujeito_type: 'robo', sujeito_id: robo.id, periodo: '7',
                                                inicio: Date.new(2026, 10, 10), fim: Date.new(2026, 10, 16), versao_ficha: 1,
                                                cartoes: [{ 'id' => 'r1' }], gerada_em: Time.current, lote: 'spec')

    resultado = painel.call('7')

    expect(resultado['recomendacoes']).not_to eq([{ 'id' => 'r1' }])
    expect(resultado['meta']['recomendacoes_de']).to be_nil
  end

  describe '.situacao_sem_procuras (o painel vazio)' do
    def situacao = described_class.situacao_sem_procuras(account, 'robo', robo.id)

    it 'com a leitura automática ligada: lendo antes da primeira rodada e durante uma, depois a parada ou sem conversas' do
      expect(situacao).to eq('lendo')
      rodada!('sem_ia', Time.utc(2026, 10, 22, 10, 0), lidas: 0)
      expect(situacao).to eq('sem_ia')
      rodada!('rodando', Time.utc(2026, 10, 23, 10, 0), lidas: 0)
      expect(situacao).to eq('lendo')
      Autonomia::Desempenho::Rodada.last.update!(status: 'ok')
      expect(situacao).to eq('sem_conversas')
    end

    it 'sem a leitura automática (ENV desligada ou ficha sem chave), leitura_desligada como antes' do
      rodada!('erro', Time.utc(2026, 10, 22, 10, 0))
      expect(with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'false') { situacao }).to eq('leitura_desligada')

      Autonomia::Desempenho::Ficha.do_sujeito(account, 'robo', robo.id).update_all(chave_de_leitura: nil) # rubocop:disable Rails/SkipsModelValidations
      expect(situacao).to eq('leitura_desligada')
    end
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

    it 'com a leitura automática desligada não avisa: ninguém lê com a chave' do
      ficha.update!(instrucao_hash: 'outra')

      meta = with_modified_env(AUTONOMIA_DESEMPENHO_LEITURA_AUTOMATICA: 'false') { painel_do_agente.call('7')['meta'] }

      expect(meta['instrucao_mudou']).to be_nil
    end

    it 'sem hash guardado, e para o robô de outro sistema, não avisa' do
      ficha
      expect(painel_do_agente.call('7')['meta']['instrucao_mudou']).to be_nil
      expect(painel.call('7')['meta']['instrucao_mudou']).to be_nil
    end
  end
end
