require 'rails_helper'

# AS DEZESSETE SEGURADORAS DE UMA COTAÇÃO REAL, na forma que o `Connector::Http` entrega (dados sintéticos:
# os nomes são os das seguradoras que o portal lista; valores e textos são inventados). Onze cotam com
# parcelamento, seis recusam com o texto de risco mais longo medido no conector (134 caracteres).
module DezesseteSeguradoras
  COTAM = { '50' => 'Pier', '55' => 'Bp Assinatura', '44' => 'Usebens', '8' => 'Porto Seguro', '20' => 'Suhai',
            '11' => 'Tokio', '47' => 'Justos', '3' => 'Mapfre', '5' => 'Allianz', '26' => 'Ituran', '56' => 'Azul' }.freeze
  RECUSAM = { '48' => 'Bp', '46' => 'Darwin', '1' => 'Bradesco', '4' => 'Hdi', '19' => 'Sancor', '7' => 'Zurich' }.freeze
  RISCO_LONGO = 'Após análise dos dados do veículo, região de circulação e critérios internos de aceitação, ' \
                'estamos declinando o risco deste orçamento.'.freeze

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
        'reason' => { 'kind' => 'risco', 'text' => RISCO_LONGO } }
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

  let(:risco) { { 'kind' => 'risco', 'text' => 'Risco sem aceitação para este cenário nesta seguradora.' } }

  describe 'uma leitura' do
    it 'guarda nome e prêmio de quem cotou, só com os campos que o item de preço usa' do
      guardado = described_class.unir({}, [cotou('8', 'Porto Seguro', 2119.18, 'installments' => { 'count' => 10, 'amount' => 211.92 })])

      expect(guardado).to eq('8' => { 'nome' => 'Porto Seguro', 'desfecho' => 'com_preco',
                                      'premio' => { 'amount' => 2119.18, 'basis' => 'total',
                                                    'installments' => { 'count' => 10, 'amount' => 211.92 } } })
    end

    it 'guarda sem proposta com o motivo quando a regra libera o texto' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco)])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta', 'motivo' => risco)
    end

    it 'guarda sem proposta e sem motivo quando o kind não é risco' do
      guardado = described_class.unir({}, [recusou('19', 'Sancor', reason: risco.merge('kind' => 'passageiro'))])

      expect(guardado['19']).to eq('nome' => 'Sancor', 'desfecho' => 'sem_proposta')
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

    it 'error sem preço é sem proposta, com o motivo liberado' do
      expect(described_class.unir({}, [recusou('9', 'Ezze', status: 'error', reason: risco)])['9'])
        .to include('desfecho' => 'sem_proposta', 'motivo' => risco)
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
    it 'onze com preço e seis recusas com o motivo mais longo medido cabem em 3 KB' do
      guardado = described_class.unir({}, DezesseteSeguradoras.ofertas)

      expect(guardado.size).to eq(17)
      expect(guardado.to_json.bytesize).to be <= 3_000
    end

    # O texto do teto é feito de palavras do vocabulário da regra (a quarta rodada exige), com acento: 7.072 bytes.
    it 'dezessete recusas com o motivo no teto de 300 caracteres cabem em 8 KB' do
      teto = { 'kind' => 'risco', 'text' => "Declinando o risco#{' do veículo' * 25}#{' do' * 2}." }
      ofertas = (1..17).map { |i| recusou(i.to_s, "Seguradora #{i}", reason: teto) }
      guardado = described_class.unir({}, ofertas)

      expect(teto['text'].length).to eq(Autonomia::Insurance::MotivoDaRecusa::TETO_DO_TEXTO)
      expect(guardado.values).to all(include('motivo' => teto))
      expect(guardado.to_json.bytesize).to be <= 8_000
    end
  end
end
