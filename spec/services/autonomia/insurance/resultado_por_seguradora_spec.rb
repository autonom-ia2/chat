require 'rails_helper'

# AS DEZESSETE SEGURADORAS DE UMA COTAÇÃO REAL, na forma que o `Connector::Http` entrega (dados sintéticos:
# os nomes são os das seguradoras que o portal lista; valores e textos são inventados). Onze cotam com
# parcelamento, seis recusam pela idade do veículo (um texto do corpus do conector, que sai com categoria).
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

    it 'guarda sem proposta com a categoria do motivo, e nunca o texto do portal' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco)])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'motivo' => 'veiculo')
      expect(guardado.to_json).not_to include(risco['text'])
    end

    it 'guarda sem proposta e sem motivo quando o kind não é risco nem passageiro' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco.merge('kind' => 'outro'))])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta')
    end

    # chat#323: a seguradora instável guarda a categoria, sem o texto do portal.
    it 'guarda a instabilidade quando o kind é passageiro' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco.merge('kind' => 'passageiro'))])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'motivo' => 'instabilidade')
      expect(guardado.to_json).not_to include(risco['text'])
    end

    it 'guarda sem proposta e sem motivo quando o texto de risco tem termo de conta' do
      reason = { 'kind' => 'risco', 'text' => 'Senha expirou. Declinando cálculo.' }

      expect(described_class.unir({}, [recusou('19', 'Sancor', reason: reason)])['19'])
        .to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta')
    end

    # CREDENCIAL DA CORRETORA: nada que possa chegar ao cliente, nem com um motivo que a regra liberaria.
    it 'auth_required vira sem proposta e nunca guarda motivo' do
      guardado = described_class.unir({}, [recusou('13', 'Mitsui', status: 'auth_required', reason: risco)])

      expect(guardado['13']).to eq('nome' => 'Mitsui', 'desfecho' => 'sem_proposta')
      expect(guardado.to_json).not_to include('auth_required', 'risco', risco['text'])
    end

    it 'error sem preço é sem proposta, com a categoria do motivo' do
      expect(described_class.unir({}, [recusou('9', 'Ezze', status: 'error', reason: risco)])['9'])
        .to include('desfecho' => 'sem_proposta', 'motivo' => 'veiculo')
    end

    # NENHUM TEXTO DO PORTAL NO BANCO: o corpus do conector, no status e no kind que o conector dá, e os das revisões.
    it 'não guarda texto do portal de nenhuma mensagem do corpus nem das revisões' do
      revisoes = (TextosDoMotivo::CONTA + TextosDoMotivo::PESSOA + TextosDoMotivo::REVISOES).map { |texto| [texto, 'risco', 'declined'] }
      linhas = TextosDoMotivo::CORPUS.map { |linha| linha.first(3) } + revisoes
      ofertas = linhas.each_with_index.map do |(texto, kind, status), i|
        recusou(i.to_s, "Seguradora #{i}", status: status, reason: { 'kind' => kind, 'text' => texto })
      end
      guardado = described_class.unir({}, ofertas).to_json

      expect(linhas.map(&:first).select { |texto| guardado.include?(texto) }).to be_empty
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

    # Guarda-se a categoria, e não o texto: o pior caso das recusas é o de dezessete com categoria.
    it 'dezessete recusas com a categoria do motivo cabem em 2 KB' do
      ofertas = (1..17).map { |i| recusou(i.to_s, "Seguradora #{i}", reason: risco) }
      guardado = described_class.unir({}, ofertas)

      expect(guardado.values).to all(include('motivo' => 'veiculo'))
      expect(guardado.to_json.bytesize).to be <= 2_000
    end
  end
end
