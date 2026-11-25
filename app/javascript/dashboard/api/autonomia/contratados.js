/* global axios */
import ApiClient from '../ApiClient';

// #3211 (Tarefa 21) — os agentes prontos que a pessoa contrata (Api::V1::Accounts::Autonomia::ContratadosController,
// Agents::ContratadoController e Agents::AcessoDaSeguradoraController). Sem a flag da conta (ou sem as consultas
// prontas), `lista` vem vazia; GET pede autonomia_view, escrita pede autonomia_manage; o POST do acesso, só administrador.
//   lista          -> { modelos: ['seguro_viagem_universal'] }
//   contratar      -> 201 o agente (com `contratado`) | 422 { error, code, campo }
//   salvarDados    -> 200 o agente | 404 | 422 { error, code, campo }  (`campo` nulo = erro do formulário todo)
//   acesso         -> { seguradora, login_dica, estado, motivo, conferido_em, so_cotacao } ou { estado: 'nao_conferido' }
//   conferirAcesso -> 200 o mesmo (também com o login recusado) | 422 { error, code: 'acesso_incompleto' | 'indisponivel', campo }
// O servidor nunca devolve login nem senha, só `login_dica`. Este módulo também não guarda nada: a senha passa pelo
// corpo do POST e não fica em propriedade nenhuma.
const CAMPOS_DA_CORRETORA = {
  nomeAgente: 'nome_agente',
  nomeCorretora: 'nome_corretora',
  sobreCorretora: 'sobre_corretora',
};

// Só os campos que vieram, com o nome que o servidor lê.
const corpoDaCorretora = (campos = {}) =>
  Object.entries(CAMPOS_DA_CORRETORA).reduce(
    (corpo, [chave, nomeNoServidor]) =>
      campos[chave] === undefined
        ? corpo
        : { ...corpo, [nomeNoServidor]: campos[chave] },
    {}
  );

class ContratadosAPI extends ApiClient {
  constructor() {
    super('autonomia', { accountScoped: true });
  }

  lista() {
    return axios.get(`${this.url}/contratados`);
  }

  contratar(modelo, { nomeAgente, nomeCorretora, sobreCorretora }) {
    return axios.post(
      `${this.url}/contratados/${modelo}`,
      corpoDaCorretora({ nomeAgente, nomeCorretora, sobreCorretora })
    );
  }

  salvarDados(agentId, campos) {
    return axios.patch(
      `${this.url}/agents/${agentId}/contratado`,
      corpoDaCorretora(campos)
    );
  }

  acesso(agentId) {
    return axios.get(`${this.url}/agents/${agentId}/acesso_da_seguradora`);
  }

  conferirAcesso(agentId, { login, senha }) {
    return axios.post(`${this.url}/agents/${agentId}/acesso_da_seguradora`, {
      login,
      senha,
    });
  }
}

export default new ContratadosAPI();
