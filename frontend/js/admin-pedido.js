/* =====================================================================
   Detalle de un pedido para la administradora: /admin/pedido.html?id=5
     GP015 Ver el pedido y su comprobante
     GP016 Confirmar o rechazar (con motivo)
     GP017 Avanzar el estado o cancelar (con motivo)
   Solo se ofrecen los estados a los que puede pasar (estadosSiguientes);
   cada cambio le llega al cliente por correo (GP019).
   ===================================================================== */

const idPedido = Number(new URLSearchParams(location.search).get('id'));

const el = {
  cargando: document.getElementById('cargando'),
  detalle: document.getElementById('detallePedido'),
  volver: document.getElementById('volverPedidos'),
  dlg: document.getElementById('dialogoEstado'),
  form: document.getElementById('formEstado'),
  titulo: document.getElementById('tituloEstado'),
  texto: document.getElementById('textoEstado'),
  error: document.getElementById('errorEstado'),
  campoMotivo: document.getElementById('campoMotivo'),
  motivo: document.getElementById('motivo'),
  confirmar: document.getElementById('confirmarEstado'),
};

let pedidoActual = null;
let estadosSiguientes = [];
let estadoElegido = null;

el.volver.href = leerTemporal('ultimaListaPedidos') || '/admin/pedidos.html';

// el texto de cada botón dice exactamente qué pasa
function textoAccion(e) {
  const textos = {
    2: 'Confirmar pedido',
    7: 'Rechazar pedido',
    8: 'Cancelar pedido',
  };
  return textos[e.IdEstadoPedido] || `Cambiar a "${e.Nombre}"`;
}

/* ---------------- Cargar y pintar ---------------- */

async function cargar() {
  try {
    const { datos } = await api('/admin/pedidos/' + idPedido);
    pedidoActual = datos.pedido;
    estadosSiguientes = datos.estadosSiguientes ?? [];
    document.title = `Pedido ${pedidoActual.IdPedido} | Capanni`;

    el.detalle.innerHTML = `
      ${htmlCabeceraPedido(pedidoActual)}
      ${htmlAcciones()}
      <div class="bloques">
        ${htmlEntregaYPago(pedidoActual)}
        ${htmlClientePedido(pedidoActual)}
        ${htmlProductosPedido(datos.productos, pedidoActual)}
        ${htmlHistorialPedido(datos.historial)}
      </div>`;
  } catch (error) {
    if (error.codigo === 50033) return;
    el.detalle.innerHTML = `
      <div class="vacio">
        <h2>${error.codigo === 50056 ? 'El pedido no existe' : 'No se pudo cargar el pedido'}</h2>
        <p>${escapar(error.message)}</p>
        <a class="boton boton-principal" href="/admin/pedidos.html">Volver a pedidos</a>
      </div>`;
  } finally {
    el.cargando.hidden = true;
  }
}

function htmlAcciones() {
  if (!estadosSiguientes.length) {
    return '<p class="mensaje mensaje-aviso">Este pedido ya no tiene más cambios de estado.</p>';
  }
  return `
    <section class="acciones-pedido" aria-labelledby="tituloAcciones">
      <h2 id="tituloAcciones" class="solo-lector">Cambiar estado</h2>
      ${estadosSiguientes
        .map(
          (e) => `<button type="button" class="boton ${e.FlagDevuelveInventario ? 'boton-secundario boton-riesgo' : 'boton-principal'}"
                    data-estado="${e.IdEstadoPedido}">${escapar(textoAccion(e))}</button>`
        )
        .join('')}
    </section>`;
}

/* ---------------- GP016 / GP017 Cambiar estado ---------------- */

el.detalle.addEventListener('click', (evento) => {
  const boton = evento.target.closest('[data-estado]');
  if (!boton) return;
  estadoElegido = estadosSiguientes.find((e) => e.IdEstadoPedido === Number(boton.dataset.estado));
  if (!estadoElegido) return;

  const n = pedidoActual.IdPedido;
  const pideMotivo = Boolean(estadoElegido.FlagRequiereMotivo);

  if (estadoElegido.IdEstadoPedido === 7) el.titulo.textContent = `¿Confirma que desea rechazar el pedido ${n}?`;
  else if (estadoElegido.IdEstadoPedido === 8) el.titulo.textContent = `¿Confirma que desea cancelar el pedido ${n}?`;
  else el.titulo.textContent = `¿Confirma que desea cambiar el pedido ${n} a "${estadoElegido.Nombre}"?`;

  el.texto.textContent = estadoElegido.FlagDevuelveInventario
    ? 'Los productos regresan al inventario y se le avisará al cliente por correo con el motivo.'
    : 'Se le avisará al cliente por correo.';

  el.campoMotivo.hidden = !pideMotivo;
  el.motivo.value = '';
  el.motivo.removeAttribute('aria-invalid');
  el.error.hidden = true;
  el.confirmar.className = `boton ${estadoElegido.FlagDevuelveInventario ? 'boton-peligro' : 'boton-principal'}`;
  el.dlg.showModal();
  (pideMotivo ? el.motivo : el.confirmar).focus();
});

el.form.addEventListener('submit', async (evento) => {
  evento.preventDefault();
  el.error.hidden = true;

  const motivo = el.motivo.value.trim();
  // GP016 restricción 3: para rechazar (y cancelar) el motivo es obligatorio
  if (estadoElegido.FlagRequiereMotivo && !motivo) {
    el.error.textContent = 'Escriba el motivo.';
    el.error.hidden = false;
    el.motivo.setAttribute('aria-invalid', 'true');
    el.motivo.focus();
    return;
  }

  el.confirmar.disabled = true;
  try {
    const { mensaje } = await api(`/admin/pedidos/${pedidoActual.IdPedido}/estado`, {
      metodo: 'PUT',
      cuerpo: { idEstado: estadoElegido.IdEstadoPedido, motivo: motivo || null },
    });
    el.dlg.close();
    notificar(mensaje);
    cargar();
  } catch (error) {
    el.error.textContent = error.message;
    el.error.hidden = false;
    // otra pestaña ya lo cambió: se recarga para ver el estado real
    if (error.codigo === 50057) cargar();
  } finally {
    el.confirmar.disabled = false;
  }
});

(async () => {
  if (!(await exigirSesion('pedidos'))) return;
  cargar();
})();
