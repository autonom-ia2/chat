require 'rails_helper'

# UM EXEMPLO POR PADRÃO, com e sem acento. Cada texto só tem o termo como motivo para ser recusado: sem
# ele, "Declinando o risco" seria liberado (o exemplo de controle abaixo).
module TextosDeContaNoMotivo
  POR_TERMO = {
    'login' => ['Declinando o risco, faça login novamente.', 'Declinando o risco, faca LOGIN de novo.',
                'Declinando o risco: sistema não logado.', 'Declinando o risco, logue de novo.',
                'Declinando o risco: sistema deslogado.', 'Declinando o risco: necessário relogar.',
                'Declinando o risco: faça o log in novamente.'],
    'senha' => ['Declinando o risco: senha vencida.', 'Declinando o risco: senhas divergentes.'],
    'sessão' => ['Declinando o risco: sessão encerrada.', 'Declinando o risco: sessao encerrada.',
                 'Declinando o risco: sessões simultâneas.'],
    'token' => ['Declinando o risco: token inválido.', 'Declinando o risco: TOKENS vencidos.'],
    'usuário' => ['Declinando o risco: usuário bloqueado.', 'Declinando o risco: usuario sem perfil.'],
    'acesso' => ['Declinando o risco: acesso negado.', 'Declinando o risco: não foi possível acessar.'],
    'permissão' => ['Declinando o risco: sem permissão.', 'Declinando o risco: sem permissao.',
                    'Declinando o risco: permissões insuficientes.'],
    'corretor' => ['Declinando o risco: corretor não habilitado.', 'Declinando o risco: corretora sem cadastro.',
                   'Declinando o risco: corretagem acima do limite.'],
    'credencial' => ['Declinando o risco: credencial vencida.', 'Declinando o risco: credenciais vencidas.',
                     'Declinando o risco: produto não credenciado.', 'Declinando o risco: credenciamento pendente.'],
    'autenticação' => ['Declinando o risco: falha de autenticação.', 'Declinando o risco: falha ao reautenticar.'],
    'autorização' => ['Declinando o risco: não autorizado a calcular.', 'Declinando o risco: sem autorização.'],
    'habilitação' => ['Declinando o risco: ramo não habilitado.', 'Declinando o risco: habilitação pendente.'],
    'produtor' => ['Declinando o risco: produtor inativo.'],
    'SUSEP' => ['Declinando o risco: código SUSEP inválido.'],
    'cadastro' => ['Declinando o risco: cadastro incompleto.', 'Declinando o risco: não cadastrado.'],
    'comissão' => ['Declinando o risco: comissão acima do permitido.', 'Declinando o risco: comissao divergente.'],
    'certificado' => ['Declinando o risco: certificado digital vencido.'],
    'bloqueado' => ['Declinando o risco: perfil bloqueado.'],
    'e-mail' => ['Declinando o risco: contato@exemplo.test sem retorno.'],
    'link' => ['Declinando o risco: veja https://exemplo.test/ajuda.', 'Declinando o risco: veja www.exemplo.test.']
  }.freeze

  POR_VALOR = {
    'R$' => ['Declinando o risco: veículo acima de R$ 500.000,00.', 'Declinando o risco: acima de r$500'],
    'reais' => ['Declinando o risco: acima de trezentos reais.'],
    'mil' => ['Declinando o risco: veículo acima de 300 mil.'],
    'centavos' => ['Declinando o risco: taxa mínima de 15,00 não atingida.'],
    'milhar' => ['Declinando o risco: prêmio mínimo de 1.500 não atingido.'],
    'quatro dígitos' => ['Declinando o risco: prêmio mínimo 1500 não atingido.']
  }.freeze

  # Os textos de risco do corpus sanitizado do conector (`autonomia-adapters`,
  # `test/fixtures/agger/motivos-de-recusa.sanitized.json`, `textoLimpo`, 13/09/2026): o que a regra existe
  # para deixar a Lia explicar.
  RISCO_DO_CORPUS = [
    'Risco sem aceitação para este cenário nesta seguradora.',
    'Não temos um seguro disponível para este veículo. Gostaria de fazer uma nova cotação para outro carro?',
    'Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida',
    'Aceitacao Restrita, cobertura auto nao permitida para este modelo.',
    'O veículo não possui aceitação para a categoria tarifária informada.',
    'Após análise dos dados do veículo, região de circulação e critérios internos de aceitação, estamos declinando o risco ' \
    'deste orçamento.',
    '400 - Restrição técnica para o Segurado',
    'Tipo de veículo não aceito.',
    '[2005] - -Contratação não permitida  -  Ano Modelo do Veículo',
    'Moto de ano/modelo sem aceitação - RP',
    '[2159] - -Contratação não permitida - Categoria do Veículo',
    'UC00 - Risco fora das políticas de aceitação',
    'Carga(s) transportada(s) ( Cigarro/Fumo) sem aceitação - RP',
    'Veículo sem aceitação - RP'
  ].freeze
end

# A REGRA DO MOTIVO (fatia 2 do #420, registrada na issue em 13/09/2026): o texto do portal só orienta a
# fala da Lia quando o `kind` é `risco` E o texto não traz termo de conta nem valor. Em qualquer outro caso,
# nil. Os textos são sintéticos, na forma das mensagens de recusa do portal, menos os do corpus do conector.
RSpec.describe Autonomia::Insurance::MotivoDaRecusa do
  def motivo(texto, kind: 'risco')
    { 'kind' => kind, 'text' => texto }
  end

  def permitido(texto, kind: 'risco')
    described_class.permitido(motivo(texto, kind: kind))
  end

  describe 'o que libera' do
    TextosDeContaNoMotivo::RISCO_DO_CORPUS.each do |texto|
      it "libera o texto de risco do corpus «#{texto}»" do
        expect(permitido(texto)).to eq(texto)
      end
    end

    describe 'palavras que começam como um padrão e não são um' do
      ['Acessórios fora da política de aceitação.', 'Logradouro fora da área de aceitação.',
       'Catálogo do veículo sem aceitação.', 'Veículo de permissionário sem aceitação.',
       'Veículo não homologado para este produto.'].each do |texto|
        it "libera «#{texto}»" do
          expect(permitido(texto)).to eq(texto)
        end
      end
    end

    it 'devolve o texto aparado' do
      expect(permitido("  Risco sem aceitação.\n")).to eq('Risco sem aceitação.')
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

  # O `kind` erra, e a regra existe por isso: os três textos da revisão do conector saíram com a classe errada,
  # e os da revisão da fatia 2 saem `risco` do classificador real do conector falando da conta da corretora.
  describe 'os textos das revisões, mesmo classificados como risco' do
    ['Senha expirou. Declinando cálculo.',
     'Sistema indisponível: sessão expirada, faça login novamente.',
     'Usuário fulano@corretora.com.br bloqueado.',
     'Produtor não credenciado para este produto. Declinando cálculo.',
     'Credenciamento pendente nesta seguradora. Declinando cálculo.',
     'Não autorizado a calcular este produto. Declinando cálculo.',
     'Perfil sem autorização para este ramo. Declinando cálculo.',
     'Código SUSEP inválido. Declinando cálculo.',
     'Sistema deslogado. Declinando cálculo.',
     'Necessário relogar no portal. Declinando cálculo.',
     'Falha ao reautenticar no portal da seguradora.',
     'Percentual de comissão acima do permitido pela seguradora.',
     'Corretagem acima do limite do produto. Declinando cálculo.',
     'Prêmio mínimo de 1.500,00 não atingido. Declinando cálculo.',
     'Valor do veículo acima de 300 mil reais.',
     'Certificado digital vencido.',
     'Cadastro do produtor bloqueado.',
     'Faça o log in novamente. Declinando cálculo.',
     'Login expirado.'].each do |texto|
      it "recusa «#{texto}»" do
        expect(permitido(texto)).to be_nil
      end
    end
  end

  describe 'cada padrão recusa o texto' do
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
    # recusaria o mesmo texto.
    it 'todo padrão tem um exemplo que só ele recusa' do
      padroes = described_class::TERMOS_DE_CONTA.merge(described_class::VALORES)
      exemplos = TextosDeContaNoMotivo::POR_TERMO.merge(TextosDeContaNoMotivo::POR_VALOR)

      sem_exemplo_proprio = padroes.keys.reject do |nome|
        exemplos.fetch(nome).any? do |texto|
          alvo = ActiveSupport::Inflector.transliterate(texto).downcase
          padroes.select { |_, padrao| alvo.match?(padrao) }.keys == [nome]
        end
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
