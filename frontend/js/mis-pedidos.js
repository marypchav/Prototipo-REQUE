/* =====================================================================
   GP018 Consultar historial de pedido: /cuenta/pedidos.html
   Los pedidos del cliente, del más reciente al más antiguo.
   ===================================================================== */

const el = {
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoPedidos'),
  lista: document.getElementById('listaPedidos'),
};

async function cargar() {
  try {
    const { datos } = await api('/cliente/pedidos');
    const pedidos = datos.pedidos ?? [];

    if (!pedidos.length) {
      // GP018 flujo alterno
      el.estado.innerHTML = `
        <div class="vacio">
          <img class="monograma" src="/img/monograma.svg" alt="">
          <h2>Aún no ha realizado pedidos</h2>
          <p>Cuando confirme una orden, aquí podrá seguir su estado.</p>
          <a class="boton boton-principal" href="/">Ver catálogo</a>
        </div>`;
      return;
    }

    el.lista.innerHTML = pedidos
      .map((p) => htmlFilaPedido(p, { href: `/cuenta/pedido.html?id=${p.IdPedido}` }))
      .join('');
  } catch (error) {
    if (error.codigo === 50033) return;
    el.estado.innerHTML = `<p class="mensaje mensaje-error">${escapar(error.message)}</p>`;
  } finally {
    el.cargando.hidden = true;
  }
}

(async () => {
  if (!(await exigirCliente('pedidos'))) return;
  cargar();
})();
