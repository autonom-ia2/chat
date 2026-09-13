require 'rails_helper'

# UM EXEMPLO POR PADRÃO, com e sem acento. Cada texto nomeia o risco ("o risco") e só tem o termo como motivo
# para ser recusado: sem ele, "Declinando o risco" seria liberado (o exemplo de controle abaixo).
module TextosDeContaNoMotivo
  POR_TERMO = {
    'login' => ['Declinando o risco, faça login novamente.', 'Declinando o risco, faca LOGIN de novo.',
                'Declinando o risco: sistema não logado.', 'Declinando o risco, logue de novo.',
                'Declinando o risco: sistema deslogado.', 'Declinando o risco: necessário relogar.',
                'Declinando o risco: faça o log in novamente.', 'Declinando o risco: faça logoff e entre de novo.'],
    'senha' => ['Declinando o risco: senha vencida.', 'Declinando o risco: senhas divergentes.',
                'Declinando o risco: password errado.'],
    'sessão' => ['Declinando o risco: sessão encerrada.', 'Declinando o risco: sessao encerrada.',
                 'Declinando o risco: sessões simultâneas.'],
    'token' => ['Declinando o risco: token inválido.', 'Declinando o risco: TOKENS vencidos.'],
    'usuário' => ['Declinando o risco: usuário sem perfil.', 'Declinando o risco: usuario sem perfil.'],
    'acesso' => ['Declinando o risco: acesso negado.', 'Declinando o risco: não foi possível acessar.'],
    'permissão' => ['Declinando o risco: sem permissão.', 'Declinando o risco: sem permissao.',
                    'Declinando o risco: permissões insuficientes.'],
    'corretor' => ['Declinando o risco: corretor inativo.', 'Declinando o risco: corretora inativa.',
                   'Declinando o risco: corretagem acima do limite.'],
    'credencial' => ['Declinando o risco: credencial vencida.', 'Declinando o risco: credenciais vencidas.',
                     'Declinando o risco: credenciamento pendente.', 'Declinando o risco: descredenciado.'],
    'autenticação' => ['Declinando o risco: falha de autenticação.', 'Declinando o risco: falha ao reautenticar.'],
    'autorização' => ['Declinando o risco: não autorizado a calcular.', 'Declinando o risco: sem autorização.',
                      'Declinando o risco: desautorizado a calcular.'],
    'habilitação' => ['Declinando o risco: ramo não habilitado.', 'Declinando o risco: desabilitado.',
                      'Declinando o risco: inabilitado para emissão.'],
    'produtor' => ['Declinando o risco: produtor inativo.'],
    'SUSEP' => ['Declinando o risco: código SUSEP inválido.'],
    'cadastro' => ['Declinando o risco: cadastro incompleto.', 'Declinando o risco: recadastramento pendente.'],
    'comissão' => ['Declinando o risco: comissão acima do permitido.', 'Declinando o risco: comissao divergente.'],
    'certificado' => ['Declinando o risco: certificado digital vencido.', 'Declinando o risco: certificação pendente.'],
    'bloqueio' => ['Declinando o risco: perfil bloqueado.', 'Declinando o risco: bloqueio comercial.'],
    'conta' => ['Declinando o risco: conta inativa.', 'Declinando o risco: CONTAS inativas.'],
    'suspensão' => ['Declinando o risco: operação suspensa.', 'Declinando o risco: suspensão comercial.'],
    'agenciamento' => ['Declinando o risco: código do agenciador inválido.'],
    'inadimplência' => ['Declinando o risco: inadimplência com a seguradora.'],
    'chave' => ['Declinando o risco: chave inválida.'],
    'integração' => ['Declinando o risco: falha na integração.'],
    'expiração' => ['Declinando o risco: prazo expirado.', 'Declinando o risco: expirou.'],
    'portal' => ['Declinando o risco: entre novamente no portal.'],
    'e-mail' => ['Declinando o risco: contato@exemplo.test sem retorno.', 'Declinando o risco: e-mail não confirmado.'],
    'link' => ['Declinando o risco: veja https://exemplo.test/ajuda.', 'Declinando o risco: veja www.exemplo.test.'],
    'redigido' => ['Declinando o risco: contato do suporte <REDACTED>.']
  }.freeze

  POR_VALOR = {
    'dígito' => ['Declinando o risco: prêmio mínimo 800 não atingido.', 'Declinando o risco: veículo ano 2005.'],
    'R$' => ['Declinando o risco: valor em R$ acima do permitido.'],
    'reais' => ['Declinando o risco: valor em reais acima do permitido.'],
    'mil' => ['Declinando o risco: veículo acima de noventa mil.'],
    'milhão' => ['Declinando o risco: veículo acima de um milhão.', 'Declinando o risco: acima de dois milhões.'],
    'centena por extenso' => ['Declinando o risco: prêmio mínimo de oitocentos não atingido.',
                              'Declinando o risco: parcela mínima de cem.']
  }.freeze

  # UM EXEMPLO LIBERADO POR OBJETO DO RISCO, em que só ele nomeia o risco.
  POR_OBJETO = {
    'veículo' => 'Veículo sem aceitação.', 'carro' => 'Carro sem aceitação.', 'moto' => 'Moto sem aceitação.',
    'caminhão' => 'Caminhão sem aceitação.', 'ônibus' => 'Ônibus sem aceitação.',
    'utilitário' => 'Utilitário sem aceitação.', 'auto' => 'Produto auto sem aceitação.',
    'acessório' => 'Acessórios fora da política de aceitação.', 'modelo' => 'Modelo sem aceitação.',
    'ano' => 'Ano fora da política de aceitação.', 'categoria' => 'Categoria sem aceitação.',
    'tarifa' => 'Tarifa indisponível para o perfil.', 'condutor' => 'Condutor fora da política de aceitação.',
    'motorista' => 'Motorista fora da política de aceitação.', 'região' => 'Região sem aceitação.',
    'circulação' => 'Área de circulação sem aceitação.', 'CEP' => 'CEP sem aceitação.',
    'logradouro' => 'Logradouro fora da área de aceitação.', 'pernoite' => 'Local de pernoite sem aceitação.',
    'garagem' => 'Garagem fora da política de aceitação.', 'uso' => 'Tipo de uso sem aceitação.',
    'carga' => 'Carga sem aceitação.', 'idade' => 'Idade acima da aceita.',
    'segurado' => 'Restrição técnica para o Segurado', 'risco' => 'Risco sem aceitação nesta seguradora.',
    'cenário' => 'Cenário sem aceitação.', 'cobertura' => 'Cobertura indisponível.',
    'blindagem' => 'Blindagem fora da política de aceitação.', 'rastreador' => 'Rastreador exigido para aceitação.',
    'chassi' => 'Chassi remarcado sem aceitação.', 'FIPE' => 'Tabela FIPE fora da política de aceitação.',
    'sinistro' => 'Histórico de sinistros fora da política.', 'bônus' => 'Classe de bônus sem aceitação.',
    'vistoria' => 'Vistoria prévia obrigatória.', 'imóvel' => 'Imóvel fora da política de aceitação.',
    'residência' => 'Residência de veraneio sem aceitação.', 'construção' => 'Construção de madeira sem aceitação.',
    'profissão' => 'Profissão sem aceitação.', 'transporte' => 'Transporte de passageiros sem aceitação.',
    'aplicativo' => 'Serviço por aplicativo sem aceitação.', 'placa' => 'Placa de outro estado sem aceitação.',
    'combustível' => 'Combustível GNV sem aceitação.', 'frota' => 'Frota sem aceitação.'
  }.freeze
end

# OS TEXTOS DE FORA DESTE SPEC: o corpus do conector, os das revisões e o custo levantado por elas.
module TextosReaisDoMotivo
  # Os textos de risco do corpus sanitizado do conector (`autonomia-adapters`,
  # `test/fixtures/agger/motivos-de-recusa.sanitized.json`, `textoLimpo`, 13/09/2026), e o que a regra devolve
  # de cada um: o que a regra existe para deixar a Lia explicar.
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
    '[2005] - -Contratação não permitida  -  Ano Modelo do Veículo' => 'Contratação não permitida  -  Ano Modelo do Veículo',
    'Moto de ano/modelo sem aceitação - RP' => 'Moto de ano/modelo sem aceitação - RP',
    '[2159] - -Contratação não permitida - Categoria do Veículo' => 'Contratação não permitida - Categoria do Veículo',
    'UC00 - Risco fora das políticas de aceitação' => 'Risco fora das políticas de aceitação',
    'Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP' => 'Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP',
    'Veículo sem aceitação - RP' => 'Veículo sem aceitação - RP'
  }.freeze

  # Os textos das revisões: os do conector, que saíram com a classe errada, e os da revisão da fatia 2 (as duas
  # rodadas), que saem `risco` do classificador real do conector falando da conta da corretora ou de valor.
  DAS_REVISOES = [
    'Senha expirou. Declinando cálculo.', 'Sistema indisponível: sessão expirada, faça login novamente.',
    'Usuário fulano@corretora.com.br bloqueado.', 'Produtor não credenciado para este produto. Declinando cálculo.',
    'Credenciamento pendente nesta seguradora. Declinando cálculo.', 'Não autorizado a calcular este produto. Declinando cálculo.',
    'Perfil sem autorização para este ramo. Declinando cálculo.', 'Código SUSEP inválido. Declinando cálculo.',
    'Sistema deslogado. Declinando cálculo.', 'Necessário relogar no portal. Declinando cálculo.',
    'Falha ao reautenticar no portal da seguradora.', 'Percentual de comissão acima do permitido pela seguradora.',
    'Corretagem acima do limite do produto. Declinando cálculo.', 'Prêmio mínimo de 1.500,00 não atingido. Declinando cálculo.',
    'Valor do veículo acima de 300 mil reais.', 'Certificado digital vencido.', 'Cadastro do produtor bloqueado.',
    'Faça o log in novamente. Declinando cálculo.', 'Login expirado.',
    'Valor do veículo acima de 300 mil reais. Declinando cálculo.', 'Prêmio mínimo de R$ 800 não atingido. Declinando cálculo.',
    'Prêmio mínimo 1500 não atingido. Declinando cálculo.', 'Taxa mínima de 15,00 não atingida. Declinando cálculo.',
    'Descredenciado para este produto. Declinando cálculo.', 'Recadastramento pendente nesta seguradora. Declinando cálculo.',
    'Desabilitado para este ramo. Declinando cálculo.', 'Desautorizado a calcular este produto. Declinando cálculo.',
    'Inabilitado para emissão neste ramo. Declinando cálculo.', 'Conta suspensa nesta seguradora. Declinando cálculo.',
    'Bloqueio comercial nesta seguradora. Declinando cálculo.', 'Código do agenciador inválido. Declinando cálculo.',
    'Inadimplência com a seguradora. Declinando cálculo.', 'Desconto comercial acima do limite. Declinando cálculo.',
    'Chave de integração expirada. Declinando cálculo.', 'Licença do multicálculo vencida. Declinando cálculo.',
    'E-mail não confirmado no portal. Declinando cálculo.', 'Código de verificação inválido. Declinando cálculo.',
    'Perfil não configurado para este produto. Declinando cálculo.', 'Entre novamente no portal da seguradora. Declinando cálculo.',
    'Faça logoff e entre de novo. Declinando cálculo.', 'Vínculo com a sucursal inexistente. Declinando cálculo.',
    'Convênio da filial inativo. Declinando cálculo.', 'Pró-labore acima do permitido. Declinando cálculo.',
    'Password expired. Declinando cálculo.', 'Contato do suporte: <REDACTED>. Declinando cálculo.',
    'Prêmio mínimo de 800 não atingido. Declinando cálculo.', 'Parcela mínima de 90 não atingida. Declinando cálculo.',
    'Valor do veículo acima de trezentos mil. Declinando cálculo.', 'Valor do veículo acima de 1,5 milhão. Declinando cálculo.',
    'Importância segurada acima de 2 milhões. Declinando cálculo.', 'Franquia mínima 950. Declinando cálculo.',
    'Prêmio mínimo 1 500 não atingido. Declinando cálculo.'
  ].freeze

  # O CUSTO, DECLARADO: textos plausíveis de risco que a regra recusa (a Lia diz só que a seguradora não fez
  # proposta), levantados pela revisão da fatia 2.
  CUSTO = [
    'Condutor com menos de 2 anos de habilitação. Declinando cálculo.',
    'Tempo de habilitação do condutor inferior ao exigido pela aceitação.',
    'CEP de pernoite não cadastrado para aceitação.', 'Veículo bloqueado para aceitação nesta seguradora.',
    'Veículo ano 2005 fora da política de aceitação.', 'Ano modelo 2008 sem aceitação - RP',
    'CEP 04567-000 fora da área de aceitação.', 'Modelo não autorizado para uso em aplicativo. Declinando cálculo.',
    'Categoria do veículo não habilitada para o produto. Declinando cálculo.',
    'Principal condutor sem CNH cadastrada. Declinando cálculo.',
    'Veículo sem permissão de circulação na região. Declinando cálculo.', 'Código FIPE 0012345 sem aceitação.',
    'Produto indisponível para usuários de aplicativo. Declinando cálculo.',
    'Veículo com rastreador bloqueado sem aceitação.', 'Certificado de registro do veículo irregular. Declinando cálculo.',
    'Veículo de corretora de valores sem aceitação.', 'Veículo com suspensão rebaixada sem aceitação.',
    'Contratação não permitida.', 'Restrição técnica.'
  ].freeze
end

# A REGRA DO MOTIVO (fatia 2 do #420, registrada na issue em 13/09/2026): o texto do portal só orienta a
# fala da Lia quando o `kind` é `risco`, o texto sem o código do começo não traz dígito, valor nem termo de conta,
# e nomeia o objeto do risco. Em qualquer outro caso, nil. Os textos são sintéticos, na forma das mensagens de
# recusa do portal, menos os do corpus do conector.
RSpec.describe Autonomia::Insurance::MotivoDaRecusa do
  def motivo(texto, kind: 'risco')
    { 'kind' => kind, 'text' => texto }
  end

  def permitido(texto, kind: 'risco')
    described_class.permitido(motivo(texto, kind: kind))
  end

  def alvo(texto)
    ActiveSupport::Inflector.transliterate(texto).downcase
  end

  describe 'o que libera' do
    TextosReaisDoMotivo::RISCO_DO_CORPUS.each do |texto, devolvido|
      it "libera o texto de risco do corpus «#{texto}»" do
        expect(permitido(texto)).to eq(devolvido)
      end
    end

    describe 'palavras que começam como um padrão e não são um' do
      ['Acessórios fora da política de aceitação.', 'Logradouro fora da área de aceitação.',
       'Catálogo do veículo sem aceitação.', 'Veículo de permissionário sem aceitação.',
       'Veículo não homologado para este produto.', 'Recusado por conta da região de circulação.',
       'Veículo sem aceitação nesta seguradora.'].each do |texto|
        it "libera «#{texto}»" do
          expect(permitido(texto)).to eq(texto)
        end
      end
    end

    it 'devolve o texto aparado' do
      expect(permitido("  Risco sem aceitação.\n")).to eq('Risco sem aceitação.')
    end
  end

  # NENHUM DÍGITO CHEGA AO MODELO: o código do começo sai do texto devolvido, e o dígito que sobra recusa.
  describe 'o código do portal no começo' do
    {
      '400 - Veículo sem aceitação' => 'Veículo sem aceitação', '[2005] - -Veículo sem aceitação' => 'Veículo sem aceitação',
      'UC00 - Veículo sem aceitação' => 'Veículo sem aceitação', '2005 - Contratação não permitida - Ano Modelo do Veículo' =>
        'Contratação não permitida - Ano Modelo do Veículo'
    }.each do |texto, devolvido|
      it "sai de «#{texto}»" do
        expect(permitido(texto)).to eq(devolvido)
      end
    end

    ['Ano 2005 - modelo sem aceitação', 'Veículo sem aceitação [2005]', 'Veículo 400 - sem aceitação',
     '400 Veículo sem aceitação'].each do |texto|
      it "o dígito fora do código do começo recusa «#{texto}»" do
        expect(permitido(texto)).to be_nil
      end
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

  # O `kind` erra, e a regra existe por isso.
  describe 'os textos das revisões, mesmo classificados como risco' do
    TextosReaisDoMotivo::DAS_REVISOES.each do |texto|
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

  describe 'cada padrão de recusa' do
    it 'o controle: o mesmo começo, sem padrão, é liberado' do
      expect(permitido('Declinando o risco deste orçamento.')).to eq('Declinando o risco deste orçamento.')
    end

    TextosDeContaNoMotivo::POR_TERMO.merge(TextosDeContaNoMotivo::POR_VALOR).each do |padrao, textos|
      textos.each do |texto|
        it "#{padrao}: recusa «#{texto}»" do
          expect(permitido(texto)).to be_nil
        end
      end
    end

    # Padrão novo sem exemplo aqui reprova, e exemplo de padrão que saiu da lista também.
    it 'todo padrão da lista tem exemplo' do
      expect(TextosDeContaNoMotivo::POR_TERMO.keys).to match_array(described_class::TERMOS_DE_CONTA.keys)
      expect(TextosDeContaNoMotivo::POR_VALOR.keys).to match_array(described_class::VALORES.keys)
    end

    # O EXEMPLO QUE SÓ AQUELE PADRÃO RECUSA: sem ele, apagar o padrão não reprovaria nada, porque outro padrão
    # recusaria o mesmo texto. Todo exemplo nomeia o risco, então é o padrão que o recusa.
    it 'todo padrão tem um exemplo que só ele recusa' do
      padroes = described_class::TERMOS_DE_CONTA.merge(described_class::VALORES)
      exemplos = TextosDeContaNoMotivo::POR_TERMO.merge(TextosDeContaNoMotivo::POR_VALOR)

      sem_exemplo_proprio = padroes.keys.reject do |nome|
        exemplos.fetch(nome).any? do |texto|
          padroes.select { |_, padrao| alvo(texto).match?(padrao) }.keys == [nome] && described_class.do_risco?(alvo(texto))
        end
      end

      expect(sem_exemplo_proprio).to be_empty
    end
  end

  # O ITEM 4: texto que não nomeia o objeto do risco não é liberado.
  describe 'cada objeto do risco' do
    TextosDeContaNoMotivo::POR_OBJETO.each do |objeto, texto|
      it "#{objeto}: libera «#{texto}»" do
        expect(permitido(texto)).to eq(texto)
      end
    end

    it 'sem objeto do risco, o texto sem termo de conta e sem valor é recusado' do
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
      expect(permitido("Risco sem aceitação #{'a' * described_class::TETO_DO_TEXTO}")).to be_nil
    end

    it 'libera o texto exatamente no teto' do
      texto = "Risco #{'a' * (described_class::TETO_DO_TEXTO - 6)}"

      expect(texto.length).to eq(described_class::TETO_DO_TEXTO)
      expect(permitido(texto)).to eq(texto)
    end
  end
end
