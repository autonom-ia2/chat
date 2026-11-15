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

  def recusar_com(codigo)
    raise_error(CustomExceptions::CarteiraRecusa) { |recusa| expect(recusa.codigo).to eq(codigo) }
  end

  # A apólice, a história dela e as outras da conta, para provar que uma recusa não mexeu em nada.
  def retrato
    [apolices.order(:id).map(&:attributes), Carteira::ApoliceEvento.count]
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

    it 'com o começo da vigência corrigido na origem (mesmo fim), atualiza a mesma apólice' do
      resultado = guardar(inicio_vigencia: comeca + 22.days)

      expect([resultado.situacao, apolices.count, primeira.reload.inicio_vigencia]).to eq(['atualizada', 1, comeca + 22.days])
      expect(ultimas_mudancas(primeira)).to eq([{ 'campo' => 'comeca', 'antes' => '2026-03-10', 'depois' => '2026-04-01' }])
    end

    it 'o tipo que muda leva junto o ramo como veio' do
      guardar(tipo: 'empresarial', ramo_original: 'Frota')

      expect(primeira.reload.slice(:tipo, :ramo_original).values).to eq(%w[empresarial Frota])
      expect(ultimas_mudancas(primeira)).to eq([{ 'campo' => 'tipo', 'antes' => 'auto', 'depois' => 'empresarial' }])
    end

    it 'o tipo que muda sem o ramo (nil é "não veio") não apaga o ramo guardado' do
      guardar(tipo: 'empresarial', ramo_original: nil)

      expect(primeira.reload.slice(:tipo, :ramo_original).values).to eq(%w[empresarial Automóvel])
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

    it 'de outra pessoa é recusada, sem mesclar e sem tocar em nada' do
      antes = retrato

      expect { guardar(contato: create(:contact, account: account), valor_centavos: 389_000) }.to recusar_com('apolice_de_outra_pessoa')
      expect(retrato).to eq(antes)
    end

    it 'cancelada continua cancelada e não é alterada por fonte nenhuma, nem pela mão: quem chamou fica sabendo' do
      primeira.update!(cancelado_em: Time.current)
      antes = retrato

      %w[planilha pdf conector manual].each do |origem|
        resultado = guardar(valor_centavos: 389_000, origem: origem)

        expect([resultado.situacao, resultado.apolice]).to eq(['cancelada', primeira]), origem
      end
      expect(retrato).to eq(antes)
    end

    it 'cancelada de outra pessoa é recusada como a de outra pessoa' do
      primeira.update!(cancelado_em: Time.current)

      expect { guardar(contato: create(:contact, account: account)) }.to recusar_com('apolice_de_outra_pessoa')
    end

    it 'e a história entram juntas: se o passo não grava, a apólice fica como estava' do
      com_passo_que_nao_grava = described_class.new(account, origem: 'planilha', valores: { arquivo: "carteira\u0000.csv" })

      expect { com_passo_que_nao_grava.call(dados.merge(valor_centavos: 389_000), contato: pessoa) }.to raise_error(ActiveRecord::StatementInvalid)
      expect([primeira.reload.valor_centavos, passos(primeira)]).to eq([341_000, %w[chegou_planilha]])
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

    it 'antecipada (começa antes de a anterior terminar, com começo e fim diferentes) também nasce ao lado: nunca sobrescreve' do
      resultado = guardar(inicio_vigencia: termina - 37.days, fim_vigencia: termina + 328.days, valor_centavos: 389_000)

      expect([resultado.situacao, apolices.count]).to eq(['nova', 2])
      expect(guardado(anterior)).to eq(dados)
    end

    it 'com os dois termos guardados, o que chega de novo atualiza o termo dele' do
      nova = guardar(**renovada).apolice

      guardar(bem: 'Carro Exemplo 2023')
      guardar(**renovada, fim_vigencia: termina + 13.months, valor_centavos: 395_000)

      expect(apolices.count).to eq(2)
      expect([anterior.reload.bem, anterior.fim_vigencia, anterior.valor_centavos]).to eq(['Carro Exemplo 2023', termina, 341_000])
      expect([nova.reload.fim_vigencia, nova.valor_centavos]).to eq([termina + 13.months, 395_000])
    end

    it 'com os dois termos guardados, o fim corrigido do primeiro atualiza o primeiro: só ele tem o mesmo começo' do
      nova = guardar(**renovada).apolice

      resultado = guardar(fim_vigencia: termina + 9.months)

      expect([resultado.situacao, resultado.apolice, apolices.count]).to eq(['atualizada', anterior, 2])
      expect([anterior.reload.fim_vigencia, guardado(nova)]).to eq([termina + 9.months, dados.merge(renovada)])
    end

    it 'o que chega com o começo de um termo e o fim do outro é recusado, sem desempate e sem tentar de novo' do
      guardar(**renovada)
      antes = retrato
      allow(Carteira::Termo).to receive(:escolher).and_call_original

      expect { guardar(fim_vigencia: renovada[:fim_vigencia], valor_centavos: 395_000) }.to recusar_com('termo_ambiguo')
      expect(retrato).to eq(antes)
      expect(Carteira::Termo).to have_received(:escolher).once
    end

    it 'a colisão no índice único ao ATUALIZAR não é corrida, é termo errado: recusa com o código, sem tentar de novo' do
      nova = guardar(**renovada).apolice
      antes = retrato
      # Como se a escolha do termo tivesse deixado passar: atualizar o fim do primeiro bate no fim do segundo.
      allow(Carteira::Termo).to receive(:escolher).and_return(anterior)

      expect { guardar(fim_vigencia: nova.fim_vigencia) }.to raise_error(CustomExceptions::CarteiraRecusa) { |recusa|
        expect([recusa.codigo, recusa.message, recusa.cause]).to eq(['termo_ambiguo', 'termo_ambiguo', nil])
      }
      expect(retrato).to eq(antes)
      expect(Carteira::Termo).to have_received(:escolher).once
    end

    it 'com dois termos de mesmo começo guardados e nenhum igual em tudo, recusa em vez de adivinhar' do
      criar_apolice(pessoa, **dados.slice(:seguradora, :numero, :inicio_vigencia), fim_vigencia: termina + 3.months)
      antes = retrato

      expect { guardar(fim_vigencia: termina + 6.months) }.to recusar_com('termo_ambiguo')
      expect(retrato).to eq(antes)
      expect(guardar(bem: 'Carro Exemplo 2023').apolice).to eq(anterior)
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

    it 'a fonte mais forte que traz o mesmo passa a ser a origem, e a história ganha o passo com a origem de antes e a de agora' do
      da_planilha = guardar.apolice

      resultado = guardar(origem: 'pdf')
      passo = da_planilha.eventos.order(:id).last

      expect([resultado.situacao, da_planilha.reload.origem, passos(da_planilha)]).to eq(['igual', 'pdf', %w[chegou_planilha chegou_de_novo_pdf]])
      expect(passo.mudancas).to be_nil
      expect(passo.valores).to eq('arquivo' => 'carteira-exemplo.csv', 'origem_antes' => 'planilha', 'origem_depois' => 'pdf')
      expect { guardar(origem: 'pdf') }.not_to(change { passos(da_planilha) })
    end

    it 'a apólice feita à mão não é mexida por fonte nenhuma, só completada' do
      a_mao = guardar(origem: 'manual', bem: nil).apolice

      guardar(origem: 'conector', valor_centavos: 389_000, bem: 'Carro Exemplo 2024')

      expect([a_mao.reload.valor_centavos, a_mao.bem, a_mao.origem]).to eq([341_000, 'Carro Exemplo 2024', 'manual'])
    end

    it 'a origem "manual" só cria: achando a apólice, recusa (quem edita à mão é a gaveta)' do
      da_planilha = guardar.apolice
      antes = retrato

      expect { guardar(origem: 'manual', valor_centavos: 389_000) }.to recusar_com('apolice_repetida')
      expect(retrato).to eq(antes)
      expect(guardar(origem: 'manual', inicio_vigencia: termina, fim_vigencia: termina + 1.year).situacao).to eq('nova')
      expect(da_planilha.reload.origem).to eq('planilha')
    end
  end

  describe 'o que o gravador recusa' do
    it 'ao ser criado: a origem que não existe e a fonte sem primeiro passo da história' do
      expect { described_class.new(account, origem: 'email') }.to raise_error(ArgumentError, 'origem')
      expect { described_class.new(account, origem: 'conector') }.to raise_error(ArgumentError, 'chegada')
      expect { described_class.new(account, origem: 'conector', chegada: 'inventado') }.to raise_error(ArgumentError, 'chegada')
      expect(described_class.new(account, origem: 'planilha')).to be_a(described_class)
      expect(described_class.new(account, origem: 'pdf')).to be_a(described_class)
    end

    it 'ao ser criado: o usuário que não é da conta e a importação de outra conta' do
      outra = create(:account)
      de_fora = create(:user, account: outra)
      importacao_de_fora = create_campaign_import(account: outra, user: de_fora, content: "Nome;Celular\nAna Albuquerino;11987650001\n")

      expect { described_class.new(account, origem: 'planilha', user: de_fora) }.to raise_error(ArgumentError, 'user')
      expect { described_class.new(account, origem: 'planilha', importacao: importacao_de_fora) }.to raise_error(ArgumentError, 'importacao')
    end

    it 'ao ser criado: o que não é a conta e o que não são os valores da história' do
      expect { described_class.new(nil, origem: 'planilha') }.to raise_error(ArgumentError, 'account')
      expect { described_class.new(account.id, origem: 'planilha') }.to raise_error(ArgumentError, 'account')
      expect { described_class.new(account, origem: 'planilha', valores: nil) }.to raise_error(ArgumentError, 'valores')
      expect { described_class.new(account, origem: 'planilha', valores: 'carteira-exemplo.csv') }.to raise_error(ArgumentError, 'valores')
    end

    it 'ao chamar: o que não são os dados, a pessoa e a empresa' do
      empresa_de_mentira = Struct.new(:id).new(1)

      expect { gravador('planilha').call(nil, contato: pessoa) }.to raise_error(ArgumentError, 'dados')
      expect { gravador('planilha').call([dados], contato: pessoa) }.to raise_error(ArgumentError, 'dados')
      expect { gravador('planilha').call(dados, contato: nil) }.to raise_error(ArgumentError, 'contato')
      expect { gravador('planilha').call(dados, contato: pessoa.id) }.to raise_error(ArgumentError, 'contato')
      expect { gravador('planilha').call(dados, contato: pessoa, empresa: empresa_de_mentira) }.to raise_error(ArgumentError, 'empresa')
      expect(apolices.count).to eq(0)
    end

    it 'o dado fora da forma do banco: valor em texto, data que não é data, texto que não é texto' do
      fora_da_forma = [[{ valor_centavos: '341000' }, 'valor_centavos'], [{ valor_centavos: 3410.0 }, 'valor_centavos'],
                       [{ fim_vigencia: '10/03/2027' }, 'fim_vigencia'], [{ inicio_vigencia: Time.current }, 'inicio_vigencia'],
                       [{ tipo: :auto }, 'tipo'], [{ numero: 1234 }, 'numero']]

      fora_da_forma.each { |campos, campo| expect { guardar(**campos) }.to raise_error(ArgumentError, campo) }
      expect(apolices.count).to eq(0)
    end

    it 'o valor em texto não vira "chegou de novo" a cada chegada: é recusado antes de comparar' do
      primeira = guardar.apolice

      expect { guardar(valor_centavos: '341000') }.to raise_error(ArgumentError, 'valor_centavos')
      expect(passos(primeira)).to eq(%w[chegou_planilha])
    end

    it 'a gravação da mesma apólice que chegou ao mesmo tempo: tenta de novo uma vez e atualiza a que entrou' do
      guardada = guardar.apolice
      chamadas = 0
      # A primeira procura não vê a apólice, como na corrida: a criação bate no índice único e a segunda procura acha.
      allow(Carteira::Termo).to receive(:escolher).and_wrap_original do |original, *argumentos|
        (chamadas += 1) == 1 ? nil : original.call(*argumentos)
      end

      resultado = guardar(valor_centavos: 389_000)

      expect([resultado.situacao, resultado.apolice, apolices.count, chamadas]).to eq(['atualizada', guardada, 1, 2])
      expect(guardada.reload.valor_centavos).to eq(389_000)
    end

    it 'se bater de novo no índice único, recusa com o código, sem repassar a mensagem do banco (que traz o número)' do
      guardar
      allow(Carteira::Termo).to receive(:escolher).and_return(nil)

      expect { guardar(valor_centavos: 389_000) }.to raise_error(CustomExceptions::CarteiraRecusa) { |recusa|
        expect([recusa.codigo, recusa.message, recusa.cause]).to eq(['apolice_repetida', 'apolice_repetida', nil])
      }
      expect([apolices.count, apolices.sole.valor_centavos]).to eq([1, 341_000])
    end

    it 'os dados que o model da apólice recusa, sem gravar nada' do
      de_fora = create(:contact, account: create(:account))
      recusados = [{ tipo: 'moto' }, { fim_vigencia: nil }, { seguradora: nil }, { fim_vigencia: comeca - 1.day }, { contato: de_fora }]

      recusados.each { |campos| expect { guardar(**campos) }.to raise_error(ActiveRecord::RecordInvalid) }
      expect([apolices.count, Carteira::ApoliceEvento.count]).to eq([0, 0])
    end

    it 'a apólice e o primeiro passo da história entram juntos: sem o passo, a apólice não fica' do
      com_passo_que_nao_grava = described_class.new(account, origem: 'planilha', valores: { arquivo: "carteira\u0000.csv" })

      expect { com_passo_que_nao_grava.call(dados, contato: pessoa) }.to raise_error(ActiveRecord::StatementInvalid)
      expect(apolices.count).to eq(0)
    end
  end
end
