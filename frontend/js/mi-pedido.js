/* =====================================================================
   GP018 Detalle de un pedido del cliente: /cuenta/pedido.html?id=5
   Con &nuevo=1 viene de confirmar la orden y muestra el número de pedido
   (GP014 paso 2.5).
   ===================================================================== */

const params = new URLSearchParams(location.search);
const idPedido = Number(params.get('id'));
const esNuevo = params.get('nuevo') === '1';

const el = {
  cargando: document.getElementById('cargando'),
  detalle: document.getElementById('detallePedido'),
};

async function cargar() {
  try {
    const { datos } = await api('/cliente/pedidos/' + idPedido);
    const { pedido, productos, historial } = datos;
    document.title = `Pedido ${pedido.IdPedido} | Confecciones Capanni`;

    const bienvenida = esNuevo
      ? `<div class="mensaje mensaje-ok confirmacion-orden" role="status">
          <p><strong>¡Gracias por su compra!</strong> Su número de pedido es <strong>${pedido.IdPedido}</strong>.</p>
          <p>Queda pendiente de confirmación: le avisaremos por correo cuando Capanni revise su pago.</p>
        </div>`
      : '';

    el.detalle.innerHTML = `
      ${bienvenida}
      ${htmlCabeceraPedido(pedido)}
      <div class="bloques">
        ${htmlProductosPedido(productos, pedido)}
        ${htmlEntregaYPago(pedido)}
        ${htmlHistorialPedido(historial)}
      </div>`;
  } catch (error) {
    if (error.codigo === 50033) return;
    el.detalle.innerHTML = `
      <div class="vacio">
        <h2>${error.codigo === 50056 ? 'El pedido no existe' : 'No se pudo cargar el pedido'}</h2>
        <p>${error.codigo === 50056 ? 'Revise el número o vuelva a la lista de sus pedidos.' : escapar(error.message)}</p>
        <a class="boton boton-principal" href="/cuenta/pedidos.html">Ver mis pedidos</a>
      </div>`;
  } finally {
    el.cargando.hidden = true;
  }
}

(async () => {
  if (esNuevo) {
    leerTemporal('aviso', { borrar: true }); // el mensaje ya va en la página, no como aviso flotante
    history.replaceState(null, '', `/cuenta/pedido.html?id=${idPedido}`);
  }
  if (!(await exigirCliente('pedidos'))) return;
  cargar();
})();
