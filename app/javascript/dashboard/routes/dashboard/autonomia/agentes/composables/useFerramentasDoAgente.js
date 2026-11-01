import { ref } from 'vue';
import AutonomiaAgentsAPI from 'dashboard/api/autonomia/agents';
import { paraApi } from '../utils/ferramentas';

// #1301 — as ferramentas HTTP de um agente com a API que já existe (ToolsController, só SuperAdmin):
// listar, criar desligada, alterar, ligar/desligar, excluir e testar. A lista é trocada inteira a
// cada mudança (nada de mutar o item). Um 401/403 em qualquer chamada liga `semPermissao`: a gaveta
// troca para a explicação (protótipo F12).

// O ToolsController levanta Pundit::NotAuthorizedError, que o core responde com 401
// (render_unauthorized); 403 fica por garantia.
const STATUS_SEM_PERMISSAO = [401, 403];

// O que deu errado, em categorias que a tela sabe dizer. `mensagem` é o texto do 422 (full_messages).
export const motivoDoErro = erro => {
  const resposta = erro?.response;
  if (!resposta) return { tipo: 'REDE', mensagem: '' };
  if (STATUS_SEM_PERMISSAO.includes(resposta.status)) {
    return { tipo: 'SEM_PERMISSAO', mensagem: '' };
  }
  const mensagem = String(resposta.data?.error ?? '');
  // #1425: o teste da ferramenta manda também o que o agente recebe nessa falha.
  const agenteRecebe = String(resposta.data?.agente_recebe ?? '');
  return { tipo: 'API', mensagem, agenteRecebe };
};

export const useFerramentasDoAgente = agenteId => {
  const ferramentas = ref([]);
  const carregando = ref(true);
  const erroAoCarregar = ref(false);
  const semPermissao = ref(false);
  // true quando o 403 chega depois de a lista abrir (a permissão mudou no meio do uso).
  const perdeuPermissao = ref(false);

  const vigiar = async chamada => {
    try {
      return await chamada();
    } catch (erro) {
      const motivo = motivoDoErro(erro);
      if (motivo.tipo === 'SEM_PERMISSAO') {
        perdeuPermissao.value = !carregando.value;
        semPermissao.value = true;
      }
      throw Object.assign(new Error(motivo.tipo), { motivo });
    }
  };

  const carregar = async () => {
    carregando.value = true;
    erroAoCarregar.value = false;
    try {
      const { data } = await vigiar(() =>
        AutonomiaAgentsAPI.getTools(agenteId)
      );
      ferramentas.value = data?.payload || [];
    } catch {
      erroAoCarregar.value = true;
    } finally {
      carregando.value = false;
    }
  };

  const trocar = salva => {
    const existe = ferramentas.value.some(f => f.id === salva.id);
    ferramentas.value = existe
      ? ferramentas.value.map(f => (f.id === salva.id ? salva : f))
      : [salva, ...ferramentas.value];
    return salva;
  };

  // Nova ferramenta nasce desligada: só liga depois de um teste que deu certo.
  const criar = async rascunho => {
    const { data } = await vigiar(() =>
      AutonomiaAgentsAPI.createTool(agenteId, {
        ...paraApi(rascunho),
        enabled: false,
      })
    );
    return trocar(data);
  };

  const alterar = async (id, rascunho, extra = {}) => {
    const { data } = await vigiar(() =>
      AutonomiaAgentsAPI.updateTool(agenteId, id, {
        ...paraApi(rascunho),
        ...extra,
      })
    );
    return trocar(data);
  };

  const mudarLigada = async (id, enabled) => {
    const { data } = await vigiar(() =>
      AutonomiaAgentsAPI.updateTool(agenteId, id, { enabled })
    );
    return trocar(data);
  };

  const excluir = async id => {
    await vigiar(() => AutonomiaAgentsAPI.deleteTool(agenteId, id));
    ferramentas.value = ferramentas.value.filter(f => f.id !== id);
  };

  const testar = async (id, valores) => {
    const { data } = await vigiar(() =>
      AutonomiaAgentsAPI.testTool(agenteId, id, valores)
    );
    return data;
  };

  return {
    ferramentas,
    carregando,
    erroAoCarregar,
    semPermissao,
    perdeuPermissao,
    carregar,
    criar,
    alterar,
    mudarLigada,
    excluir,
    testar,
  };
};
