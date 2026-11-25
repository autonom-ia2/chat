// #3211 — os agentes prontos que a corretora contrata (Api::V1::Accounts::Autonomia::ContratadosController). A chave
// é a do catálogo do servidor (Autonomia::Agents::Contratados::MODELOS); a tela só mostra os modelos que conhece,
// porque os textos de cada um moram no i18n (AGENTS.CONTRATADOS.*).
export const MODELO_UNIVERSAL = 'seguro_viagem_universal';
export const MODELOS_CONTRATADOS = [MODELO_UNIVERSAL];

// Os mesmos limites do servidor (Contratados::Instrucao::MAX_NOME e MAX_SOBRE).
export const MAX_NOME = 120;
export const MAX_SOBRE = 1000;
