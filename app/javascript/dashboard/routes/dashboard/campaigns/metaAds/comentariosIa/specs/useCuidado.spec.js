import { flushPromises } from '@vue/test-utils';
import { effectScope, ref } from 'vue';
import ComentariosIaAPI from 'dashboard/api/comentariosIa';
import {
  ESPERA_LENDO_MS,
  MAX_LEITURAS,
  useCuidado,
  useResumo,
} from '../useCuidado';

// #2212: o cuidado de um post vem do Painel do servidor; as escritas regravam e devolvem o Painel novo.
vi.mock('dashboard/api/comentariosIa', () => ({
  default: {
    getCuidado: vi.fn(),
    saveCuidado: vi.fn(),
    previa: vi.fn(),
    lerAntigos: vi.fn(),
    getResumo: vi.fn(),
  },
}));

const alvo = { kind: 'post', id: '1790', perfil: 'instagram-7' };
const painel = (extra = {}) => ({
  network: 'instagram',
  private_available: true,
  care: 'on',
  message: 'Oi! O catálogo: loja.com',
  para_quem: 'Quem pedir o link',
  phrases: ['Te mandei no privado!', 'Olha o privado!'],
  read_old: false,
  results: { sent: 2, replied: 1, skipped: 0 },
  unanswered: 3,
  older: 1,
  to_see: [],
  hidden: [],
  ...extra,
});
const falha = (status, data) =>
  Object.assign(new Error('x'), { response: { status, data } });
const pendente = () => {
  let resolver;
  const promessa = new Promise(resolve => {
    resolver = resolve;
  });
  return [promessa, valor => resolver(valor)];
};

describe('useCuidado (#2212)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lê o Painel do alvo e para de carregar', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    const cuidado = useCuidado(alvo);
    expect(cuidado.carregando.value).toBe(true);
    await flushPromises();

    expect(ComentariosIaAPI.getCuidado).toHaveBeenCalledWith(alvo);
    expect(cuidado.painel.value.care).toBe('on');
    expect(cuidado.carregando.value).toBe(false);
    expect(cuidado.erro.value).toBeNull();
  });

  it.each([
    [403, 'acesso'],
    [404, 'sumiu'],
    [500, 'rede'],
  ])('erro %s vira %s', async (status, erro) => {
    ComentariosIaAPI.getCuidado.mockRejectedValue(falha(status));
    const cuidado = useCuidado(alvo);
    await flushPromises();

    expect(cuidado.erro.value).toBe(erro);
    expect(cuidado.painel.value).toBeNull();
  });

  it('sem alvo (flag desligada), não lê nada', async () => {
    useCuidado(null);
    useResumo(() => null);
    await flushPromises();

    expect(ComentariosIaAPI.getCuidado).not.toHaveBeenCalled();
    expect(ComentariosIaAPI.getResumo).not.toHaveBeenCalled();
  });

  it('trocar de alvo lê o novo, e só a leitura mais nova vale', async () => {
    let primeira;
    ComentariosIaAPI.getCuidado
      .mockReturnValueOnce(
        new Promise(resolve => {
          primeira = resolve;
        })
      )
      .mockResolvedValueOnce({ data: painel({ care: 'paused' }) });
    const atual = ref(alvo);
    const cuidado = useCuidado(atual);
    atual.value = { ...alvo, id: '1791' };
    await flushPromises();
    primeira({ data: painel({ care: 'off' }) });
    await flushPromises();

    expect(ComentariosIaAPI.getCuidado).toHaveBeenLastCalledWith({
      ...alvo,
      id: '1791',
    });
    expect(cuidado.painel.value.care).toBe('paused');
  });

  it('trocar de alvo tira o Painel do anterior da tela enquanto lê o novo', async () => {
    const [segunda, responderSegunda] = pendente();
    ComentariosIaAPI.getCuidado
      .mockResolvedValueOnce({ data: painel({ message: 'Texto do A' }) })
      .mockReturnValueOnce(segunda);
    const atual = ref(alvo);
    const cuidado = useCuidado(atual);
    await flushPromises();
    expect(cuidado.painel.value.message).toBe('Texto do A');

    atual.value = { ...alvo, id: '1791' };
    await flushPromises();
    expect(cuidado.painel.value).toBeNull();
    expect(cuidado.carregando.value).toBe(true);

    responderSegunda({ data: painel({ message: 'Texto do B' }) });
    await flushPromises();
    expect(cuidado.painel.value.message).toBe('Texto do B');
  });

  it('ler de novo o mesmo alvo mantém o Painel na tela', async () => {
    const [segunda] = pendente();
    ComentariosIaAPI.getCuidado
      .mockResolvedValueOnce({ data: painel() })
      .mockReturnValueOnce(segunda);
    const cuidado = useCuidado(alvo);
    await flushPromises();

    cuidado.carregar();
    expect(cuidado.painel.value.care).toBe('on');
  });

  it('a resposta de uma escrita do alvo anterior não entra no Painel do novo', async () => {
    const [gravando, responderGravacao] = pendente();
    ComentariosIaAPI.getCuidado
      .mockResolvedValueOnce({ data: painel({ message: 'Texto do A' }) })
      .mockResolvedValueOnce({ data: painel({ message: 'Texto do B' }) });
    ComentariosIaAPI.saveCuidado.mockReturnValueOnce(gravando);
    const atual = ref(alvo);
    const cuidado = useCuidado(atual);
    await flushPromises();

    const salvo = cuidado.pausar();
    atual.value = { ...alvo, id: '1791' };
    await flushPromises();
    responderGravacao({
      data: painel({ message: 'Texto do A', care: 'paused' }),
    });
    await salvo;

    expect(cuidado.painel.value.message).toBe('Texto do B');
    expect(cuidado.painel.value.care).toBe('on');
  });

  it.each([
    [falha(403), 'acesso'],
    [falha(422, { error: 'invalid_message' }), 'invalid_message'],
    [falha(422, { error: 'invalid_para_quem' }), 'invalid_para_quem'],
    [falha(422, { error: 'invalid_status' }), 'rede'],
    [falha(500), 'rede'],
    [new Error('sem rede'), 'rede'],
  ])('escrita que falha diz o porquê (%#)', async (erro, motivo) => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    ComentariosIaAPI.saveCuidado
      .mockRejectedValueOnce(erro)
      .mockResolvedValueOnce({ data: painel() });
    const cuidado = useCuidado(alvo);
    await flushPromises();

    expect(await cuidado.pausar()).toBe(false);
    expect(cuidado.falhaAoSalvar.value).toBe(motivo);
    expect(await cuidado.voltar()).toBe(true);
    expect(cuidado.falhaAoSalvar.value).toBeNull();
  });

  it('salvar grava o corpo do contrato e guarda o Painel novo', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({
      data: painel({ care: 'off' }),
    });
    ComentariosIaAPI.saveCuidado.mockResolvedValue({ data: painel() });
    const cuidado = useCuidado(alvo);
    await flushPromises();

    const valeu = await cuidado.salvar({
      message: 'Oi!',
      paraQuem: 'Quem perguntar o preço',
      phrases: ['Te mandei!'],
      status: 'on',
    });

    expect(valeu).toBe(true);
    expect(ComentariosIaAPI.saveCuidado).toHaveBeenCalledWith(alvo, {
      message: 'Oi!',
      paraQuem: 'Quem perguntar o preço',
      phrases: ['Te mandei!'],
      status: 'on',
    });
    expect(cuidado.painel.value.care).toBe('on');
    expect(cuidado.salvando.value).toBe(false);
  });

  it('pausar e voltar regravam o que está guardado, com outro status', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    ComentariosIaAPI.saveCuidado.mockResolvedValue({
      data: painel({ care: 'paused' }),
    });
    const cuidado = useCuidado(alvo);
    await flushPromises();

    await cuidado.pausar();
    expect(ComentariosIaAPI.saveCuidado).toHaveBeenLastCalledWith(alvo, {
      message: 'Oi! O catálogo: loja.com',
      paraQuem: 'Quem pedir o link',
      phrases: ['Te mandei no privado!', 'Olha o privado!'],
      status: 'paused',
    });
    expect(cuidado.painel.value.care).toBe('paused');

    await cuidado.voltar();
    expect(ComentariosIaAPI.saveCuidado.mock.lastCall[1].status).toBe('on');
  });

  it('escrita que falha devolve false e mantém o Painel', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    ComentariosIaAPI.saveCuidado.mockRejectedValue(falha(422));
    const cuidado = useCuidado(alvo);
    await flushPromises();

    expect(await cuidado.pausar()).toBe(false);
    expect(cuidado.painel.value.care).toBe('on');
    expect(cuidado.salvando.value).toBe(false);
  });

  it('a prévia devolve os exemplos, ou null quando falha', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    const exemplos = { recebe: { sample: true }, nao: null };
    ComentariosIaAPI.previa
      .mockResolvedValueOnce({ data: exemplos })
      .mockRejectedValueOnce(falha(500));
    const cuidado = useCuidado(alvo);
    await flushPromises();

    expect(await cuidado.previa('Quem pedir o link')).toEqual(exemplos);
    expect(ComentariosIaAPI.previa).toHaveBeenCalledWith(alvo, {
      paraQuem: 'Quem pedir o link',
    });
    expect(await cuidado.previa('Quem pedir o link')).toBeNull();
  });

  it('ler e mandar põe na fila e lê o Painel de novo', async () => {
    ComentariosIaAPI.getCuidado
      .mockResolvedValueOnce({ data: painel() })
      .mockResolvedValueOnce({ data: painel({ read_old: true }) });
    ComentariosIaAPI.lerAntigos.mockResolvedValue({ data: { queued: 3 } });
    const cuidado = useCuidado(alvo);
    await flushPromises();

    expect(await cuidado.lerAntigos()).toBe(true);
    expect(ComentariosIaAPI.lerAntigos).toHaveBeenCalledWith(alvo);
    expect(ComentariosIaAPI.getCuidado).toHaveBeenCalledTimes(2);
    expect(cuidado.painel.value.read_old).toBe(true);
  });

  it('ler e mandar que falha não relê', async () => {
    ComentariosIaAPI.getCuidado.mockResolvedValue({ data: painel() });
    ComentariosIaAPI.lerAntigos.mockRejectedValue(falha(500));
    const cuidado = useCuidado(alvo);
    await flushPromises();

    expect(await cuidado.lerAntigos()).toBe(false);
    expect(ComentariosIaAPI.getCuidado).toHaveBeenCalledTimes(1);
  });
});

describe('useResumo (#2212)', () => {
  beforeEach(() => vi.clearAllMocks());

  it('lê o resumo e marca a falha', async () => {
    ComentariosIaAPI.getResumo
      .mockResolvedValueOnce({ data: { status: 'ready', questions: 2 } })
      .mockRejectedValueOnce(falha(500));
    const resumo = useResumo(alvo);
    await flushPromises();

    expect(resumo.resumo.value.questions).toBe(2);
    expect(resumo.falhou.value).toBe(false);

    await resumo.carregar();
    expect(resumo.falhou.value).toBe(true);
    expect(resumo.carregando.value).toBe(false);
  });

  describe('lendo (a primeira contagem roda num job)', () => {
    beforeEach(() => vi.useFakeTimers());
    afterEach(() => vi.useRealTimers());

    it('reading segue carregando e pergunta de novo até vir pronto', async () => {
      ComentariosIaAPI.getResumo
        .mockResolvedValueOnce({ data: { status: 'reading' } })
        .mockResolvedValueOnce({ data: { status: 'reading' } })
        .mockResolvedValueOnce({ data: { status: 'ready', questions: 2 } });
      const resumo = useResumo(alvo);
      await flushPromises();

      expect(resumo.resumo.value).toBeNull();
      expect(resumo.carregando.value).toBe(true);
      expect(resumo.falhou.value).toBe(false);

      await vi.advanceTimersByTimeAsync(ESPERA_LENDO_MS);
      expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(2);
      expect(resumo.carregando.value).toBe(true);

      await vi.advanceTimersByTimeAsync(ESPERA_LENDO_MS);
      expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(3);
      expect(resumo.resumo.value.questions).toBe(2);
      expect(resumo.carregando.value).toBe(false);
    });

    it('reading sem fim: para no teto e vira falha, com tentar de novo', async () => {
      ComentariosIaAPI.getResumo.mockResolvedValue({
        data: { status: 'reading' },
      });
      const resumo = useResumo(alvo);
      await flushPromises();
      await vi.advanceTimersByTimeAsync(ESPERA_LENDO_MS * MAX_LEITURAS * 2);

      expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(MAX_LEITURAS);
      expect(resumo.falhou.value).toBe(true);
      expect(resumo.carregando.value).toBe(false);

      ComentariosIaAPI.getResumo.mockResolvedValueOnce({
        data: { status: 'ready', questions: 1 },
      });
      await resumo.carregar();
      expect(resumo.falhou.value).toBe(false);
      expect(resumo.resumo.value.questions).toBe(1);
    });

    it('trocar de alvo para as perguntas do anterior', async () => {
      ComentariosIaAPI.getResumo
        .mockResolvedValueOnce({ data: { status: 'reading' } })
        .mockResolvedValue({ data: { status: 'ready', questions: 5 } });
      const atual = ref(alvo);
      const resumo = useResumo(atual);
      await flushPromises();

      atual.value = { ...alvo, id: '1791' };
      await flushPromises();
      await vi.advanceTimersByTimeAsync(ESPERA_LENDO_MS * 3);

      expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(2);
      expect(ComentariosIaAPI.getResumo).toHaveBeenLastCalledWith({
        ...alvo,
        id: '1791',
      });
      expect(resumo.resumo.value.questions).toBe(5);
    });

    it('sair da tela para as perguntas', async () => {
      ComentariosIaAPI.getResumo.mockResolvedValue({
        data: { status: 'reading' },
      });
      const escopo = effectScope();
      escopo.run(() => useResumo(alvo));
      await flushPromises();
      escopo.stop();
      await vi.advanceTimersByTimeAsync(ESPERA_LENDO_MS * 3);

      expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(1);
    });
  });

  it('ai_unavailable (a IA fora) chega como resumo, sem esperar', async () => {
    ComentariosIaAPI.getResumo.mockResolvedValue({
      data: { status: 'ai_unavailable' },
    });
    const resumo = useResumo(alvo);
    await flushPromises();

    expect(resumo.resumo.value.status).toBe('ai_unavailable');
    expect(resumo.carregando.value).toBe(false);
    expect(ComentariosIaAPI.getResumo).toHaveBeenCalledTimes(1);
  });

  it('trocar de alvo tira o resumo do anterior da tela', async () => {
    const [segunda] = pendente();
    ComentariosIaAPI.getResumo
      .mockResolvedValueOnce({ data: { status: 'ready', questions: 2 } })
      .mockReturnValueOnce(segunda);
    const atual = ref(alvo);
    const resumo = useResumo(atual);
    await flushPromises();

    atual.value = { ...alvo, id: '1791' };
    await flushPromises();
    expect(resumo.resumo.value).toBeNull();
    expect(resumo.carregando.value).toBe(true);
  });
});
