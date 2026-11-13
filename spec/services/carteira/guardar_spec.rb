require 'rails_helper'

# E4 (#2897): o gravador único da apólice. Quem traz um seguro (planilha, PDF, conector) entrega os dados já na forma do
# banco; aqui se decide se a apólice é nova, a mesma ou o termo novo. Os dados são fictícios.
RSpec.describe Carteira::Guardar do
  let(:account) { create(:account) }
  let(:pessoa) { create(:contact, account: account) }
  let(:user) { create(:user, account: account) }
  let(:comeca) { Date.new(2026, 3, 10) }
  let(:termina) { Date.new(2027, 3, 10) }
  let(:dados) do
    { seguradora: 'Seguradora Exemplo', seguradora_chave: 'seguradoraexemplo', numero: 'EX-001234', numero_chave: 'EX001234',
      tipo: 'auto', ramo_original: 'Automóvel', inicio_vigencia: comeca, fim_vigencia: termina, valor_centavos: 341_000,
      bem: 'Carro Exemplo 2022' }
  end
  # O primeiro passo da história que cada fonte diz ao gravador.
  let(:chegadas) { { 'planilha' => 'chegou_planilha', 'pdf' => 'pdf_anexado', 'conector' => 'chegou_agger', 'manual' => 'apolice_nova' } }

  def gravador(origem)
    described_class.new(account, origem: origem, user: user, valores: { arquivo: 'carteira-exemplo.csv' }, chegada: chegadas.fetch(origem))
  end

  def guardar(origem: 'planilha', contato: pessoa, **campos)
    gravador(origem).call(dados.merge(campos), contato: contato)
  end

  def apolices
    Carteira::Apolice.where(account_id: account.id)
  end

  def guardado(apolice)
    apolice.reload.attributes.symbolize_keys.slice(*dados.keys)
  end

  def passos(apolice)
    apolice.eventos.order(:id).pluck(:tipo)
  end

  def ultimas_mudancas(apolice)
    apolice.eventos.order(:id).last.mudancas
  end

  describe 'a apólice que a conta ainda não tem' do
    it 'nasce da pessoa, com a origem de quem chamou e o primeiro passo da história' do
      resultado = guardar
      apolice = resultado.apolice
      evento = apolice.eventos.sole

      expect(resultado.situacao).to eq('nova')
      expect(guardado(apolice)).to eq(dados)
      expect([apolice.account, apolice.contact, apolice.company]).to eq([account, pessoa, nil])
      expect([apolice.origem, apolice.corrigido_a_mao]).to eq(['planilha', []])
      expect([evento.tipo, evento.user, evento.mudancas]).to eq(['chegou_planilha', user, nil])
      expect(evento.valores).to eq('arquivo' => 'carteira-exemplo.csv')
    end

    it 'guarda a empresa segurada e a importação que trouxe, quando quem chama as entrega' do
      empresa = create(:company, account: account)
      importacao = create_campaign_import(account: account, user: user, content: "Nome;Celular\nAna Albuquerino;11987650001\n")
      trazida = described_class.new(account, origem: 'planilha', importacao: importacao)

      apolice = trazida.call(dados, contato: pessoa, empresa: empresa).apolice

      expect([apolice.company, apolice.campaign_import, apolice.eventos.sole.campaign_import]).to eq([empresa, importacao, importacao])
    end

    it 'aceita as datas em texto AAAA-MM-DD e as chaves em texto, e ignora o que não é dado da apólice' do
      de_fora = { 'cancelado_em' => Time.current, 'corrigido_a_mao' => ['valor'], 'origem' => 'manual' }
      em_texto = dados.merge(inicio_vigencia: '2026-03-10', fim_vigencia: '2027-03-10').stringify_keys.merge(de_fora)

      apolice = gravador('planilha').call(em_texto, contato: pessoa).apolice

      expect(guardado(apolice)).to eq(dados)
      expect([apolice.cancelado_em, apolice.corrigido_a_mao, apolice.origem]).to eq([nil, [], 'planilha'])
    end

    it 'sem número não há como achar a mesma: nasce outra a cada vez' do
      2.times { guardar(numero: nil, numero_chave: nil) }

      expect(apolices.count).to eq(2)
    end

    it 'não se mistura com a mesma seguradora e o mesmo número de outra conta' do
      outra = create(:account)
      de_fora = criar_apolice(create(:contact, account: outra), **dados.slice(:seguradora, :numero, :fim_vigencia), valor_centavos: 100)

      resultado = guardar(valor_centavos: 389_000)

      expect([resultado.situacao, apolices.count]).to eq(['nova', 1])
      expect([de_fora.reload.valor_centavos, de_fora.eventos.count]).to eq([100, 0])
    end
  end

  describe 'a mesma apólice de novo' do
    let!(:primeira) { guardar.apolice }

    it 'sem nada diferente, não cria outra nem escreve na história' do
      resultado = guardar

      expect([resultado.situacao, resultado.apolice, apolices.count]).to eq(['igual', primeira, 1])
      expect(passos(primeira)).to eq(%w[chegou_planilha])
    end

    it 'com o valor e o bem mudados, atualiza e deixa na história o antes e o depois, na forma do banco' do
      resultado = guardar(valor_centavos: 389_000, bem: 'Carro Exemplo 2024')

      expect([resultado.situacao, resultado.apolice, apolices.count]).to eq(['atualizada', primeira, 1])
      expect(guardado(primeira)).to eq(dados.merge(valor_centavos: 389_000, bem: 'Carro Exemplo 2024'))
      expect(passos(primeira)).to eq(%w[chegou_planilha chegou_de_novo])
      expect(ultimas_mudancas(primeira)).to eq(
        [{ 'campo' => 'valor', 'antes' => 341_000, 'depois' => 389_000 },
         { 'campo' => 'bem', 'antes' => 'Carro Exemplo 2022', 'depois' => 'Carro Exemplo 2024' }]
      )
    end

    it 'com o fim da vigência corrigido na origem, atualiza a mesma apólice em vez de criar outra' do
      resultado = guardar(fim_vigencia: '2027-04-10')

      expect([resultado.situacao, apolices.count, primeira.reload.fim_vigencia]).to eq(['atualizada', 1, Date.new(2027, 4, 10)])
      expect(ultimas_mudancas(primeira)).to eq([{ 'campo' => 'termina', 'antes' => '2027-03-10', 'depois' => '2027-04-10' }])
    end

    it 'o tipo que muda leva junto o ramo como veio' do
      guardar(tipo: 'empresarial', ramo_original: 'Frota')

      expect(primeira.reload.slice(:tipo, :ramo_original).values).to eq(%w[empresarial Frota])
      expect(ultimas_mudancas(primeira)).to eq([{ 'campo' => 'tipo', 'antes' => 'auto', 'depois' => 'empresarial' }])
    end

    it 'o dado que não veio não apaga o guardado, e o tipo "outro" não desfaz o tipo decidido' do
      resultado = guardar(inicio_vigencia: nil, valor_centavos: nil, bem: nil, tipo: 'outro', ramo_original: 'Diversos')

      expect(resultado.situacao).to eq('igual')
      expect(guardado(primeira)).to eq(dados)
      expect(passos(primeira)).to eq(%w[chegou_planilha])
    end

    it 'o campo corrigido à mão não muda; os outros mudam' do
      primeira.update!(valor_centavos: 400_000, corrigido_a_mao: ['valor'])

      so_o_corrigido = guardar(valor_centavos: 389_000)
      com_outro_campo = guardar(valor_centavos: 389_000, bem: 'Carro Exemplo 2024')

      expect([so_o_corrigido.situacao, com_outro_campo.situacao]).to eq(%w[igual atualizada])
      expect(primeira.reload.slice(:valor_centavos, :bem).values).to eq([400_000, 'Carro Exemplo 2024'])
      expect(ultimas_mudancas(primeira).pluck('campo')).to eq(%w[bem])
    end

    it 'continua da pessoa que tinha, e o cancelado continua cancelado' do
      primeira.update!(cancelado_em: Time.current)

      guardar(contato: create(:contact, account: account), valor_centavos: 389_000)

      expect([primeira.reload.contact, primeira.cancelado_em.present?, primeira.valor_centavos]).to eq([pessoa, true, 389_000])
    end
  end

  describe 'a renovação que mantém o número' do
    let!(:anterior) { guardar.apolice }
    let(:renovada) { { inicio_vigencia: termina, fim_vigencia: termina + 1.year, valor_centavos: 389_000 } }

    it 'começa quando a anterior termina: nasce ao lado dela, e a anterior fica como estava' do
      resultado = guardar(**renovada)

      expect([resultado.situacao, apolices.count]).to eq(['nova', 2])
      expect(guardado(anterior)).to eq(dados)
      expect([passos(anterior), passos(resultado.apolice)]).to eq([%w[chegou_planilha], %w[chegou_planilha]])
    end

    it 'com os dois termos guardados, o que chega de novo atualiza o termo dele' do
      nova = guardar(**renovada).apolice

      guardar(bem: 'Carro Exemplo 2023')
      guardar(inicio_vigencia: nil, fim_vigencia: termina + 13.months, valor_centavos: 395_000)

      expect(apolices.count).to eq(2)
      expect([anterior.reload.bem, anterior.fim_vigencia, anterior.valor_centavos]).to eq(['Carro Exemplo 2023', termina, 341_000])
      expect([nova.reload.fim_vigencia, nova.valor_centavos]).to eq([termina + 13.months, 395_000])
    end
  end

  describe 'a precedência das fontes (conector > PDF > planilha)' do
    it 'a fonte mais fraca só preenche o que está vazio, e a origem não muda' do
      do_pdf = guardar(origem: 'pdf', bem: nil).apolice

      resultado = guardar(valor_centavos: 389_000, fim_vigencia: termina + 1.month)

      expect(resultado.situacao).to eq('atualizada')
      expect(guardado(do_pdf)).to eq(dados)
      expect([do_pdf.origem, passos(do_pdf)]).to eq(['pdf', %w[pdf_anexado chegou_de_novo]])
      expect(ultimas_mudancas(do_pdf)).to eq([{ 'campo' => 'bem', 'antes' => nil, 'depois' => 'Carro Exemplo 2022' }])
    end

    it 'a fonte mais forte atualiza e passa a ser a origem; depois dela a mais fraca não desfaz' do
      da_planilha = guardar.apolice

      resultado = guardar(origem: 'conector', valor_centavos: 389_000)
      guardar(valor_centavos: 341_000)

      expect(resultado.situacao).to eq('atualizada')
      expect([da_planilha.reload.valor_centavos, da_planilha.origem]).to eq([389_000, 'conector'])
      expect(passos(da_planilha)).to eq(%w[chegou_planilha chegou_de_novo])
    end

    it 'a fonte mais forte que traz o mesmo passa a ser a origem, sem escrever na história' do
      da_planilha = guardar.apolice

      resultado = guardar(origem: 'pdf')

      expect([resultado.situacao, da_planilha.reload.origem, passos(da_planilha)]).to eq(['igual', 'pdf', %w[chegou_planilha]])
    end

    it 'a apólice feita à mão não é mexida por fonte nenhuma, só completada' do
      a_mao = guardar(origem: 'manual', bem: nil).apolice

      guardar(origem: 'conector', valor_centavos: 389_000, bem: 'Carro Exemplo 2024')

      expect([a_mao.reload.valor_centavos, a_mao.bem, a_mao.origem]).to eq([341_000, 'Carro Exemplo 2024', 'manual'])
    end
  end

  describe 'o que o gravador recusa' do
    it 'ao ser criado: a origem que não existe e a fonte sem primeiro passo da história' do
      expect { described_class.new(account, origem: 'email') }.to raise_error(ArgumentError, 'origem')
      expect { described_class.new(account, origem: 'pdf') }.to raise_error(ArgumentError, 'chegada')
      expect { described_class.new(account, origem: 'pdf', chegada: 'inventado') }.to raise_error(ArgumentError, 'chegada')
      expect(described_class.new(account, origem: 'planilha')).to be_a(described_class)
    end

    it 'os dados que o model da apólice recusa, sem gravar nada' do
      de_fora = create(:contact, account: create(:account))
      recusados = [{ tipo: 'moto' }, { fim_vigencia: nil }, { seguradora: nil }, { fim_vigencia: comeca - 1.day }, { contato: de_fora }]

      recusados.each { |campos| expect { guardar(**campos) }.to raise_error(ActiveRecord::RecordInvalid) }
      expect { guardar(fim_vigencia: '10/03/2027') }.to raise_error(Date::Error)
      expect([apolices.count, Carteira::ApoliceEvento.count]).to eq([0, 0])
    end

    it 'a apólice e o primeiro passo da história entram juntos: sem o passo, a apólice não fica' do
      sem_valores = described_class.new(account, origem: 'planilha', valores: nil)

      expect { sem_valores.call(dados, contato: pessoa) }.to raise_error(ActiveRecord::NotNullViolation)
      expect(apolices.count).to eq(0)
    end
  end
end
