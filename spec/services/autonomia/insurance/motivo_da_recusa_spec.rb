require 'rails_helper'

# OS PADRÕES DA REGRA E UM EXEMPLO DE CADA. Cada exemplo de termo de conta e de valor casa o seu padrão; cada
# exemplo de objeto do risco é liberado e só ele nomeia o risco.
module TextosDeContaNoMotivo
  POR_TERMO = {
    'login' => ['faça login novamente', 'sistema deslogado', 'necessário relogar', 'faça o log in', 'faça logoff'],
    'senha' => ['senha vencida', 'password expired'],
    'sessão' => ['sessão encerrada', 'sessoes simultaneas'],
    'token' => ['token inválido'],
    'usuário' => ['usuário sem perfil', 'user locked'],
    'acesso' => ['acesso negado', 'access denied'],
    'permissão' => ['sem permissão', 'permissões insuficientes'],
    'corretor' => ['corretor inativo', 'corretagem acima do limite'],
    'credencial' => ['descredenciado', 'invalid credentials'],
    'autenticação' => ['falha de autenticação', 'authentication failed'],
    'autorização' => ['desautorizado a calcular', 'not authorized'],
    'habilitação' => ['desabilitado', 'inabilitado para emissão', 'ramo não habilitado'],
    'produtor' => ['produtor inativo'],
    'SUSEP' => ['código SUSEP inválido'],
    'cadastro' => ['recadastramento pendente'],
    'comissão' => ['comissão acima do permitido'],
    'certificado' => ['certificado digital vencido', 'certificação pendente'],
    'bloqueio' => ['bloqueio comercial', 'perfil bloqueado', 'user locked'],
    'conta' => ['conta inativa', 'account suspended'],
    'suspensão' => ['conta suspensa', 'account suspended'],
    'agenciamento' => ['código do agenciador inválido'],
    'inadimplência' => ['inadimplência com a seguradora'],
    'chave' => ['chave de integração expirada'],
    'integração' => ['falha na integração'],
    'expiração' => ['prazo expirado', 'password expired'],
    'portal' => ['entre novamente no portal'],
    'licença' => ['licença do multicálculo vencida'],
    'multicálculo' => ['uso indevido do multicálculo'],
    'operador' => ['operador joao.silva'],
    'CPF' => ['CPF do operador divergente'],
    'e-mail' => ['contato@exemplo.test', 'e-mail não confirmado', 'e mail não confirmado'],
    'link' => ['veja https://exemplo.test/ajuda', 'veja www.exemplo.test'],
    'redigido' => ['contato do suporte <REDACTED>']
  }.freeze

  POR_VALOR = {
    'reais' => ['valor em reais acima do permitido'], 'mil' => ['veículo acima de trezentos mil'],
    'milhão' => ['veículo acima de um milhão', 'acima de dois milhões'], 'bilhão' => ['veículo acima de um bilhão'],
    'milhar' => ['dez milhares'], 'moeda' => ['franquia de sessenta dólares', 'dez euros'],
    'centena por extenso' => ['prêmio mínimo de oitocentos', 'parcela mínima de cem'],
    'dezena por extenso' => ['prêmio mínimo de noventa', 'oitenta e cinco'],
    'unidade por extenso' => ['oitenta e cinco', 'dois anos']
  }.freeze

  POR_OBJETO = {
    'veículo' => 'Veículo sem aceitação.', 'carro' => 'Carro sem aceitação.', 'moto' => 'Moto sem aceitação.',
    'caminhão' => 'Caminhão sem aceitação.', 'ônibus' => 'Ônibus sem aceitação.',
    'utilitário' => 'Utilitário sem aceitação.', 'auto' => 'Seguro auto sem aceitação.',
    'acessório' => 'Acessórios fora da política de aceitação.', 'modelo' => 'Modelo sem aceitação.',
    'ano' => 'Ano fora da política de aceitação.', 'categoria' => 'Categoria sem aceitação.',
    'tarifa' => 'Tarifa sem aceitação.', 'condutor' => 'Condutor fora da política de aceitação.',
    'motorista' => 'Motorista fora da política de aceitação.', 'região' => 'Região sem aceitação.',
    'circulação' => 'Circulação sem aceitação.', 'CEP' => 'CEP sem aceitação.',
    'logradouro' => 'Logradouro fora da política de aceitação.', 'pernoite' => 'Pernoite sem aceitação.',
    'garagem' => 'Garagem fora da política de aceitação.', 'uso' => 'Tipo de uso sem aceitação.',
    'carga' => 'Carga sem aceitação.', 'idade' => 'Idade acima da aceita.',
    'segurado' => 'Restrição técnica para o Segurado', 'risco' => 'Risco sem aceitação nesta seguradora.',
    'cenário' => 'Cenário sem aceitação.', 'cobertura' => 'Cobertura sem aceitação.',
    'blindagem' => 'Blindagem fora da política de aceitação.', 'rastreador' => 'Rastreador exigido para aceitação.',
    'chassi' => 'Chassi remarcado sem aceitação.', 'FIPE' => 'FIPE fora da política de aceitação.',
    'sinistro' => 'Sinistros fora da política de aceitação.', 'bônus' => 'Bônus sem aceitação.',
    'vistoria' => 'Vistoria prévia obrigatória.', 'imóvel' => 'Imóvel fora da política de aceitação.',
    'residência' => 'Residência de veraneio sem aceitação.', 'construção' => 'Construção de madeira sem aceitação.',
    'profissão' => 'Profissão sem aceitação.', 'transporte' => 'Transporte de passageiros sem aceitação.',
    'aplicativo' => 'Aplicativo sem aceitação.', 'placa' => 'Placa sem aceitação.',
    'combustível' => 'Combustível GNV sem aceitação.', 'frota' => 'Frota sem aceitação.'
  }.freeze
end

# OS TEXTOS DE FORA DESTE SPEC: o corpus do conector, os das revisões e o custo levantado por elas.
module TextosReaisDoMotivo
  # As entradas `risco` do corpus sanitizado do conector (`autonomia-adapters` `ad4372a597`,
  # `test/fixtures/agger/motivos-de-recusa.sanitized.json`, `textoLimpo`), e o que a regra devolve de cada uma. A
  # décima segunda cola uma linha de risco a um erro de sistema, e é recusada.
  RISCO_DO_CORPUS = {
    'Risco sem aceitação para este cenário nesta seguradora.' => 'Risco sem aceitação para este cenário nesta seguradora.',
    'Não temos um seguro disponível para este veículo. Gostaria de fazer uma nova cotação para outro carro?' =>
      'Não temos um seguro disponível para este veículo. Gostaria de fazer uma nova cotação para outro carro?',
    'Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida' =>
      'Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida',
    'Aceitacao Restrita, cobertura auto nao permitida para este modelo.' =>
      'Aceitacao Restrita, cobertura auto nao permitida para este modelo.',
    'O veículo não possui aceitação para a categoria tarifária informada.' =>
      'O veículo não possui aceitação para a categoria tarifária informada.',
    'Após análise dos dados do veículo, região de circulação e critérios internos de aceitação, estamos declinando o risco ' \
    'deste orçamento.' =>
      'Após análise dos dados do veículo, região de circulação e critérios internos de aceitação, estamos declinando o risco ' \
      'deste orçamento.',
    '400 - Restrição técnica para o Segurado' => 'Restrição técnica para o Segurado',
    'Tipo de veículo não aceito.' => 'Tipo de veículo não aceito.',
    '[2005] - -Contratação não permitida - Ano Modelo do Veículo' => 'Contratação não permitida - Ano Modelo do Veículo',
    'Moto de ano/modelo sem aceitação - RP' => 'Moto de ano/modelo sem aceitação - RP',
    '[2159] - -Contratação não permitida - Categoria do Veículo' => 'Contratação não permitida - Categoria do Veículo',
    'UC00 - Risco fora das políticas de aceitação As Necessidades do Cliente, não foram salvas com sucesso, selecione nov' => nil,
    'Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP Veículo sem aceitação - RP' =>
      'Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP Veículo sem aceitação - RP'
  }.freeze

  # As outras 26 entradas do mesmo corpus, com o `kind` que o conector deu. Nenhuma passaria nem como `risco`.
  OUTROS_DO_CORPUS = {
    'O sistema de cálculo está indisponível, tente novamente em alguns instantes.' => 'passageiro',
    'Serviço indisponível, tente novamente mais tarde' => 'passageiro',
    'Houve uma instabilidade ao realizar o cálculo nesta seguradora, tente novamente em breve.' => 'passageiro',
    'Usuário não possui acesso a funcionalidade. Por favor, verifique suas permissões no site da seguradora.' => 'credencial',
    'Login ou senha incorreta. Confira suas credenciais de acesso.' => 'credencial',
    'Erro ao processar o cálculo do prêmio' => 'outro',
    'Desmoronamento - Para contratação desta cobertura é necessário enviar para Análise Técnica.' => 'outro',
    'O Nome informado não corresponde ao CPF cadastrado. Por favor, verifique e tente novamente.' => 'outro',
    'Corretor não encontrado. Por favor, selecione um corretor válido no cadastro da seguradora.' => 'credencial',
    'LMI COB RC OBRIGATORIA PARA DANO MORAL' => 'outro',
    'Houve um erro ao realizar este cálculo.' => 'outro',
    'Não foi possível recuperar o valor dessa cotação. Por favor, tente novamente mais tarde.' => 'passageiro',
    'Profissão deve ser especificada corretamente para que o cálculo prossiga.' => 'outro',
    'Ocorreu uma divergencia entre a comissao informada e a comissao permitida.' => 'credencial',
    'Nenhum produto com seguro disponível para exibição.' => 'outro',
    'Só é permitida a contratação de [Faróis, Lanternas e Retrovisor] para veículos até 20 anos.' => 'outro',
    'A cobertura "Impacto Veículos" não está disponível para esta cotação.' => 'outro',
    'Ocorreu um erro ao calcular. Revise o formulario de calculo e tente novamente.' => 'outro',
    'Origem da viagem deve ser especificada corretamente' => 'outro',
    'Cálculo sem prêmio.' => 'outro',
    'O valor informado de R$ 10.000,00 para a cobertura Roubo Residencial Condominos, Cobertura é invalido. O mínimo aceito' =>
      'outro',
    "Necessário contratar primeiro uma das coberturas: '000510026 - Responsabilidade Civil Operacoes', '000510304 - Resp Civ" =>
      'outro',
    '[165456] - Contratação da Cobertura Desmoronamento para o GRUPO ESCRITORIOS ATIVIDADE DEMAIS ESCRITÓRIOS está fora da p' =>
      'outro',
    'Para a Cobertura Responsabilidade Civil Empregador, Obrigat ria a contrata o da Cobertura Responsabilidade Civil Est' =>
      'outro',
    'A cobertura de INCENDIO / QUEDA DE RAIO / EXPLOSAO / IMPLOSAO ACIDENTAL / FUMACA / QUEDA DE AERONAVES não pode ser cont' =>
      'outro',
    'O valor do capital segurado deve ser entre R$100,00 e R$1.000,00, limitado a 250 vezes o capital segurado da cobertura' =>
      'outro'
  }.freeze

  # O CUSTO, DECLARADO: textos plausíveis de risco que a regra recusa (a Lia diz só que a seguradora não fez
  # proposta), levantados pelas revisões da fatia 2.
  CUSTO = [
    'Condutor com menos de 2 anos de habilitação. Declinando cálculo.',
    'Tempo de habilitação do condutor inferior ao exigido pela aceitação.',
    'CEP de pernoite não cadastrado para aceitação.', 'Veículo bloqueado para aceitação nesta seguradora.',
    'Veículo ano 2005 fora da política de aceitação.', 'CEP 04567-000 fora da área de aceitação.',
    'Modelo não autorizado para uso em aplicativo. Declinando cálculo.',
    'Veículo sem permissão de circulação na região. Declinando cálculo.', 'Código FIPE 0012345 sem aceitação.',
    'Veículo com suspensão rebaixada sem aceitação.', 'Recusado por conta da região de circulação.',
    'Veículo zero km sem aceitação.', 'Contratação não permitida.', 'Restrição técnica.',
    'Declinando o risco: histórico de sinistros do segurado.', 'Placa de outro estado sem aceitação.'
  ].freeze
end

# OS TEXTOS DAS REVISÕES: os do conector, que saíram com a classe errada, e os das revisões da fatia 2, que saem
# `risco` do classificador real do conector falando da conta da corretora, de dado pessoal ou de valor.
module TextosDasRevisoesDoMotivo
  DAS_REVISOES = [
    'Senha expirou. Declinando cálculo.', 'Sistema indisponível: sessão expirada, faça login novamente.',
    'Usuário fulano@corretora.com.br bloqueado.', 'Produtor não credenciado para este produto. Declinando cálculo.',
    'Não autorizado a calcular este produto. Declinando cálculo.', 'Código SUSEP inválido. Declinando cálculo.',
    'Sistema deslogado. Declinando cálculo.', 'Corretagem acima do limite do produto. Declinando cálculo.',
    'Prêmio mínimo de 1.500,00 não atingido. Declinando cálculo.', 'Faça o log in novamente. Declinando cálculo.',
    'Valor do veículo acima de 300 mil reais. Declinando cálculo.', 'Descredenciado para este produto. Declinando cálculo.',
    'Recadastramento pendente nesta seguradora. Declinando cálculo.', 'Conta suspensa nesta seguradora. Declinando cálculo.',
    'Chave de integração expirada. Declinando cálculo.', 'Licença do multicálculo vencida. Declinando cálculo.',
    'Entre novamente no portal da seguradora. Declinando cálculo.', 'Vínculo com a sucursal inexistente. Declinando cálculo.',
    'Contato do suporte: <REDACTED>. Declinando cálculo.', 'Prêmio mínimo de 800 não atingido. Declinando cálculo.',
    'Valor do veículo acima de trezentos mil. Declinando cálculo.', 'Importância segurada acima de 2 milhões. Declinando cálculo.',
    # Rodada 3: conta colada a uma linha de risco, palavra de risco com outro sentido, inglês, dado pessoal, número.
    'Risco fora das políticas de aceitação Licença do multicálculo vencida.',
    'UC00 - Risco fora das políticas de aceitação Código de verificação inválido.',
    'Veículo sem aceitação - RP Pró-labore acima do permitido.', 'Declinando o risco. Convênio da filial inativo.',
    'Uso indevido do multicálculo detectado. Declinando cálculo.', 'Versão do aplicativo desatualizada. Declinando cálculo.',
    'Veículo sem aceitação por conta inativa nesta seguradora.', 'Veículo sem aceitação: access denied.',
    'Veículo sem aceitação: invalid credentials.', 'Veículo sem aceitação: operador joao.silva.',
    'Veículo sem aceitação: CPF do operador divergente.', 'Veículo sem aceitação: e mail não confirmado.',
    'Prêmio mínimo de noventa não atingido para o veículo.', 'Veículo acima de um bilhão.',
    'Franquia de sessenta dólares para o veículo.', 'Veículo sem aceitação, prêmio mínimo de ８００.',
    '٨٠٠ - Veículo sem aceitação.', 'Veículo sem aceitação пароль.', 'Senha123 - Veículo sem aceitação.',
    # Rodada 4: conta escrita só com palavras que estavam no vocabulário, e letra latina que não se translitera.
    'Limite máximo de cotação de seguro auto nesta seguradora. Declinando cálculo.',
    'Veículo sem aceitação: sua tabela não é mais aceita.',
    'Nova análise dos seus dados obrigatória para cotação do veículo. Declinando cálculo.',
    'Produto auto restrito para o seu tipo de contratação. Declinando cálculo.',
    'Cotação do veículo não permitida: seus dados internos estão restritos nesta seguradora. Declinando cálculo.',
    'Veículo sem aceitação: seu produto está indisponível nesta seguradora.',
    'Risco sem aceitação: sua classe não é mais permitida nesta seguradora.',
    'Restrição técnica: seu cálculo de seguro auto não é mais permitido nesta seguradora.',
    'Veículo sem aceitação: seu limite de cotação já foi realizado.',
    'Aceitação restrita: seus dados não são aceitos para cotação de seguro auto.',
    'Veículo sem aceitação: seu histórico de cotação nesta seguradora.',
    'Veículo sem aceitação: seu local de contratação não é permitido.',
    'Veículo sem aceitação: sua área de contratação é restrita.',
    'Veículo sem aceitação: seu estado de contratação é restrito.',
    'Veículo sem aceitação: sua atividade está restrita nesta seguradora.',
    'Aceitação restrita: dados do segurado recusados.',
    'Veículo sem aceitação: ꜱᴇɴʜᴀ ᴇˣᴘɪʀᴏᴜ.', 'Veículo sem aceitação: ʟᴏɢɪɴ ᴅᴀ ᴄᴏʀʀᴇᴛᴏʀᴀ ʙʟᴏɋᴜᴇᴀᴅᴏ.',
    'Veículo sem aceitação: ＳＥＮＨＡ ＥＸＰＩＲＯＵ.', 'Veículo sem aceitação acima de Ⅹ Ⅿ.'
  ].freeze
end

# A REGRA DO MOTIVO (fatia 2 do #420, registrada na issue em 13/09/2026): o texto do portal só orienta a fala da Lia
# quando o `kind` é `risco` e, sem o código do começo, o texto só tem letras latinas e pontuação, só palavras do
# vocabulário, nenhum termo de conta nem valor, e nomeia o objeto do risco. Em qualquer outro caso, nil. Os textos
# são sintéticos, na forma das mensagens de recusa do portal, menos os do corpus do conector.
RSpec.describe Autonomia::Insurance::MotivoDaRecusa do
  def permitido(texto, kind: 'risco')
    described_class.permitido('kind' => kind, 'text' => texto)
  end

  def alvo(texto)
    ActiveSupport::Inflector.transliterate(texto).downcase
  end

  describe 'o corpus do conector' do
    TextosReaisDoMotivo::RISCO_DO_CORPUS.each do |texto, devolvido|
      it "o risco «#{texto}» devolve #{devolvido.inspect}" do
        expect(permitido(texto)).to eq(devolvido)
      end
    end

    TextosReaisDoMotivo::OUTROS_DO_CORPUS.each do |texto, kind|
      it "«#{texto}» (#{kind}) não passa, nem se viesse como risco" do
        expect(permitido(texto, kind: kind)).to be_nil
        expect(permitido(texto)).to be_nil
      end
    end
  end

  describe 'o que libera' do
    ['Catálogo do veículo sem aceitação.', 'Veículo de permissionário sem aceitação.',
     'Veículo não homologado para aceitação.', 'Veículo sem aceitação nesta seguradora.',
     'Declinando o risco deste orçamento.'].each do |texto|
      it "libera «#{texto}»" do
        expect(permitido(texto)).to eq(texto)
      end
    end

    it 'devolve o texto aparado' do
      expect(permitido("  Risco sem aceitação.\n")).to eq('Risco sem aceitação.')
    end
  end

  describe 'o código do portal no começo' do
    { '400 - Veículo sem aceitação' => 'Veículo sem aceitação', '[2005] - -Veículo sem aceitação' => 'Veículo sem aceitação',
      'UC00 - Veículo sem aceitação' => 'Veículo sem aceitação',
      '2005 - Contratação não permitida - Ano Modelo do Veículo' => 'Contratação não permitida - Ano Modelo do Veículo' }
      .each do |texto, devolvido|
        it "sai de «#{texto}»" do
          expect(permitido(texto)).to eq(devolvido)
        end
      end

    ['Ano 2005 - modelo sem aceitação', 'Veículo sem aceitação [2005]', 'Veículo 400 - sem aceitação',
     '400 Veículo sem aceitação', 'Senha123 - Veículo sem aceitação'].each do |texto|
      it "fora do começo, ou sem hífen, ou com mais de três letras, o número fica e recusa «#{texto}»" do
        expect(permitido(texto)).to be_nil
      end
    end
  end

  describe 'o que recusa pelos caracteres e pelo vocabulário' do
    { 'dígito de outro alfabeto' => 'Veículo sem aceitação, prêmio mínimo de ８００.',
      'dígito arábico no código' => '٨٠٠ - Veículo sem aceitação.', 'letra de outro alfabeto' => 'Veículo sem aceitação пароль.',
      'símbolo de moeda' => 'Veículo sem aceitação acima de R$.', 'arroba' => 'Veículo sem aceitação @seguradora.',
      'palavra fora do vocabulário' => 'Veículo sem aceitação, detectado.' }.each do |caso, texto|
      it "#{caso}: recusa «#{texto}»" do
        expect(permitido(texto)).to be_nil
      end
    end

    it 'o controle: o mesmo texto sem o que recusa é liberado' do
      expect(permitido('Veículo sem aceitação.')).to eq('Veículo sem aceitação.')
    end
  end

  describe 'o kind decide antes do texto' do
    %w[passageiro credencial outro].each do |kind|
      it "recusa o kind #{kind} com um texto que o risco liberaria" do
        expect(permitido('Risco sem aceitação para este cenário.', kind: kind)).to be_nil
      end
    end

    it 'recusa motivo sem kind' do
      expect(described_class.permitido('text' => 'Risco sem aceitação.')).to be_nil
    end
  end

  describe 'os textos das revisões, mesmo classificados como risco' do
    TextosDasRevisoesDoMotivo::DAS_REVISOES.each do |texto|
      it "recusa «#{texto}»" do
        expect(permitido(texto)).to be_nil
      end
    end
  end

  describe 'o custo, declarado: motivos de risco que a regra recusa' do
    TextosReaisDoMotivo::CUSTO.each do |texto|
      it "recusa «#{texto}»" do
        expect(permitido(texto)).to be_nil
      end
    end
  end

  # O VOCABULÁRIO É A LISTA DE LIBERAÇÃO, e os padrões de conta e de valor são a guarda dela: nenhuma palavra do
  # vocabulário pode casar um deles.
  describe 'o vocabulário' do
    let(:padroes) { described_class::TERMOS_DE_CONTA.merge(described_class::VALORES) }

    it 'nenhuma palavra casa um termo de conta ou de valor' do
      casadas = described_class::VOCABULARIO.select { |palavra| padroes.values.any? { |padrao| palavra.match?(padrao) } }

      expect(casadas).to be_empty
    end

    it 'só tem palavras sem acento, em minúsculas' do
      expect(described_class::VOCABULARIO.grep_v(/\A[a-z]+\z/)).to be_empty
    end

    TextosDeContaNoMotivo::POR_TERMO.merge(TextosDeContaNoMotivo::POR_VALOR).each do |padrao, exemplos|
      exemplos.each do |exemplo|
        it "#{padrao}: o padrão casa «#{exemplo}», e o texto com ele é recusado" do
          expect(alvo(exemplo)).to match(described_class::TERMOS_DE_CONTA.merge(described_class::VALORES).fetch(padrao))
          expect(permitido("Veículo sem aceitação, #{exemplo}.")).to be_nil
        end
      end
    end

    it 'todo padrão da lista tem exemplo' do
      expect(TextosDeContaNoMotivo::POR_TERMO.keys).to match_array(described_class::TERMOS_DE_CONTA.keys)
      expect(TextosDeContaNoMotivo::POR_VALOR.keys).to match_array(described_class::VALORES.keys)
    end
  end

  describe 'cada objeto do risco' do
    TextosDeContaNoMotivo::POR_OBJETO.each do |objeto, texto|
      it "#{objeto}: libera «#{texto}»" do
        expect(permitido(texto)).to eq(texto)
      end
    end

    it 'sem objeto do risco, o texto só com palavras do vocabulário é recusado' do
      expect(permitido('Declinando cálculo.')).to be_nil
      expect(permitido('Contratação não permitida nesta seguradora.')).to be_nil
    end

    it 'todo objeto da lista tem exemplo' do
      expect(TextosDeContaNoMotivo::POR_OBJETO.keys).to match_array(described_class::OBJETOS_DO_RISCO.keys)
    end

    it 'todo objeto tem um exemplo em que só ele nomeia o risco' do
      sem_exemplo_proprio = described_class::OBJETOS_DO_RISCO.keys.reject do |nome|
        texto = TextosDeContaNoMotivo::POR_OBJETO.fetch(nome)
        described_class::OBJETOS_DO_RISCO.select { |_, padrao| alvo(texto).match?(padrao) }.keys == [nome]
      end

      expect(sem_exemplo_proprio).to be_empty
    end
  end

  describe 'o que não é texto do conector' do
    it 'recusa motivo nil, motivo que não é Hash, texto nil, texto que não é String, vazio e acima do teto' do
      expect(described_class.permitido(nil)).to be_nil
      expect(described_class.permitido('Risco sem aceitação.')).to be_nil
      expect(described_class.permitido('kind' => 'risco', 'text' => nil)).to be_nil
      expect(described_class.permitido('kind' => 'risco', 'text' => { 'a' => 1 })).to be_nil
      expect(permitido('   ')).to be_nil
      expect(permitido("Risco#{' o' * described_class::TETO_DO_TEXTO}")).to be_nil
    end

    it 'libera o texto exatamente no teto' do
      texto = "Risco#{' o' * ((described_class::TETO_DO_TEXTO - 5) / 2)}"
      texto += '.' * (described_class::TETO_DO_TEXTO - texto.length)

      expect(texto.length).to eq(described_class::TETO_DO_TEXTO)
      expect(permitido(texto)).to eq(texto)
    end
  end
end
