require 'rails_helper'

# UM EXEMPLO POR TERMO DE CONTA, com e sem acento. Cada texto só tem o termo como motivo para ser recusado:
# sem ele, "Declinando o risco" seria liberado (o exemplo de controle abaixo).
module TextosDeContaNoMotivo
  POR_TERMO = {
    'login' => ['Declinando o risco, faça login novamente.', 'Declinando o risco, faca LOGIN de novo.',
                'Declinando o risco: sistema não logado.', 'Declinando o risco, logue de novo.'],
    'senha' => ['Declinando o risco: senha vencida.', 'Declinando o risco: senhas divergentes.'],
    'sessão' => ['Declinando o risco: sessão encerrada.', 'Declinando o risco: sessao encerrada.',
                 'Declinando o risco: sessões simultâneas.'],
    'token' => ['Declinando o risco: token inválido.', 'Declinando o risco: TOKENS vencidos.'],
    'usuário' => ['Declinando o risco: usuário bloqueado.', 'Declinando o risco: usuario bloqueado.'],
    'acesso' => ['Declinando o risco: acesso negado.', 'Declinando o risco: não foi possível acessar.'],
    'permissão' => ['Declinando o risco: sem permissão.', 'Declinando o risco: sem permissao.',
                    'Declinando o risco: permissões insuficientes.'],
    'corretor' => ['Declinando o risco: corretor não habilitado.', 'Declinando o risco: corretora sem cadastro.'],
    'credencial' => ['Declinando o risco: credencial vencida.', 'Declinando o risco: credenciais vencidas.'],
    'autenticação' => ['Declinando o risco: falha de autenticação.', 'Declinando o risco: falha de autenticacao.'],
    'e-mail' => ['Declinando o risco: contato@exemplo.test sem cadastro.']
  }.freeze
end

# A REGRA DO MOTIVO (fatia 2 do #420, registrada na issue em 13/09/2026): o texto do portal só orienta a
# fala da Lia quando o `kind` é `risco` E o texto não traz termo de conta. Em qualquer outro caso, nil.
#
# Os textos são sintéticos, na forma das mensagens de recusa do portal. Os três de "o kind erra" são os da
# revisão da PR autonomia-adapters#60.
RSpec.describe Autonomia::Insurance::MotivoDaRecusa do
  def motivo(texto, kind: 'risco')
    { 'kind' => kind, 'text' => texto }
  end

  def permitido(texto, kind: 'risco')
    described_class.permitido(motivo(texto, kind: kind))
  end

  describe 'o que libera' do
    [
      'Risco sem aceitação para este cenário nesta seguradora.',
      'Cotação não será realizada por motivos técnicos: Veículo acima da idade permitida',
      '[2005] - -Contratação não permitida - Ano Modelo do Veículo',
      # As palavras que começam como um termo de conta e não são uma.
      'Acessórios fora da política de aceitação.',
      'Logradouro fora da área de aceitação.',
      'Catálogo do veículo sem aceitação.',
      'Veículo de permissionário sem aceitação.'
    ].each do |texto|
      it "libera «#{texto}» com kind risco" do
        expect(permitido(texto)).to eq(texto)
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

  # O `kind` erra, e a regra existe por isso: os três textos saíram com a classe errada na revisão.
  describe 'os textos da revisão do conector, mesmo classificados como risco' do
    it 'recusa "Senha expirou. Declinando cálculo."' do
      expect(permitido('Senha expirou. Declinando cálculo.')).to be_nil
    end

    it 'recusa "Sistema indisponível: sessão expirada, faça login novamente."' do
      expect(permitido('Sistema indisponível: sessão expirada, faça login novamente.')).to be_nil
    end

    it 'recusa "Usuário fulano@corretora.com.br bloqueado."' do
      expect(permitido('Usuário fulano@corretora.com.br bloqueado.')).to be_nil
    end
  end

  describe 'cada termo de conta recusa o texto' do
    it 'o controle: o mesmo começo, sem termo, é liberado' do
      expect(permitido('Declinando o risco deste orçamento.')).to eq('Declinando o risco deste orçamento.')
    end

    TextosDeContaNoMotivo::POR_TERMO.each do |termo, textos|
      textos.each do |texto|
        it "#{termo}: recusa «#{texto}»" do
          expect(permitido(texto)).to be_nil
        end
      end
    end

    # Termo novo sem exemplo aqui reprova, e exemplo de termo que saiu da lista também.
    it 'todo termo da lista tem exemplo' do
      expect(TextosDeContaNoMotivo::POR_TERMO.keys).to match_array(described_class::TERMOS_DE_CONTA.keys)
    end
  end

  describe 'valor em reais' do
    it 'recusa o texto com valor em reais: ele vai ao modelo, e valor ao cliente é do código' do
      expect(permitido('Declinando o risco: veículo acima de R$ 500.000,00.')).to be_nil
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
