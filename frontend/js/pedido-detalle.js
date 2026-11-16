/* =====================================================================
   pedido-detalle.js: cómo se dibuja un pedido. Lo usan el cliente
   (GP018, /cuenta/pedido.html) y la administradora (GP015 a GP017,
   /admin/pedido.html y /admin/pedidos.html), así se ve igual en los dos.
   Se carga después de comun.js.
   ===================================================================== */

// color del estado (estilos.css: .estado-pedido.e1 ... .e8)
function htmlEstadoPedido(idEstado, nombre) {
  return `<span class="estado-pedido e${Number(idEstado)}">${escapar(nombre)}</span>`;
}

function textoEnvio(pedido) {
  if (!pedido.FlagRequiereDireccion) return 'Sin costo';
  if (pedido.CostoEnvio === null || pedido.CostoEnvio === undefined) return 'Por coordinar';
  return formatearPrecio(pedido.CostoEnvio);
}

function htmlCabeceraPedido(pedido) {
  // GP019 restricción 1: el motivo se muestra si fue rechazado o cancelado
  const motivo = pedido.MotivoEstado
    ? `<p class="mensaje mensaje-aviso"><strong>Motivo:</strong> ${escapar(pedido.MotivoEstado)}</p>`
    : '';
  return `
    <div class="titulo-admin">
      <div>
        <h1>Pedido ${pedido.IdPedido}</h1>
        <p>Realizado el ${escapar(formatearFecha(pedido.FechaCreacion))}</p>
      </div>
      ${htmlEstadoPedido(pedido.IdEstadoPedido, pedido.Estado)}
    </div>
    ${motivo}`;
}

function htmlClientePedido(pedido) {
  return `
    <section class="bloque" aria-labelledby="tituloCliente">
      <h2 id="tituloCliente">Cliente</h2>
      <dl class="datos">
        <div><dt>Nombre</dt><dd>${escapar(pedido.Cliente)}</dd></div>
        <div><dt>Correo</dt><dd><a href="mailto:${escapar(pedido.Correo)}">${escapar(pedido.Correo)}</a></dd></div>
        <div><dt>Teléfono</dt><dd><a href="tel:${escapar(pedido.Telefono)}">${escapar(pedido.Telefono)}</a></dd></div>
      </dl>
    </section>`;
}

// GP015 restricción 2: método de pago, entrega y el comprobante (si es SINPE)
function htmlEntregaYPago(pedido) {
  let comprobante;
  if (pedido.urlComprobante) {
    comprobante = `
      <a class="comprobante-vista" href="${escapar(pedido.urlComprobante)}" target="_blank" rel="noopener">
        <img src="${escapar(pedido.urlComprobante)}" alt="Comprobante de SINPE Móvil del pedido ${pedido.IdPedido}" loading="lazy">
      </a>
      <p class="ayuda">Toque la imagen para verla completa.<br>Subido el ${escapar(formatearFecha(pedido.FechaComprobante))}</p>`;
  } else if (pedido.FlagRequiereComprobante) {
    comprobante = '<p class="mensaje mensaje-error">No se encontró el comprobante de pago.</p>';
  } else {
    comprobante = '<p>Pago en efectivo al retirar en el taller.</p>';
  }

  return `
    <section class="bloque" aria-labelledby="tituloEntrega">
      <h2 id="tituloEntrega">Entrega y pago</h2>
      <dl class="datos">
        <div><dt>Entrega</dt><dd>${escapar(pedido.MetodoEntrega)}</dd></div>
        <div><dt>Dirección</dt><dd>${pedido.DireccionEntrega ? escapar(pedido.DireccionEntrega) : 'Retiro en el taller'}</dd></div>
        <div><dt>Pago</dt><dd>${escapar(pedido.MetodoPago)}</dd></div>
      </dl>
      ${comprobante}
    </section>`;
}

// productos con el nombre, talla y precio del momento de la compra
function htmlProductosPedido(productos, pedido) {
  return `
    <section class="bloque" aria-labelledby="tituloProductos">
      <h2 id="tituloProductos">Productos</h2>
      <ul class="resumen-productos con-foto">
        ${productos
          .map(
            (p) => `
          <li>
            <span class="miniatura">${htmlFoto({ RutaImagen: p.RutaImagen, Nombre: p.NombreProducto }, { textoSinFoto: '' })}</span>
            <span class="resumen-nombre">${escapar(p.NombreProducto)}
              <span class="ayuda">talla ${escapar(p.NombreTalla)} × ${p.Cantidad}, ${escapar(formatearPrecio(p.PrecioUnitario))} c/u</span>
            </span>
            <span>${escapar(formatearPrecio(p.Subtotal))}</span>
          </li>`
          )
          .join('')}
      </ul>
      <dl class="montos">
        <div><dt>Productos</dt><dd>${escapar(formatearPrecio(pedido.SubtotalProductos))}</dd></div>
        <div><dt>Envío</dt><dd>${escapar(textoEnvio(pedido))}</dd></div>
        <div class="total"><dt>Total</dt><dd>${escapar(formatearPrecio(pedido.Total))}</dd></div>
      </dl>
    </section>`;
}

// GP016 paso 2.1, GP017 paso 4.1, GP019 restricción 2: cada cambio con fecha y hora
function htmlHistorialPedido(historial) {
  return `
    <section class="bloque" aria-labelledby="tituloHistorial">
      <h2 id="tituloHistorial">Historial del pedido</h2>
      <ol class="linea-tiempo">
        ${historial
          .map(
            (h) => `
          <li>
            ${htmlEstadoPedido(h.IdEstadoPedido, h.Estado)}
            <time datetime="${escapar(h.FechaHora)}">${escapar(formatearFecha(h.FechaHora))}</time>
            ${h.Comentario ? `<p>${escapar(h.Comentario)}</p>` : ''}
          </li>`
          )
          .join('')}
      </ol>
    </section>`;
}

// fila de una lista de pedidos (cliente y administradora)
function htmlFilaPedido(p, { href, conCliente = false }) {
  return `
    <li>
      <a class="fila-pedido" href="${href}">
        <span class="fila-pedido-numero">Pedido ${p.IdPedido}</span>
        <span class="fila-pedido-datos">
          ${conCliente ? `<span>${escapar(p.Cliente)}</span>` : ''}
          <span>${escapar(formatearFecha(p.FechaCreacion))}</span>
          ${conCliente ? `<span>${escapar(p.MetodoPago)}, ${escapar(p.MetodoEntrega)}</span>` : ''}
        </span>
        <span class="fila-pedido-total">${escapar(formatearPrecio(p.Total))}</span>
        ${htmlEstadoPedido(p.IdEstadoPedido, p.Estado)}
      </a>
    </li>`;
}
