require 'rails_helper'

# AS DEZESSETE SEGURADORAS DE UMA COTAÇÃO REAL, na forma que o `Connector::Http` entrega (dados sintéticos:
# os nomes são os das seguradoras que o portal lista; valores e textos são inventados). Onze cotam com
# parcelamento, seis recusam pela idade do veículo (um texto do corpus do conector, guardado para a equipe).
module DezesseteSeguradoras
  COTAM = { '50' => 'Pier', '55' => 'Bp Assinatura', '44' => 'Usebens', '8' => 'Porto Seguro', '20' => 'Suhai',
            '11' => 'Tokio', '47' => 'Justos', '3' => 'Mapfre', '5' => 'Allianz', '26' => 'Ituran', '56' => 'Azul' }.freeze
  RECUSAM = { '48' => 'Bp', '46' => 'Darwin', '1' => 'Bradesco', '4' => 'Hdi', '19' => 'Sancor', '7' => 'Zurich' }.freeze
  RISCO_DO_VEICULO = 'Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida'.freeze

  module_function

  def ofertas
    cotam = COTAM.each_with_index.map do |(code, name), i|
      { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
        'premium' => { 'amount' => 2119.18 + (i * 101.37), 'currency' => 'BRL', 'basis' => 'total',
                       'basis_evidence' => 'parcelas=10 x premioDemaisParc=211.92 fecha com premio=2119.18',
                       'installments' => { 'count' => 10, 'amount' => 211.92 + (i * 10.14) } } }
    end
    recusam = RECUSAM.map do |code, name|
      { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'declined',
        'reason' => { 'kind' => 'risco', 'text' => RISCO_DO_VEICULO } }
    end
    cotam + recusam
  end
end

# O RESULTADO POR SEGURADORA GUARDADO NO HANDLE DA COTAÇÃO (fatia 2 do #420).
RSpec.describe Autonomia::Insurance::ResultadoPorSeguradora do
  def cotou(code, name, amount, extra = {})
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'quoted',
      'premium' => { 'amount' => amount, 'currency' => 'BRL', 'basis' => 'total',
                     'basis_evidence' => 'parcelas=1 fecha' }.merge(extra) }
  end

  def recusou(code, name, status: 'declined', reason: nil)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => status, 'reason' => reason }.compact
  end

  def correndo(code, name)
    { 'insurer' => { 'code' => code, 'name' => name }, 'status' => 'running' }
  end

  let(:risco) { { 'kind' => 'risco', 'text' => 'Tipo de veículo não aceito.' } }

  describe 'uma leitura' do
    it 'guarda nome e prêmio de quem cotou, só com os campos que o item de preço usa' do
      guardado = described_class.unir({}, [cotou('8', 'Porto Seguro', 2119.18, 'installments' => { 'count' => 10, 'amount' => 211.92 })])

      expect(guardado).to eq('8' => { 'nome' => 'Porto Seguro', 'desfecho' => 'com_preco',
                                      'premio' => { 'amount' => 2119.18, 'basis' => 'total',
                                                    'installments' => { 'count' => 10, 'amount' => 211.92 } } })
    end

    # chat#612: a recusa do risco guarda o que a seguradora escreveu, para a nota da equipe, e nenhuma categoria.
    it 'guarda sem proposta com o texto da recusa, sem categoria' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco)])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'texto_da_recusa' => risco['text'])
    end

    it 'guarda o texto também quando o kind é outro' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco.merge('kind' => 'outro'))])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'texto_da_recusa' => risco['text'])
    end

    it 'o texto guardado sai limpo e curto' do
      longo = { 'kind' => 'risco', 'text' => "  Veículo   sem\naceitação #{'x' * 400}" }
      texto = described_class.unir({}, [recusou('19', 'Sancor', reason: longo)])['19']['texto_da_recusa']

      expect(texto).to start_with('Veículo sem aceitação x')
      expect(texto.length).to eq(described_class::MAX_TEXTO)
    end

    it 'texto que não é String válida não é guardado' do
      invalido = { 'kind' => 'risco', 'text' => "Tipo de ve\xC3culo" }

      expect(described_class.unir({}, [recusou('19', 'Sancor', reason: invalido)])['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta')
      expect(described_class.unir({}, [recusou('19', 'Sancor', reason: { 'kind' => 'risco', 'text' => 42 })])['19'])
        .to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta')
    end

    # chat#323: a seguradora instável guarda a categoria, sem o texto do portal.
    it 'guarda a instabilidade quando o kind é passageiro' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco.merge('kind' => 'passageiro'))])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'motivo' => 'instabilidade')
      expect(guardado.to_json).not_to include(risco['text'])
    end

    it 'a conta da corretora (kind credencial) não guarda texto, só a marca' do
      reason = { 'kind' => 'credencial', 'text' => 'Senha expirou. Declinando cálculo.' }

      expect(described_class.unir({}, [recusou('19', 'Sancor', reason: reason)])['19'])
        .to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'credencial' => true)
    end

    # CREDENCIAL DA CORRETORA: nada que possa chegar ao cliente, nem com um motivo que a regra liberaria.
    # Revisão da chat#639: a conta da corretora recusada vira só uma marca, para a nota da equipe; nem texto nem motivo.
    it 'auth_required ou kind credencial vira sem proposta com a marca da credencial, sem texto nem motivo' do
      guardado = described_class.unir({}, [recusou('13', 'Mitsui', status: 'auth_required', reason: risco),
                                           recusou('4', 'Hdi', reason: { 'kind' => 'credencial', 'text' => 'Senha expirou.' })])

      expect(guardado['13']).to eq('nome' => 'Mitsui', 'desfecho' => 'sem_proposta', 'credencial' => true)
      expect(guardado['4']).to eq('nome' => 'Hdi', 'desfecho' => 'sem_proposta', 'credencial' => true)
      expect(guardado.to_json).not_to include('auth_required', 'risco', risco['text'], 'Senha')
    end

    it 'error sem preço é sem proposta, sem categoria e sem texto' do
      expect(described_class.unir({}, [recusou('9', 'Ezze', status: 'error', reason: risco)])['9'])
        .to eq('nome' => 'Ezze', 'desfecho' => 'sem_proposta')
    end

    # O TEXTO SÓ DA RECUSA DO RISCO: o corpus do conector, no status e no kind que o conector dá. Credencial da corretora
    # e seguradora instável nunca guardam texto.
    it 'no corpus, guarda o texto só de declined com kind risco ou outro' do
      linhas = TextosDoMotivo::CORPUS.map { |linha| linha.first(3) }
      ofertas = linhas.each_with_index.map do |(texto, kind, status), i|
        recusou(i.to_s, "Seguradora #{i}", status: status, reason: { 'kind' => kind, 'text' => texto })
      end
      guardado = described_class.unir({}, ofertas)
      com_texto = linhas.each_index.select { |i| guardado[i.to_s].key?('texto_da_recusa') }
      esperado = linhas.each_index.select { |i| linhas[i][2] == 'declined' && described_class::KINDS_COM_TEXTO.include?(linhas[i][1]) }

      expect(com_texto).to eq(esperado)
      expect(esperado.size).to be < linhas.size
    end

    it 'seguradora sem desfecho e quoted sem valor ficam aguardando' do
      sem_valor = cotou('3', 'Mapfre', nil)
      guardado = described_class.unir({}, [correndo('47', 'Justos'), sem_valor])

      expect(guardado.transform_values { |entrada| entrada['desfecho'] }).to eq('47' => 'aguardando', '3' => 'aguardando')
    end

    it 'oferta sem código fica de fora' do
      expect(described_class.unir({}, [cotou('', 'Sem Código', 100.0)])).to eq({})
    end
  end

  describe 'a união entre leituras' do
    # Revisão da chat#634: a recusa que chega primeiro sem texto (ou gravada antes desta versão) não esconde o texto
    # que vem depois, e a nota da equipe não sai sem aquela seguradora.
    it 'a recusa que agora traz o texto substitui a guardada sem ele, e não o contrário' do
      sem_texto = described_class.unir({}, [recusou('19', 'Sancor', status: 'error')])
      com_texto = described_class.unir(sem_texto, [recusou('19', 'Sancor', reason: risco)])
      depois = described_class.unir(com_texto, [recusou('19', 'Sancor', status: 'error')])

      expect(com_texto['19']).to include('texto_da_recusa' => risco['text'])
      expect(depois['19']).to include('texto_da_recusa' => risco['text'])
    end

    it 'mantém a seguradora que a leitura nova não listou' do
      primeira = described_class.unir({}, [cotou('8', 'Porto Seguro', 2119.18), recusou('19', 'Sancor', reason: risco)])

      segunda = described_class.unir(primeira, [cotou('8', 'Porto Seguro', 2119.18)])

      expect(segunda.keys).to contain_exactly('8', '19')
    end

    it 'um desfecho não volta para aguardando' do
      primeira = described_class.unir({}, [cotou('8', 'Porto Seguro', 2119.18), recusou('19', 'Sancor', reason: risco)])

      segunda = described_class.unir(primeira, [correndo('8', 'Porto Seguro'), correndo('19', 'Sancor')])

      expect(segunda).to eq(primeira)
    end

    it 'o preço guardado não muda com a leitura seguinte, nem quando a seguradora aparece recusando' do
      primeira = described_class.unir({}, [cotou('8', 'Porto Seguro', 2119.18)])

      com_outro_valor = described_class.unir(primeira, [cotou('8', 'Porto Seguro', 2500.0)])
      recusando = described_class.unir(primeira, [recusou('8', 'Porto Seguro', reason: risco)])

      expect([com_outro_valor, recusando]).to all(eq(primeira))
    end

    it 'sem proposta vira com preço quando a seguradora cota numa leitura seguinte' do
      primeira = described_class.unir({}, [recusou('8', 'Porto Seguro', reason: risco)])

      segunda = described_class.unir(primeira, [cotou('8', 'Porto Seguro', 2119.18)])

      expect(segunda['8']['desfecho']).to eq('com_preco')
    end

    it 'aguardando ganha o desfecho que chega' do
      primeira = described_class.unir({}, [correndo('19', 'Sancor')])

      expect(described_class.unir(primeira, [recusou('19', 'Sancor', reason: risco)])['19']['desfecho']).to eq('sem_proposta')
    end

    it 'o guardado que não é Hash, e a entrada que não é Hash, dão lugar à leitura' do
      expect(described_class.unir('corrompido', [correndo('19', 'Sancor')]).keys).to eq(['19'])
      expect(described_class.unir({ '19' => 'x' }, [correndo('19', 'Sancor')])['19']['desfecho']).to eq('aguardando')
    end
  end

  describe 'com_preco?' do
    it 'responde pela entrada com preço' do
      expect(described_class.com_preco?(described_class.unir({}, [cotou('8', 'Porto Seguro', 2119.18)]))).to be(true)
      expect(described_class.com_preco?(described_class.unir({}, [recusou('19', 'Sancor', reason: risco)]))).to be(false)
      expect(described_class.com_preco?(nil)).to be(false)
      expect(described_class.com_preco?({})).to be(false)
    end
  end

  # O TAMANHO NO HANDLE, medido: dezessete seguradoras numa chave jsonb regravada a cada passada.
  describe 'o tamanho com 17 seguradoras' do
    it 'onze com preço e seis recusas com a categoria do motivo cabem em 3 KB' do
      guardado = described_class.unir({}, DezesseteSeguradoras.ofertas)

      expect(guardado.size).to eq(17)
      expect(guardado.to_json.bytesize).to be <= 3_000
    end

    # O pior caso das recusas: dezessete com o texto no limite (`MAX_TEXTO`).
    it 'dezessete recusas com o texto no limite cabem em 7 KB' do
      ofertas = (1..17).map { |i| recusou(i.to_s, "Seguradora #{i}", reason: { 'kind' => 'risco', 'text' => 'a' * 500 }) }
      guardado = described_class.unir({}, ofertas)

      expect(guardado.values.map { |entrada| entrada['texto_da_recusa'].length }).to all(eq(described_class::MAX_TEXTO))
      expect(guardado.to_json.bytesize).to be <= 7_000
    end
  end
end
