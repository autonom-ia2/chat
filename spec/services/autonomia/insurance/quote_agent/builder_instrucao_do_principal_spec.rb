require 'rails_helper'

# A INSTRUÇÃO DA LIA É A DO DEPLOY (#380) — a mesma classe de defeito da entrega 3, agora no principal.
#
# Até 11/09/2026 `Builder#criar_agente` gravava `principal.md` em `autonomia_agents.instruction` com as
# variáveis substituídas, e nada relia o arquivo: toda edição do texto só valia para agente criado
# depois. O principal tem o que o especialista não tinha — quatro valores que a corretora escolhe —,
# então o desenho é em duas partes: as ESCOLHAS ficam guardadas no config (termo 1) e quem monta o
# prompt lê o arquivo do deploy e substitui com elas (termos 2 e 3). Um agente criado antes de as
# escolhas serem guardadas continua lendo a coluna, sem quebrar. E uma variável NUNCA chega ao modelo
# como `$nomeAgente` (termo 6): escolha faltando para com o nome do campo, não cai no arquivo cru.
#
# O que vai ao modelo é medido pelo caminho real: `PromptBuilder#instructions`, que o `Answerer`
# entrega ao cliente da OpenAI. O texto esperado é montado AQUI, sem passar pelo Builder, para a prova
# não comparar o Builder consigo mesmo.
#
# PROVA POR MUTAÇÃO (11/09/2026, `~/ops/agente-cotacao/issue-380/mutacoes_i380.rb`, oito mutações): o
# `PromptBuilder` lendo a coluna, o Builder sem gravar as escolhas, o arquivo cru no lugar da coluna
# quando faltam escolhas, a substituição pulando um campo, o tipo do agente ignorado, a escolha em
# branco passando em silêncio, a chave desprotegida na API, `Agent#instrucao_do_sistema` devolvendo
# só a coluna — cada uma reprova um exemplo daqui (ou da spec de jornada da API do agente). Rodada 6
# (`mutacoes_i380_rodada6.rb`): a substituição voltando a uma passada por marcador, a recusa de marcador
# dentro de uma escolha apagada, a chave presente com `null` voltando à coluna — idem.
RSpec.describe Autonomia::Insurance::QuoteAgent::Builder do
  let(:account) { create(:account) }
  let(:arquivo) { described_class::INSTRUCOES.join('principal.md').read }
  let(:chave) { described_class::ESCOLHAS_DA_CORRETORA }
  let(:escolhas) do
    { 'nome_agente' => 'Clara', 'nome_corretora' => 'Seguros do Vale',
      'horario' => 'todo dia, das 08h às 20h', 'comportamento' => 'objetivo' }
  end
  # O arquivo com as escolhas, substituído à mão.
  let(:esperado) do
    arquivo.gsub('$nomeAgente', 'Clara').gsub('$nomeCorretora', 'Seguros do Vale')
           .gsub('$horarioAtendimento', 'todo dia, das 08h às 20h').gsub('$comportamento', 'objetivo')
  end

  def construir(**extra)
    described_class.new(account: account, nome_agente: 'Clara', nome_corretora: 'Seguros do Vale',
                        horario: 'todo dia, das 08h às 20h', comportamento: 'objetivo', **extra).call
  end

  # A Lia de antes de #380: só a coluna sabe o nome dela.
  def agente_criado_antes
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active, enabled: true,
      instruction: 'Você é Lia, e atende pela corretora Sena.',
      config: { 'native_tool_slugs' => described_class::TODAS_AS_TOOLS, 'with_knowledge' => true }
    )
  end

  # O caminho real: o `instructions` que o Answerer manda ao modelo.
  def prompt_de(agente)
    Autonomia::Agents::PromptBuilder.new(agent: agente, query: 'oi').instructions
  end

  describe 'as escolhas da corretora ficam guardadas (termo 1)' do
    it 'grava os quatro valores no config, na chave própria — o texto deixa de ser a única fonte' do
      expect(construir.config[chave]).to eq(escolhas)
    end

    it 'guarda o horário e o comportamento padrão quando a corretora não escolhe' do
      agente = described_class.new(account: account, nome_agente: 'Clara', nome_corretora: 'Seguros do Vale').call

      expect(agente.config[chave]).to include('horario' => described_class::HORARIO_PADRAO,
                                              'comportamento' => described_class::COMPORTAMENTO_PADRAO)
    end

    it 'guarda o que a corretora escreveu, sem interpretar' do
      agente = construir(nome_agente: 'Mia \0 Bot')

      expect(agente.config.dig(chave, 'nome_agente')).to eq('Mia \0 Bot')
      expect(agente.instrucao_do_sistema).to include('Você é Mia \0 Bot, e atende')
    end
  end

  describe 'quem roda lê o arquivo do deploy (termos 2 e 3)' do
    it 'o agente já criado recebe o texto novo sem ser recriado' do
      agente = construir
      agente.update!(instruction: 'instrução velha, gravada no nascimento')

      expect(agente.reload.instrucao_do_sistema).to eq(esperado)
      expect(prompt_de(agente)).to include(esperado)
      expect(prompt_de(agente)).not_to include('instrução velha')
    end

    it 'um agente criado do zero nasce com o mesmo texto, na coluna e no que roda' do
      agente = construir

      expect(agente.instruction).to eq(esperado)
      expect(agente.instrucao_do_sistema).to eq(esperado)
    end

    # O ARQUIVO É LIDO A CADA MONTAGEM, não fotografado no boot nem memoizado: é o que faz o deploy
    # seguinte valer. A prova dubla a LEITURA DO ARQUIVO (`Pathname#read` passa por `File.read`), não o
    # método do Builder: duas leituras sucessivas devolvem dois textos, e duas montagens do MESMO agente
    # têm de refletir cada uma o seu. Um `||=` na leitura devolveria o primeiro texto nas duas.
    it 'lê o arquivo de novo a cada montagem, com as escolhas guardadas' do
      agente = construir
      caminho = described_class::INSTRUCOES.join(described_class::ARQUIVO_DO_PRINCIPAL)
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with(caminho.to_s)
                                   .and_return('Você é $nomeAgente ($comportamento).', 'Agora sou $nomeAgente, da $nomeCorretora.')

      expect(agente.instrucao_do_sistema).to eq('Você é Clara (objetivo).')
      expect(agente.instrucao_do_sistema).to eq('Agora sou Clara, da Seguros do Vale.')
    end

    it 'o agente criado antes de as escolhas serem guardadas continua lendo a coluna, sem quebrar' do
      antigo = agente_criado_antes

      expect(antigo.instrucao_do_sistema).to eq('Você é Lia, e atende pela corretora Sena.')
      expect(prompt_de(antigo)).to include('Você é Lia, e atende pela corretora Sena.')
    end

    it 'agente que não é de cotação continua lendo a própria instrução, mesmo com a chave no config' do
      outro = Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active,
                                               enabled: true, instruction: 'Atenda.', config: { chave => escolhas })

      expect(outro.instrucao_do_sistema).to eq('Atenda.')
      expect(prompt_de(outro)).to include('Atenda.')
      expect(prompt_de(outro)).not_to include('Você é Clara')
    end
  end

  describe 'variável nunca chega ao modelo (termo 6)' do
    it 'no agente criado pelo Builder' do
      expect(prompt_de(construir).scan(/\$[a-zA-Z]+/)).to be_empty
    end

    it 'no agente criado antes' do
      expect(prompt_de(agente_criado_antes).scan(/\$[a-zA-Z]+/)).to be_empty
    end

    # Escolha faltando NÃO cai no arquivo cru nem na coluna em silêncio: para, e diz qual campo. Só um
    # write fora do Builder produz este estado (a API não toca na chave: `PROTECTED_CONFIG_KEYS`).
    it 'escolha faltando para com o nome do campo, em vez de mandar o marcador' do
      agente = construir
      agente.update!(config: agente.config.merge(chave => escolhas.except('nome_corretora')))

      expect { agente.reload.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas, 'nome_corretora')
    end

    it 'escolha em branco também para' do
      agente = construir
      agente.update!(config: agente.config.merge(chave => escolhas.merge('horario' => '')))

      expect { agente.reload.instrucao_do_sistema }.to raise_error(described_class::EscolhasIncompletas, 'horario')
    end

    # A CHAVE PRESENTE E VAZIA NÃO É O AGENTE DE ANTES DE #380 (rodada 4). Só a chave AUSENTE devolve a
    # coluna; `{}` ou `false` (escrita fora do Builder) é a mesma classe da chave incompleta e para com o
    # primeiro campo. Um `blank?` no lugar do `nil?` da guarda mandaria o agente de volta à coluna de
    # nascimento em silêncio — o texto velho, com crases —, que é o default calado que o termo 6 proíbe.
    it 'chave presente e vazia também para, em vez de voltar à coluna em silêncio' do
      agente = construir
      agente.update!(instruction: 'instrução velha, gravada no nascimento',
                     config: agente.config.merge(chave => {}))

      expect { agente.reload.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas, 'nome_agente')
    end

    it 'chave presente com um valor que não é hash (false) também para' do
      agente = construir
      agente.update!(config: agente.config.merge(chave => false))

      expect { agente.reload.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas, 'nome_agente')
      expect(agente.instruction).not_to be_blank # a coluna está lá, e mesmo assim não é usada
    end

    # A CHAVE PRESENTE COM `null` (rodada 6, P2 do Codex) é a borda que `nil?` deixava passar: o jsonb
    # guarda `{"agente_de_cotacao": null}` com a chave lá, e `escolhas.nil?` a tratava como o agente de
    # antes de #380 — de volta à coluna de nascimento, em silêncio. Só a chave AUSENTE (`key?`) é o
    # agente antigo.
    it 'chave presente com null também para, em vez de voltar à coluna em silêncio' do
      agente = construir
      agente.update!(instruction: 'instrução velha, gravada no nascimento',
                     config: agente.config.merge(chave => nil))

      expect(agente.reload.config).to have_key(chave) # o jsonb guardou o null com a chave
      expect { agente.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas, 'nome_agente')
    end

    it 'o erro nomeia o campo e nunca carrega o valor de outra escolha' do
      agente = construir
      agente.update!(config: agente.config.merge(chave => escolhas.except('comportamento')))

      expect { agente.reload.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas) { |e| expect(e.message).not_to include('Clara') }
    end

    # UMA ESCOLHA QUE CONTÉM UM MARCADOR (rodada 6, P2 do Codex) é recusada com o nome do campo. Com uma
    # passada por marcador, `nome_corretora: '$horarioAtendimento'` virava o horário (o valor inserido era
    # relido pela passada seguinte); com a passada única, `'$nomeAgente'` chegaria ao modelo como o
    # marcador literal. Nenhum dos dois: para. Só escrita fora do Builder produz este estado — a criação
    # recusa o mesmo valor (`builder_spec` «o que a corretora escreve»).
    it 'escolha com um marcador dentro para com o nome do campo, em vez de virar a outra escolha' do
      agente = construir
      agente.update!(config: agente.config.merge(chave => escolhas.merge('nome_corretora' => '$horarioAtendimento')))

      expect { agente.reload.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas, 'nome_corretora')
    end

    it 'escolha com o próprio marcador dentro para, em vez de mandar o marcador ao modelo' do
      agente = construir
      agente.update!(config: agente.config.merge(chave => escolhas.merge('nome_corretora' => '$nomeAgente')))

      expect { agente.reload.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas, 'nome_corretora')
    end

    it 'horário com marcador dentro também para' do
      agente = construir
      agente.update!(config: agente.config.merge(chave => escolhas.merge('horario' => 'das 09h às 18h ($comportamento)')))

      expect { agente.reload.instrucao_do_sistema }
        .to raise_error(described_class::EscolhasIncompletas, 'horario')
    end
  end

  # A SUBSTITUIÇÃO É NUMA PASSADA SÓ (rodada 6): uma regex com os quatro marcadores, e o bloco consulta a
  # escolha do que casou. É medida direto em `substituir`, com um valor que a conferência recusaria, porque
  # a regra dela é outra: o valor inserido NUNCA é relido — a recusa de marcador é a segunda guarda, não a
  # única. Uma passada por marcador (`reduce`) devolveria o horário no lugar da corretora.
  describe 'a substituição é numa passada só (rodada 6)' do
    let(:modelo) { 'Você é $nomeAgente, da $nomeCorretora, $horarioAtendimento ($comportamento).' }

    it 'o valor inserido nunca é relido' do
      texto = described_class.substituir(modelo, escolhas.merge('nome_corretora' => '$horarioAtendimento'))

      expect(texto).to eq('Você é Clara, da $horarioAtendimento, todo dia, das 08h às 20h (objetivo).')
    end

    it 'um marcador só casa inteiro: `$nomeAgentes` não é `$nomeAgente`' do
      expect(described_class.substituir('$nomeAgente e $nomeAgentes', escolhas)).to eq('Clara e $nomeAgentes')
    end
  end

  # A SUBSTITUIÇÃO NÃO INVENTA VALOR (rodada 7, P3 do Codex). `escolhas` chega conferida, mas o `fetch` é a
  # segunda guarda: um marcador conhecido sem escolha correspondente para alto (`KeyError`), em vez de virar
  # string vazia — com `[]`, `nil.to_s` é `''` e o modelo receberia «Você é Clara, da .» sem ninguém perceber.
  # A mensagem do `KeyError` carrega só o nome do campo, nunca o valor de outra escolha.
  describe 'a substituição não inventa valor (rodada 7)' do
    it 'marcador conhecido sem escolha correspondente para alto, em vez de virar string vazia' do
      expect { described_class.substituir('Você é $nomeAgente, da $nomeCorretora.', escolhas.except('nome_corretora')) }
        .to raise_error(KeyError) do |erro|
          expect(erro.message).to include('nome_corretora')
          expect(erro.message).not_to include('Clara')
        end
    end
  end

  # O QUE FOI AO MODELO É RECONSTRUÍVEL (termo 4): o texto é função só do arquivo no SHA deployado e das
  # escolhas guardadas. Com os dois, `Builder.instrucao_do_principal` devolve o mesmo texto.
  describe 'auditabilidade (termo 4)' do
    it 'o mesmo arquivo e as mesmas escolhas devolvem o mesmo texto, sem depender da coluna' do
      agente = construir
      agente.update!(instruction: nil)

      expect(described_class.instrucao_do_principal(agente.reload)).to eq(esperado)
    end
  end
end
