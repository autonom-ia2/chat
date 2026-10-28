require 'rails_helper'
require 'open3'

# O script local que gera o .sql da chave de leitura (#2301): Ruby puro, sem Rails; o .sql trava pela conta, pela ficha
# e pela versão vigente, e quem executa é a Orquestração. Aqui o SQL gerado roda no banco de teste (sem BEGIN/COMMIT,
# dentro da transação do exemplo). Chave e instrução inventadas.
RSpec.describe 'script/desempenho/chave.rb' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let(:ficha) { ficha_da_loja!(account, sujeito_id: 7) }
  let(:pasta) { Dir.mktmpdir }
  let(:script) { Rails.root.join('script/desempenho/chave.rb').to_s }
  let(:chave) { "Leia a conversa.\nTexto com 'aspas', $$ e um $tag$ qualquer.\n" }

  after { FileUtils.remove_entry(pasta) }

  def gerar(*extras, versao: ficha.versao, saida: File.join(pasta, 'chave.sql'))
    File.write(File.join(pasta, 'chave.md'), chave)
    argumentos = ['--chave', File.join(pasta, 'chave.md'), '--conta', account.id.to_s, '--ficha', ficha.id.to_s,
                  '--versao', versao.to_s, '--saida', saida, *extras]
    _saida, erro, status = Open3.capture3(RbConfig.ruby, '--disable-gems', script, *argumentos)
    [status.success?, erro, (File.read(saida) if File.exist?(saida))]
  end

  def executar(sql)
    ActiveRecord::Base.transaction(requires_new: true) do
      ActiveRecord::Base.connection.execute(sql.sub("BEGIN;\n", '').sub("COMMIT;\n", ''))
    end
  end

  it 'gera o UPDATE da ficha vigente com a chave intacta e o hash da instrução' do
    File.write(File.join(pasta, 'instrucao.txt'), 'Responda com o prazo.')

    certo, _erro, sql = gerar('--instrucao', File.join(pasta, 'instrucao.txt'))
    executar(sql)

    expect(certo).to be(true)
    expect(ficha.reload).to have_attributes(chave_de_leitura: chave, instrucao_hash: Digest::SHA256.hexdigest('Responda com o prazo.'))
  end

  it 'grava o .sql só para o dono ler (0600), mesmo se o arquivo já existia aberto' do
    saida = File.join(pasta, 'chave.sql')
    File.write(saida, 'antigo')
    File.chmod(0o644, saida)

    gerar(saida: saida)

    expect(File.stat(saida).mode & 0o777).to eq(0o600)
  end

  it '--com-teste grava leitura.com_teste no mesmo UPDATE, sem mudar a ordem das chaves da ficha' do
    antes = ficha.configuracao
    ordem = antes.keys
    certo, _erro, sql = gerar('--com-teste')
    executar(sql)

    configuracao = ficha.reload.configuracao
    expect(certo).to be(true)
    expect(ficha.chave_de_leitura).to eq(chave)
    expect(configuracao.keys).to eq(ordem.include?('leitura') ? ordem : ordem + ['leitura'])
    expect(configuracao['leitura']['com_teste']).to be(true)
    expect(configuracao.except('leitura')).to eq(antes.except('leitura'))
  end

  it '--com-teste mantém o que a leitura já tinha, na mesma posição, e não duplica com_teste' do
    leitura = { 'rotulo_do_agente' => 'LOJA', 'com_teste' => false, 'max_caracteres' => 9 }
    ficha.update!(configuracao: ficha.configuracao.merge('leitura' => leitura))
    ordem = ficha.reload.configuracao.keys

    _certo, _erro, sql = gerar('--com-teste')
    executar(sql)

    configuracao = ficha.reload.configuracao
    expect(configuracao.keys).to eq(ordem)
    expect(configuracao['leitura']).to eq('rotulo_do_agente' => 'LOJA', 'max_caracteres' => 9, 'com_teste' => true)
    expect(configuracao['leitura'].keys).to eq(%w[rotulo_do_agente max_caracteres com_teste])
  end

  it 'sem --com-teste não toca na configuracao' do
    antes = ficha.configuracao
    _certo, _erro, sql = gerar

    executar(sql)

    expect(sql).not_to include('configuracao =')
    expect(ficha.reload.configuracao).to eq(antes)
  end

  it 'não atualiza nada se a versão não for a vigente' do
    _certo, _erro, sql = gerar(versao: ficha.versao + 1)

    expect { executar(sql) }.to raise_error(ActiveRecord::StatementInvalid, a_string_including('esperava 1 ficha vigente'))
    expect(ficha.reload.chave_de_leitura).to be_nil
  end

  it 'recusa gravar o .sql dentro do repositório e hash que não é hexadecimal' do
    dentro, erro, = gerar(saida: Rails.root.join('tmp/chave.sql').to_s)
    expect([dentro, erro]).to eq([false, "--saida precisa ficar fora do repositório\n"])

    hash_ruim, erro, = gerar('--hash', 'z' * 64)
    expect([hash_ruim, erro]).to eq([false, "--hash precisa ter 64 caracteres hexadecimais\n"])
  end

  it 'recusa gravar dentro de QUALQUER repositório git (outra cópia, outra worktree), direto ou por link simbólico' do
    outro_repositorio = File.join(pasta, 'copia')
    FileUtils.mkdir_p(File.join(outro_repositorio, 'sub'))
    _saida, _erro, iniciado = Open3.capture3('git', 'init', '-q', outro_repositorio)
    expect(iniciado.success?).to be(true)
    File.symlink(File.join(outro_repositorio, 'sub'), File.join(pasta, 'atalho'))

    [File.join(outro_repositorio, 'sub', 'chave.sql'), File.join(pasta, 'atalho', 'chave.sql')].each do |saida|
      certo, erro, conteudo = gerar(saida: saida)
      expect([certo, erro, conteudo]).to eq([false, "--saida precisa ficar fora do repositório\n", nil])
    end
  end

  it 'recusa a pasta de --saida que não existe' do
    certo, erro, = gerar(saida: File.join(pasta, 'nao-existe', 'chave.sql'))

    expect([certo, erro]).to eq([false, "a pasta de --saida não existe\n"])
  end
end
