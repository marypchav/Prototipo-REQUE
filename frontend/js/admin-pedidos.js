/* =====================================================================
   GP015 Pedidos de la administradora: /admin/pedidos.html?estado=1
   Lista con número, cliente, fecha, total y estado, filtrable por estado.
   ===================================================================== */

const el = {
  resumen: document.getElementById('resumen'),
  filtro: document.getElementById('filtroEstado'),
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoPedidos'),
  lista: document.getElementById('listaPedidos'),
};

let estadoFiltro = new URLSearchParams(location.search).get('estado') || '';
let estados = [];

async function cargar() {
  el.cargando.hidden = false;
  history.replaceState(null, '', location.pathname + (estadoFiltro ? `?estado=${estadoFiltro}` : ''));
  guardarTemporal('ultimaListaPedidos', location.pathname + location.search);

  try {
    const { datos } = await api('/admin/pedidos' + (estadoFiltro ? `?estado=${estadoFiltro}` : ''));
    estados = datos.estados ?? [];
    pintarFiltro();
    pintar(datos.pedidos ?? []);
  } catch (error) {
    if (error.codigo === 50033) return;
    el.lista.replaceChildren();
    el.estado.innerHTML = `<p class="mensaje mensaje-error">${escapar(error.message)}</p>`;
  } finally {
    el.cargando.hidden = true;
  }
}

function pintarFiltro() {
  el.filtro.innerHTML =
    `<button type="button" class="ficha ficha-todas" data-estado="" aria-pressed="${!estadoFiltro}">Todos</button>` +
    estados
      .map(
        (e) => `<button type="button" class="ficha ficha-estado e${e.IdEstadoPedido}" data-estado="${e.IdEstadoPedido}"
                  aria-pressed="${String(e.IdEstadoPedido) === estadoFiltro}">${escapar(e.Nombre)}</button>`
      )
      .join('');
}

function pintar(pedidos) {
  el.estado.innerHTML = '';
  const nombreEstado = estados.find((e) => String(e.IdEstadoPedido) === estadoFiltro)?.Nombre;

  el.resumen.textContent =
    (pedidos.length === 1 ? '1 pedido' : `${pedidos.length} pedidos`) +
    (nombreEstado ? ` en estado "${nombreEstado}"` : '');

  if (!pedidos.length) {
    el.lista.replaceChildren();
    el.estado.innerHTML = `
      <div class="vacio">
        <img class="monograma" src="/img/monograma.svg" alt="">
        <h2>${estadoFiltro ? 'No hay pedidos con este estado' : 'Aún no hay pedidos registrados'}</h2>
        ${estadoFiltro ? '<button type="button" class="boton boton-principal" data-estado="">Ver todos</button>' : '<p>Cuando un cliente confirme una orden, aparecerá aquí.</p>'}
      </div>`;
    return;
  }

  el.lista.innerHTML = pedidos
    .map((p) => htmlFilaPedido(p, { href: `/admin/pedido.html?id=${p.IdPedido}`, conCliente: true }))
    .join('');
}

document.addEventListener('click', (evento) => {
  const boton = evento.target.closest('[data-estado]');
  if (!boton) return;
  estadoFiltro = boton.dataset.estado;
  cargar();
});

(async () => {
  if (!(await exigirSesion('pedidos'))) return;
  cargar();
})();
