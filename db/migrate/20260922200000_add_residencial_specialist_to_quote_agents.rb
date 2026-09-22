# O ESPECIALISTA DE RESIDENCIAL NOS AGENTES QUE JÁ EXISTEM (fase 5 do piloto, chat#323, 22/09/2026).
#
# O `Builder` cria os especialistas só no nascimento do agente (`JaExiste` depois). Sem isto, o especialista de
# residencial valeria só para agente criado a partir deste deploy, e o agente em produção seguiria sem ele. O
# que roda é lido do deploy (`Builder.instrucao_mantida`, `ferramentas_mantidas_do_especialista`,
# `descricao_mantida`): as colunas desta linha são o retrato do nascimento, como nos que o `Builder` cria.
#
# SÓ INSERE. Agente que já tem o slug fica como está (o índice único de agente e slug garante, e o
# `ON CONFLICT` o respeita). E não liga residencial em conta nenhuma: quem decide se a Lia o chama é
# `Builder.disponivel?`, pela conexão da conta.
#
# O DOWN NÃO APAGA. A linha pode ter nascido pelo `Builder` num agente criado depois deste deploy, e a migration
# não tem como separar as duas; apagar especialista é decisão por conta, fora de migration.
class AddResidencialSpecialistToQuoteAgents < ActiveRecord::Migration[7.2]
  SLUG = 'cotacao_residencial'.freeze

  def up
    dados = Autonomia::Insurance::QuoteAgent::Builder::ESPECIALISTAS.find { |e| e[:slug] == SLUG }
    instrucao = Autonomia::Insurance::QuoteAgent::Builder.instrucao_do_especialista(dados[:arquivo])
    ferramentas = Autonomia::Insurance::QuoteAgent::Builder.ferramentas_do_especialista(dados)

    # SEM SQUISH: o manual vai citado dentro do SQL, e o squish achataria as quebras de linha dele (o ensaio pegou).
    execute(<<~SQL) # rubocop:disable Rails/SquishedSQLHeredocs
      INSERT INTO autonomia_agent_specialists
        (account_id, autonomia_agent_id, name, slug, description, instruction, enabled, tool_slugs, metadata,
         created_at, updated_at)
      SELECT a.account_id, a.id, #{quote(dados[:nome])}, #{quote(SLUG)}, #{quote(dados[:descricao])},
             #{quote(instrucao)}, TRUE, #{quote(ferramentas.to_json)}::jsonb, '{}'::jsonb, NOW(), NOW()
      FROM autonomia_agents a
      WHERE a.agent_type = 'insurance_quote'
      ON CONFLICT (autonomia_agent_id, slug) DO NOTHING
    SQL
  end

  def down; end

  private

  def quote(valor)
    connection.quote(valor)
  end
end
