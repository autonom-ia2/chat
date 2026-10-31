# #1431 (F0) — placar da busca na base, para rodar no banco local com a base ingerida.
#   AGENTES=12,13 PERGUNTAS=/caminho/perguntas.yml SAIDA=/caminho/fora/do/repo bundle exec rails autonomia:rag:placar
# Imprime só o resumo (sem o texto das perguntas). O detalhe por pergunta vai para SAIDA, que precisa ficar fora do
# repositório: o repo é público e a pergunta de uma base de cliente carrega o material dele.
namespace :autonomia do
  namespace :rag do
    desc 'Placar da busca na base: hit@k, MRR, fora da base e distâncias por agente'
    task placar: :environment do
      perguntas = Autonomia::Agents::PlacarDaBase.perguntas_do_arquivo(ENV.fetch('PERGUNTAS'))
      saida = Pathname(ENV.fetch('SAIDA')).expand_path
      abort 'SAIDA precisa ficar fora do repositório' if saida.ascend.any?(Rails.root)
      FileUtils.mkdir_p(saida)

      ENV.fetch('AGENTES').split(',').each do |id|
        placar = Autonomia::Agents::PlacarDaBase.new(agent: Autonomia::Agents::Agent.find(id.strip), perguntas: perguntas).medir
        File.write(saida.join("placar-agente-#{placar[:agente]}.json"), JSON.pretty_generate(placar))
        puts JSON.generate(Autonomia::Agents::PlacarDaBase.resumo(placar))
      end
    end
  end
end
