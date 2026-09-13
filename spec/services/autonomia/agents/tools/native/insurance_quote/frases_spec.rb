require 'rails_helper'

# O CATÁLOGO DAS FRASES DO ESPECIALISTA (entrega das frases, 12/09/2026).
#
# As quatorze frases que o cliente lê passam a ser escritas pelo especialista, no pedido. O que este
# arquivo trava são as três garantias que não podem depender de o modelo colaborar: todo papel
# produz palavra, os quatorze textos de uma execução são distintos, e nada disso levanta.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote::Frases do
  let(:peneira) { Autonomia::Agents::Tools::TextoAoCliente }

  def com(frases)
    described_class.de({ described_class::NO => frases })
  end

  describe 'o catálogo de recuo' do
    # REGRA SEM GUARDA É INTENÇÃO. A peneira proíbe número, travessão, crase, caminho de campo e
    # vocabulário de sistema na frase do MODELO; se a constante de recuo carregasse qualquer um
    # deles, a regra valeria para ele e não para nós — e é a constante que sai quando a frase dele
    # não passa. Foi por esta guarda que o `AVISO_SEM_BONUS` perdeu o "(é um número de 0 a 10)".
    it 'toda constante de recuo passa pela propria peneira' do
      reprovadas = described_class.constantes.reject { |_, texto| peneira.vetar(texto) == texto }

      expect(reprovadas.keys).to be_empty
    end

    # A GARANTIA 2 SE APOIA NISTO: o desempate recua para a constante do papel, e ela não pode já
    # estar tomada por outro.
    it 'as constantes sao distintas duas a duas' do
      expect(described_class.constantes.values.uniq.size).to eq(described_class::ORDEM.size)
    end

    it 'ha uma constante e uma descricao para cada papel, e nada sobrando' do
      expect(described_class.constantes.keys).to match_array(described_class::ORDEM)
      expect(described_class::DESCRICOES.keys).to match_array(described_class::ORDEM)
    end

    # A DESCRIÇÃO É INSTRUÇÃO DE AGENTE, e o modelo copia a pontuação dela para o WhatsApp: uma
    # crase na descrição vira acento grave na mensagem do cliente (medido em produção), e um
    # travessão vira travessão.
    it 'nenhuma descricao usa crase nem travessao' do
      textos = described_class::DESCRICOES.values + [described_class::DESCRICAO_DO_NO]

      expect(textos.select { |t| t.include?('`') || t.match?(/[—–]/) }).to be_empty
    end

    # P1-5: `Declaracao::ACEITA` manda o modelo NÃO afirmar que a cotação já foi às seguradoras, e o
    # aviso de espera sai ANTES de `tool.start`, que tem cinco caminhos de recusa. A descrição do
    # papel não pode pedir o contrário do que o aceite proíbe, e a constante não pode afirmá-lo.
    it 'a espera nao manda afirmar um envio que ainda nao aconteceu' do
      cotacao = Autonomia::Agents::Tools::Native::InsuranceQuote

      expect(described_class::DESCRICOES[:espera]).to include('não afirme que já foi enviado')
      expect(cotacao::Declaracao::ESPERANDO).not_to include('seguradoras')
      expect(cotacao::Declaracao::ACEITA).to include('NÃO afirme que já foi')
    end
  end

  describe '.de' do
    # GARANTIA 1, primeira metade: a execução aberta antes desta versão não tem o nó nenhum, e a
    # ferramenta montada pelo encerramento pode nem ter argumentos. Nenhuma delas pode calar.
    it 'sem argumentos, devolve os quatorze papeis pelas constantes' do
      expect(described_class.de(nil)).to eq(described_class.constantes)
      expect(described_class.de({})).to eq(described_class.constantes)
      expect(described_class.de({ 'produto' => 'auto' })).to eq(described_class.constantes)
    end

    it 'usa a frase que o especialista escreveu' do
      expect(com('espera' => 'Já estou vendo isso com as companhias.')[:espera])
        .to eq('Já estou vendo isso com as companhias.')
    end

    # GARANTIA 1, segunda metade: `strict` garante PRESENÇA, não conteúdo. Branco, reprovado pela
    # peneira ou de tipo errado recuam para a constante — nunca para o silêncio.
    {
      'em branco' => '   ',
      'com número' => 'Chegaram 3 opções:',
      'com travessão' => 'Comparativo — todas as opções',
      'com caminho de campo' => 'Faltou o insured.document',
      'que não é texto' => { 'nao' => 'é string' }
    }.each do |motivo, frase|
      it "recua para a constante quando a frase vem #{motivo}" do
        expect(com('primeiros_precos' => frase)[:primeiros_precos])
          .to eq(described_class.constantes[:primeiros_precos])
      end
    end

    it 'recua so no papel estragado, e mantem os outros' do
      resolvidas = com('espera' => 'Chego em 5 minutos.', 'falhou' => 'Não consegui concluir agora.')

      expect(resolvidas[:espera]).to eq(described_class.constantes[:espera])
      expect(resolvidas[:falhou]).to eq('Não consegui concluir agora.')
    end

    # GARANTIA 2 — P1-6. A identidade de uma entrega é o SHA do texto, num espaço por execução: duas
    # frases iguais fariam a segunda ser lida como já publicada, `delivered_count` não subiria, e o
    # cliente ficaria sem saber, por exemplo, que faltava a placa.
    it 'duas frases iguais saem como textos distintos' do
      resolvidas = com('falhou' => 'Não deu certo por aqui.', 'incerto' => 'Não deu certo por aqui.')

      expect(resolvidas[:falhou]).to eq('Não deu certo por aqui.')
      expect(resolvidas[:incerto]).to eq(described_class.constantes[:incerto])
    end

    it 'os quatorze textos sao distintos, escreva o especialista o que escrever' do
      iguais = described_class::ORDEM.index_with { 'A mesma frase para tudo.' }.transform_keys(&:to_s)

      resolvidas = com(iguais)

      expect(resolvidas.values.uniq.size).to eq(described_class::ORDEM.size)
      expect(resolvidas.values).to all(be_present)
    end

    # E A REGRA QUE FECHA A PROVA: a frase do especialista igual à constante de OUTRO papel é
    # recusada. Sem ela, o dono daquela constante recuaria para um texto já tomado e o desempate não
    # teria para onde ir.
    it 'recusa a frase que copia a constante de outro papel' do
      resolvidas = com('espera' => described_class.constantes[:falhou])

      expect(resolvidas[:espera]).to eq(described_class.constantes[:espera])
      expect(resolvidas[:falhou]).to eq(described_class.constantes[:falhou])
    end

    # GARANTIA 3: nunca levanta. Quem chama é, entre outros, o fecho — e um fecho que levanta é um
    # cliente sem uma palavra (o `rescue` de `Encerramento#etapa` engoliria tudo).
    it 'nao levanta com argumento de forma inesperada' do
      [nil, {}, { described_class::NO => nil }, { described_class::NO => 'texto' },
       { described_class::NO => [] }, 'string solta'].each do |argumento|
        expect { described_class.de(argumento) }.not_to raise_error
      end
    end

    # O NÓ CHEGA COM CHAVE DE TEXTO (veio da linha) OU COM SÍMBOLO (a ferramenta em memória). As duas
    # grafias precisam resolver a mesma frase — trocar a leitura do hash inteiro pela leitura da
    # chave não pode custar isso.
    it 'le o no nas duas grafias de chave' do
      frase = 'Já estou vendo isso com as companhias.'

      expect(described_class.de({ described_class::NO => { 'espera' => frase } })[:espera]).to eq(frase)
      expect(described_class.de({ described_class::NO.to_sym => { espera: frase } })[:espera]).to eq(frase)
    end

    # NÃO COPIA O FORMULÁRIO PARA LER UMA FRASE. `deep_stringify_keys` sobre `argumentos` duplicava
    # os ~90 campos de auto a cada chamada, e o fecho chama isto umas seis vezes (quatro papéis, cada
    # um resolvido e mais a constante, sem memória entre eles). O que se lê é a chave.
    it 'nao copia o hash de argumentos inteiro para ler o no' do
      argumentos = { 'dados' => { 'vehicle' => { 'plate' => 'ABC1D23' } },
                     described_class::NO => { 'espera' => 'Já estou vendo isso.' } }

      expect(argumentos).not_to receive(:deep_stringify_keys)

      expect(described_class.de(argumentos)[:espera]).to eq('Já estou vendo isso.')
    end

    # DETERMINISMO É REQUISITO: a identidade de uma entrega é o SHA do texto, e a ferramenta é
    # remontada a cada passada a partir dos mesmos argumentos. Duas leituras que discordassem dariam
    # um token na emissão e outro na pergunta do fecho.
    it 'e deterministica: duas leituras dos mesmos argumentos dao os mesmos textos' do
      argumentos = { described_class::NO => { 'espera' => 'Já estou vendo.', 'falhou' => 'Já estou vendo.' } }

      primeira = described_class.de(argumentos)
      segunda = described_class.de(argumentos.deep_dup)

      expect(primeira).to eq(segunda)
    end
  end

  describe '.parametro' do
    let(:no) { Autonomia::Agents::Tools::Native::Base.propriedade(described_class.parametro) }

    # A FORMA QUE A MEDIÇÃO APROVOU (12/09/2026): nó e folhas OBRIGATÓRIOS, sem `null`. Em `strict` o
    # modelo não consegue omitir nem mandar `null`, o que elimina por construção a entrega sem frase;
    # e custa menos tokens que a forma anulável, porque o `"null"` de cada folha é token pago.
    it 'declara as quatorze folhas, todas obrigatorias e nenhuma anulavel' do
      expect(no[:properties].keys).to match_array(described_class::ORDEM.map(&:to_s))
      expect(no[:required]).to match_array(no[:properties].keys)
      expect(no[:type]).to eq('object')
      expect(no[:additionalProperties]).to be(false)
      expect(no[:properties].values.map { |folha| folha['type'] }).to all(eq('string'))
    end

    it 'cada folha leva a descricao do papel' do
      described_class::ORDEM.each do |papel|
        expect(no[:properties][papel.to_s]['description']).to eq(described_class::DESCRICOES[papel])
      end
    end
  end

  # P1-4 — A COLISÃO DE NOME COM O ADAPTER, E ELA É HTTP 400 NA CHAMADA INTEIRA.
  #
  # `Parametros#grupos` põe as raízes do `quote/schema` por último e `objeto` monta `properties` por
  # `to_h`: um campo de raiz com o nome do nó apagaria o nó em silêncio e deixaria `required` com a
  # chave duas vezes. A API responde `has non-unique elements` e o agente fica MUDO — a mesma classe
  # de falha de 08/09/2026. Hoje o risco é zero (as duas raízes do adapter estão em `NAO_EXPOSTOS`),
  # e basta o adapter publicar uma terceira.
  describe 'a colisão de nome com o adapter' do
    let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }

    it 'levanta na MONTAGEM, e nao so numa spec' do
      raiz = { 'name' => described_class::NO, 'type' => 'string', 'description' => 'campo novo do adapter' }

      expect { cotacao.objeto(cotacao.params + [raiz]) }
        .to raise_error(Autonomia::Agents::Tools::Native::Base::NomeDeParametroDuplicado, /frases_ao_cliente/)
    end

    # A GUARDA É SOBRE A CLASSE DO DEFEITO, e não sobre este nome: um campo de raiz chamado
    # `vehicle` apagaria o GRUPO `vehicle` pelo mesmo caminho.
    it 'levanta tambem quando a raiz nova colide com um grupo do formulario' do
      lista = Autonomia::Insurance::Parametros.de_auto(Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO)
      raiz = { 'name' => 'vehicle', 'type' => 'string', 'description' => 'campo novo do adapter' }

      expect { cotacao.objeto(lista + [raiz]) }
        .to raise_error(Autonomia::Agents::Tools::Native::Base::NomeDeParametroDuplicado, /vehicle/)
    end

    it 'nao levanta na montagem de hoje, com o formulario inteiro de auto' do
      lista = cotacao.params + Autonomia::Insurance::Parametros.de_auto(Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO)

      objeto = cotacao.objeto(lista)

      expect(objeto[:required].uniq.size).to eq(objeto[:properties].keys.size)
    end
  end
end
