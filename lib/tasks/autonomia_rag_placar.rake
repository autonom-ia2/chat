# #1431 (F0) — placar da base, para rodar no banco local com a base ingerida. Nunca em produção (lá, só psql).
#   AGENTES=12,13 PERGUNTAS=/caminho/perguntas.yml SAIDA=/pasta/fora/de/repo bundle exec rails autonomia:rag:placar
#   RESPOSTA=1 TETO_USD=2 ... também roda a resposta e o juiz (IA paga; para antes do teto, que vale para a execução
#   inteira, somando todos os agentes).
# Imprime só o resumo (sem o texto das perguntas). O detalhe por pergunta vai para SAIDA, que precisa ficar fora de
# qualquer repositório git: o repo é público e a pergunta de uma base de cliente carrega o material dele.
namespace :autonomia do
  namespace :rag do
    desc 'Placar da base: busca (hit@k, MRR, fora da base, distâncias) e, com RESPOSTA=1, resposta e juiz'
    task placar: :environment do
      abort 'Só em desenvolvimento ou teste' unless Rails.env.development? || Rails.env.test?

      begin
        saida = Autonomia::Agents::PlacarDaBase.pasta_de_saida(ENV.fetch('SAIDA'))
      rescue ArgumentError => e
        abort e.message
      end
      agentes = ENV.fetch('AGENTES').split(',').map { |id| Autonomia::Agents::Agent.find(id.strip) }
      perguntas = Autonomia::Agents::PlacarDaBase.perguntas_do_arquivo(ENV.fetch('PERGUNTAS'))
      medidor = Autonomia::Agents::Material::MedidorDeCusto.new(teto: Float(ENV.fetch('TETO_USD'))) if ENV['RESPOSTA'] == '1'
      FileUtils.mkdir_p(saida)

      agentes.each do |agente|
        placar = Autonomia::Agents::PlacarDaBase.new(agent: agente, perguntas: perguntas).medir
        File.write(saida.join("placar-agente-#{agente.id}.json"), JSON.pretty_generate(placar))
        puts JSON.generate(Autonomia::Agents::PlacarDaBase.resumo(placar))
        next unless ENV['RESPOSTA'] == '1'

        resposta = Autonomia::Agents::PlacarDaResposta.new(agent: agente, perguntas: perguntas, medidor: medidor).medir
        File.write(saida.join("resposta-agente-#{agente.id}.json"), JSON.pretty_generate(resposta))
        puts JSON.generate(Autonomia::Agents::PlacarDaResposta.resumo(resposta))
      end
    end
  end
end
