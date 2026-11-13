// #2932–#2934 — o que os passos novos com motor leem do servidor: os públicos
// salvos (Públicos), os blocos da conta (automações marcadas "Usar como bloco"),
// quantos entrariam hoje no "para cada", as consultas prontas e o teste do
// "buscar em outro sistema". Os públicos, os blocos e as consultas ficam
// guardados aqui depois da 1ª leitura, para a frase do passo (frasesDosNovos)
// dizer o nome sem pedir de novo.
import { ref } from 'vue';
import AutomacoesAPI from 'dashboard/api/autonomia/automacoes';
import { audiencesAPI as AudiencesAPI } from 'dashboard/api/campaignJourneyAudiences';

export { COM_MOTOR, temMotor } from './passosNovos';

const publicos = ref([]);
const blocos = ref([]);
// A última contagem da lista e o último teste da busca que a tela fez: a prévia
// do ensaio e do histórico (LivrePassoNovoPrevia) mostra o que veio deles.
const ultimaContagem = ref({ total: 0, primeiros: [] });
const ultimoTeste = ref([]);
export const contagemDaTela = () => ultimaContagem.value;
export const valorDoTeste = caminho =>
  ultimoTeste.value.find(dado => dado.caminho === caminho)?.valor ?? '';
let publicosLidos = null;
let blocosLidos = null;

export const publicosDaConta = () => publicos.value;
export const nomeDoPublico = id =>
  publicos.value.find(publico => publico.value === id)?.label || '';

// Lidos uma vez por tela; o erro deixa a lista vazia (a escolha some e a tela
// diz que não há público), e a próxima abertura tenta de novo.
export const carregarPublicos = () => {
  publicosLidos ||= AudiencesAPI.list({ saved: true })
    .then(({ data }) => {
      publicos.value = (data?.payload || []).map(publico => ({
        value: publico.id,
        label: publico.name,
      }));
      return publicos.value;
    })
    .catch(() => {
      publicosLidos = null;
      return [];
    });
  return publicosLidos;
};

export const blocosDaConta = () => blocos.value;
// As frases dos passos de dentro, que a peça do bloco monta com o catálogo.
export const guardarFrasesDoBloco = (id, frases) => {
  blocos.value = blocos.value.map(bloco =>
    bloco.id === id ? { ...bloco, frases } : bloco
  );
};
export const blocoDe = id =>
  blocos.value.find(bloco => bloco.id === id) || null;

// Os blocos vêm da lista de automações, com a receita (para a tela mostrar os
// passos de dentro). Mudar a marca na lista relê (`esquecerBlocos`).
export const carregarBlocos = () => {
  blocosLidos ||= AutomacoesAPI.get()
    .then(({ data }) => {
      blocos.value = (data?.automacoes || [])
        .filter(automacao => automacao.bloco)
        .map(automacao => ({
          id: automacao.id,
          nome: automacao.nome,
          passos: automacao.versao?.receita?.passos || [],
          frases: [],
        }));
      return blocos.value;
    })
    .catch(() => {
      blocosLidos = null;
      return [];
    });
  return blocosLidos;
};
export const esquecerBlocos = () => {
  blocosLidos = null;
};

// #2934: as consultas prontas (Busca de CEP, Consulta de CNPJ…): [{ id, nome,
// faz, entradas: [{ nome, rotulo, exemplo }], dados: [{ caminho, rotulo }],
// disponivel, falta, limite_do_dia }]. A que a conta não pode usar vem com o
// que falta (`falta`), nunca some.
const consultasProntas = ref([]);
let consultasLidas = null;
export const consultasProntasDaConta = () => consultasProntas.value;
export const consultaPronta = id =>
  consultasProntas.value.find(consulta => consulta.id === id) || null;
export const carregarConsultasProntas = () => {
  consultasLidas ||= AutomacoesAPI.consultasProntas()
    .then(({ data }) => {
      consultasProntas.value = data?.consultas || [];
      return consultasProntas.value;
    })
    .catch(() => {
      consultasLidas = null;
      return [];
    });
  return consultasLidas;
};

// { total, primeiros, fora_do_teto, mais_alem, teto }, pela régua do motor.
export const contarLista = (lista, teto) =>
  AutomacoesAPI.contarLista({ lista, teto }).then(({ data }) => {
    ultimaContagem.value = data;
    return data;
  });

// { ok, dados: [{ caminho, valor, rotulo }] } ou { ok: false, error }. Busca de
// verdade: só quando a pessoa toca no botão.
export const testarConsulta = fonte =>
  AutomacoesAPI.testarConsulta(fonte)
    .then(({ data }) => {
      ultimoTeste.value = data.ok ? data.dados : [];
      return data;
    })
    .catch(erro => ({ ok: false, error: erro?.response?.data?.error || '' }));

// O "Buscar agora" do ensaio: cada dado guardado com o valor de agora. Na
// consulta pronta, com o que ela usaria da conversa do ensaio (`entradas`).
const fonteDoEnsaio = passo =>
  passo.fonte?.de === 'pronta'
    ? {
        de: 'pronta',
        consulta: passo.fonte.consulta,
        exemplos: passo.entradasDoEnsaio || {},
      }
    : passo.fonte;
export const buscarNoEnsaio = passo =>
  testarConsulta(fonteDoEnsaio(passo)).then(resposta => ({
    ...resposta,
    dados: (passo.guardar || []).map(dado => ({
      nome: dado.nome,
      valor:
        (resposta.dados || []).find(achado => achado.caminho === dado.caminho)
          ?.valor ?? '',
    })),
  }));
