/* =====================================================================
   Detalle de un producto: /producto.html?id=5
     CP008 Ver detalle del producto     CP011 Compartir producto
     CP003, CP004, CP005 tallas, precio y "Agotado"
     CP010 se actualiza solo si la administradora cambia este producto
   ===================================================================== */

const idProducto = Number(new URLSearchParams(location.search).get('id'));
const urlCatalogo = leerTemporal('ultimoCatalogo') || '/';

const el = {
  cargando: document.getElementById('cargando'),
  detalle: document.getElementById('detalle'),
  volver: document.getElementById('volverCatalogo'),
};

let productoActual = null;
let tallaElegida = null; // IdTalla marcado por el cliente
let temporizadorRegreso = null;

el.volver.href = urlCatalogo; // CP008: vuelve con los mismos filtros

/* ---------------- Cargar ---------------- */

async function cargarProducto({ desdeTiempoReal = false } = {}) {
  if (!Number.isInteger(idProducto) || idProducto <= 0) {
    pintarNoDisponible({ mientrasLoVeia: false });
    return;
  }

  try {
    const { datos } = await api('/productos/' + idProducto);
    const estabaDisponible = Boolean(productoActual?.Disponible);
    productoActual = datos;
    pintarProducto(datos);
    if (desdeTiempoReal && estabaDisponible && !datos.Disponible) {
      notificar('Este producto se acaba de agotar.'); // CP008 alterno y CP005
    }
  } catch (error) {
    if (error.codigo === 50011) {
      // eliminado. Si el cliente lo estaba viendo, se le regresa al catálogo (CP008 alterno)
      pintarNoDisponible({ mientrasLoVeia: desdeTiempoReal });
    } else if (!(desdeTiempoReal && productoActual)) {
      pintarError(error);
    }
  } finally {
    el.cargando.hidden = true;
  }
}

/* ---------------- Pintar ---------------- */

function pintarProducto(p) {
  const disponible = Boolean(p.Disponible);
  const conPrecio = precioValido(p.Precio);
  const tallas = (p.tallas ?? []).filter((t) => Number(t.Cantidad) > 0);

  // si la talla que había elegido se agotó, se desmarca
  if (!tallas.some((t) => t.IdTalla === tallaElegida)) tallaElegida = null;

  document.title = `${p.Nombre} | Confecciones Capanni`;

  el.detalle.innerHTML = `
    <article class="detalle ${claseCategoria(p.IdCategoria)}">
      <div class="detalle-foto">
        ${htmlFoto(p, { textoSinFoto: 'Este producto aún no tiene foto' })}
        ${disponible ? '' : '<span class="sello-agotado">Agotado</span>'}
      </div>

      <div class="detalle-info">
        <div>
          <span class="categoria-texto">${escapar(p.Categoria)}</span>
          <h1>${escapar(p.Nombre)}</h1>
        </div>

        <p class="detalle-precio ${conPrecio ? '' : 'sin-precio'}">${escapar(formatearPrecio(p.Precio))}</p>

        ${p.Descripcion ? `<p class="detalle-descripcion">${escapar(p.Descripcion)}</p>` : ''}

        <div class="filtro-grupo">
          <p class="filtro-titulo" id="tituloTallasDetalle">Tallas disponibles</p>
          ${
            tallas.length
              ? `<div class="tallas-opciones" role="radiogroup" aria-labelledby="tituloTallasDetalle">
                  ${tallas
                    .map(
                      (t) => `<label>
                        <input type="radio" name="talla" value="${t.IdTalla}" ${t.IdTalla === tallaElegida ? 'checked' : ''}>
                        <span class="talla">${escapar(t.Talla)}</span>
                        <span class="solo-lector">Talla ${escapar(t.Talla)}</span>
                      </label>`
                    )
                    .join('')}
                </div>`
              : '<p class="sin-tallas">Sin tallas disponibles</p>'
          }
        </div>

        <div class="detalle-acciones">
          <button type="button" class="boton boton-principal" id="agregarCarrito"
            ${disponible && conPrecio ? '' : 'disabled'}>
            ${disponible ? 'Agregar al carrito' : 'Agotado'}
          </button>
          <button type="button" class="boton boton-secundario" id="compartir" aria-expanded="false" aria-controls="panelCompartir">
            Compartir
          </button>
        </div>
        <p class="mensaje mensaje-error" id="errorCarrito" role="alert" hidden></p>

        <div class="compartir-panel" id="panelCompartir" hidden>
          <label for="enlaceProducto" class="filtro-titulo">Enlace del producto</label>
          <div class="fila-enlace">
            <input type="text" id="enlaceProducto" readonly value="${escapar(enlaceDelProducto())}">
            <button type="button" class="boton boton-principal boton-pequeno" id="copiarEnlace">Copiar enlace</button>
          </div>
          ${
            puedeCompartirConApps()
              ? '<button type="button" class="boton boton-secundario boton-pequeno" id="compartirApps">Enviar por WhatsApp u otra aplicación</button>'
              : ''
          }
        </div>
      </div>
    </article>`;

  conectarAcciones();
}

function pintarNoDisponible({ mientrasLoVeia }) {
  productoActual = null;
  document.title = 'Producto no disponible | Confecciones Capanni';
  el.detalle.innerHTML = `
    <div class="vacio no-disponible" role="alert">
      <img class="monograma" src="/img/monograma.svg" alt="">
      <h1 style="font-size:1.6rem">Este producto ya no está disponible</h1>
      <p>${mientrasLoVeia ? 'Lo llevaremos al catálogo en unos segundos.' : 'Puede ver las demás prendas en el catálogo.'}</p>
      <a class="boton boton-principal" href="${escapar(urlCatalogo)}">Ir al catálogo</a>
    </div>`;

  if (mientrasLoVeia) {
    clearTimeout(temporizadorRegreso);
    temporizadorRegreso = setTimeout(() => location.assign(urlCatalogo), 5000);
  }
}

function pintarError(error) {
  el.detalle.innerHTML = `
    <div class="vacio no-disponible">
      <img class="monograma" src="/img/monograma.svg" alt="">
      <h1 style="font-size:1.6rem">No se pudo cargar el producto</h1>
      <p>${escapar(error.message || MENSAJE_INESPERADO)}</p>
      <button type="button" class="boton boton-principal" id="reintentar">Intentar de nuevo</button>
    </div>`;
  document.getElementById('reintentar').addEventListener('click', () => cargarProducto());
}

/* ---------------- Acciones ---------------- */

function conectarAcciones() {
  const errorCarrito = document.getElementById('errorCarrito');

  el.detalle.querySelectorAll('input[name="talla"]').forEach((radio) => {
    radio.addEventListener('change', () => {
      tallaElegida = Number(radio.value);
      errorCarrito.hidden = true;
    });
  });

  document.getElementById('agregarCarrito').addEventListener('click', () => {
    if (!tallaElegida) {
      errorCarrito.textContent = 'Seleccione una talla.';
      errorCarrito.hidden = false;
      return;
    }
    agregarAlCarrito(productoActual, tallaElegida);
  });

  const botonCompartir = document.getElementById('compartir');
  const panel = document.getElementById('panelCompartir');
  botonCompartir.addEventListener('click', () => {
    panel.hidden = !panel.hidden;
    botonCompartir.setAttribute('aria-expanded', String(!panel.hidden));
  });

  document.getElementById('copiarEnlace').addEventListener('click', copiarEnlace);
  document.getElementById('compartirApps')?.addEventListener('click', compartirConApps);
}

/*
Módulo Gestión de pedidos (GP007). CP009 alterno: sin sesión, se pide
iniciar sesión o registrarse. Cuando exista la página del cliente, este es
el único lugar que hay que cambiar.
*/
function agregarAlCarrito(producto, idTalla) {
  notificar('Para agregar productos al carrito debe iniciar sesión o registrarse. Esta opción estará disponible pronto.');
}

/* ---------------- CP011 Compartir ---------------- */

function enlaceDelProducto() {
  return `${location.origin}/producto.html?id=${idProducto}`;
}

function puedeCompartirConApps() {
  return typeof navigator.share === 'function';
}

async function compartirConApps() {
  try {
    // solo se envía el enlace y el nombre: ningún dato del cliente (CP011 restricción 2)
    await navigator.share({
      title: productoActual?.Nombre ?? 'Confecciones Capanni',
      text: `Mire este producto de Confecciones Capanni: ${productoActual?.Nombre ?? ''}`,
      url: enlaceDelProducto(),
    });
    notificar('Enlace compartido.');
  } catch (error) {
    if (error?.name !== 'AbortError') notificar('No se pudo compartir. Copie el enlace.', { error: true });
  }
}

// CP011 alterno: si el dispositivo no tiene menú de compartir, solo se copia
async function copiarEnlace() {
  const texto = enlaceDelProducto();
  try {
    await navigator.clipboard.writeText(texto);
    notificar('Enlace copiado.');
    return;
  } catch {
    /* navigator.clipboard solo existe con https o localhost; abajo el plan B */
  }

  const campo = document.getElementById('enlaceProducto');
  campo.focus();
  campo.select();
  let copiado = false;
  try {
    copiado = document.execCommand('copy');
  } catch {
    copiado = false;
  }
  notificar(copiado ? 'Enlace copiado.' : 'Mantenga presionado el enlace para copiarlo.', { error: !copiado });
}

/* ---------------- Inicio ---------------- */

pintarEncabezadoPublico('producto');
pintarPie();
cargarProducto();

// CP010: si cambia este producto (o varios a la vez), se vuelve a pedir
escucharCatalogo(
  (id) => {
    if (id === null || id === idProducto) cargarProducto({ desdeTiempoReal: true });
  },
  () => cargarProducto({ desdeTiempoReal: true })
);
