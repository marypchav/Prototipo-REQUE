/* =====================================================================
   Página del catálogo (módulo Catálogo de productos)
     CP001 Visualizar catálogo           CP005 Disponibilidad (Agotado)
     CP002 Foto del producto             CP006 Filtrar por talla
     CP003 Tallas disponibles            CP007 Filtrar por categoría
     CP004 Precio                        CP009 Acceso público (sin sesión)
     CP010 Actualización en tiempo real
   Los filtros quedan en la dirección (?categoria=2&tallas=2,3) para que
   "Volver al catálogo" desde el detalle no los pierda (CP008).
   ===================================================================== */

const estado = {
  categoria: '', // '' = todas
  tallas: new Set(), // ids de talla marcados
  categorias: [],
  tallasDisponibles: [],
  tarjetas: new Map(), // IdProducto -> { html, elemento }
  cargadoUnaVez: false,
};

const el = {
  filtros: document.getElementById('filtros'),
  fichas: document.getElementById('fichasCategorias'),
  tallas: document.getElementById('opcionesTallas'),
  conteo: document.getElementById('conteo'),
  limpiar: document.getElementById('limpiarFiltros'),
  cargando: document.getElementById('cargando'),
  estado: document.getElementById('estadoCatalogo'),
  rejilla: document.getElementById('rejilla'),
};

/* ---------------- Filtros en la dirección ---------------- */

function leerFiltrosDeLaDireccion() {
  const params = new URLSearchParams(location.search);
  const categoria = params.get('categoria');
  estado.categoria = /^\d+$/.test(categoria || '') ? categoria : '';
  estado.tallas = new Set(
    (params.get('tallas') || '').split(',').filter((t) => /^\d+$/.test(t))
  );
}

function consultaActual() {
  const params = new URLSearchParams();
  if (estado.categoria) params.set('categoria', estado.categoria);
  if (estado.tallas.size) params.set('tallas', [...estado.tallas].join(','));
  const texto = params.toString();
  return texto ? '?' + texto : '';
}

function guardarFiltrosEnLaDireccion() {
  const consulta = consultaActual();
  history.replaceState(null, '', location.pathname + consulta);
  guardarTemporal('ultimoCatalogo', '/' + consulta);
}

function hayFiltros() {
  return Boolean(estado.categoria) || estado.tallas.size > 0;
}

/* ---------------- Cargar ---------------- */

async function cargarCatalogo({ desdeTiempoReal = false, idCambiado = null } = {}) {
  if (!estado.cargadoUnaVez) el.cargando.hidden = false;

  try {
    const { datos } = await api('/catalogo' + consultaActual());
    estado.categorias = datos.filtros?.categorias ?? [];
    estado.tallasDisponibles = datos.filtros?.tallas ?? [];
    estado.cargadoUnaVez = true;

    pintarFiltros();
    pintarProductos(datos.productos ?? [], { resaltar: desdeTiempoReal ? idCambiado : undefined });
  } catch (error) {
    // en una actualización en segundo plano no se borra lo que ya se ve
    if (desdeTiempoReal && estado.cargadoUnaVez) return;
    pintarError(error);
  } finally {
    el.cargando.hidden = true;
  }
}

/* ---------------- Filtros ---------------- */

function pintarFiltros() {
  el.filtros.hidden = false;

  // al volver a dibujar los filtros, el foco del teclado se queda donde estaba
  const activo = document.activeElement;
  const selectorFoco = el.filtros.contains(activo)
    ? activo.dataset.categoria !== undefined
      ? `[data-categoria="${activo.dataset.categoria}"]`
      : activo.value
        ? `input[value="${activo.value}"]`
        : null
    : null;
  queueMicrotask(() => selectorFoco && el.filtros.querySelector(selectorFoco)?.focus());

  // si la categoría elegida ya no está en la lista (se quedó sin productos), se sigue mostrando
  const categorias = [...estado.categorias];
  if (estado.categoria && !categorias.some((c) => String(c.IdCategoria) === estado.categoria)) {
    categorias.push({ IdCategoria: Number(estado.categoria), Nombre: 'Categoría elegida' });
  }

  el.fichas.innerHTML =
    `<button type="button" class="ficha ficha-todas" data-categoria="" aria-pressed="${!estado.categoria}">Todas</button>` +
    categorias
      .map(
        (c) => `<button type="button" class="ficha ${claseCategoria(c.IdCategoria)}"
                  data-categoria="${c.IdCategoria}"
                  aria-pressed="${String(c.IdCategoria) === estado.categoria}">${escapar(c.Nombre)}</button>`
      )
      .join('');

  const tallas = [...estado.tallasDisponibles];
  for (const id of estado.tallas) {
    if (!tallas.some((t) => String(t.IdTalla) === id)) tallas.push({ IdTalla: Number(id), Nombre: '?' });
  }

  el.tallas.innerHTML = tallas
    .map(
      (t) => `<label>
          <input type="checkbox" value="${t.IdTalla}" ${estado.tallas.has(String(t.IdTalla)) ? 'checked' : ''}>
          <span class="talla">${escapar(t.Nombre)}</span>
          <span class="solo-lector">Talla ${escapar(t.Nombre)}</span>
        </label>`
    )
    .join('');

  el.limpiar.hidden = !hayFiltros();
}

el.fichas.addEventListener('click', (evento) => {
  const boton = evento.target.closest('[data-categoria]');
  if (!boton) return;
  estado.categoria = boton.dataset.categoria;
  guardarFiltrosEnLaDireccion();
  cargarCatalogo();
});

el.tallas.addEventListener('change', (evento) => {
  const casilla = evento.target;
  if (casilla.checked) estado.tallas.add(casilla.value);
  else estado.tallas.delete(casilla.value);
  guardarFiltrosEnLaDireccion();
  cargarCatalogo();
});

function limpiarFiltros() {
  estado.categoria = '';
  estado.tallas.clear();
  guardarFiltrosEnLaDireccion();
  cargarCatalogo();
}

el.limpiar.addEventListener('click', limpiarFiltros);

/* ---------------- Productos ---------------- */

function htmlTarjeta(p) {
  const disponible = Boolean(p.Disponible);
  const tallas = (p.tallas ?? []).filter((t) => Number(t.Cantidad) > 0);
  const conPrecio = precioValido(p.Precio);

  return `
    <a class="tarjeta ${claseCategoria(p.IdCategoria)} ${disponible ? '' : 'agotado'}" href="/producto.html?id=${p.IdProducto}">
      <div class="tarjeta-foto">
        ${htmlFoto(p)}
        ${disponible ? '' : '<span class="sello-agotado">Agotado</span>'}
        <span class="precio-etiqueta ${conPrecio ? '' : 'sin-precio'}">${escapar(formatearPrecio(p.Precio))}</span>
      </div>
      <div class="tarjeta-cuerpo">
        <h2>${escapar(p.Nombre)}</h2>
        <span class="categoria-texto">${escapar(p.Categoria)}</span>
        ${
          tallas.length
            ? `<div class="tallas-lista" aria-label="Tallas disponibles">
                 ${tallas.map((t) => `<span class="talla talla-mini">${escapar(t.Talla)}</span>`).join('')}
               </div>`
            : '<span class="sin-tallas">Sin tallas disponibles</span>'
        }
      </div>
    </a>`;
}

/*
CP010: se actualizan solo las tarjetas que cambiaron. Las demás se quedan como
están, así no se pierde la posición ni los filtros.
*/
function pintarProductos(productos, { resaltar } = {}) {
  el.estado.innerHTML = '';

  if (!productos.length) {
    el.rejilla.replaceChildren();
    estado.tarjetas.clear();
    el.conteo.textContent = '';
    pintarVacio();
    return;
  }

  const nuevas = new Map();
  const elementos = productos.map((p) => {
    const html = htmlTarjeta(p);
    const anterior = estado.tarjetas.get(p.IdProducto);
    let elemento;
    if (anterior && anterior.html === html) {
      elemento = anterior.elemento;
    } else {
      elemento = document.createElement('li');
      elemento.innerHTML = html;
      // brillo breve en la tarjeta que acaba de cambiar
      if (resaltar !== undefined && (resaltar === null ? anterior : resaltar === p.IdProducto)) {
        elemento.firstElementChild.classList.add('recien');
      }
    }
    nuevas.set(p.IdProducto, { html, elemento });
    return elemento;
  });

  el.rejilla.replaceChildren(...elementos);
  estado.tarjetas = nuevas;

  el.conteo.textContent = productos.length === 1 ? '1 producto' : `${productos.length} productos`;
}

function pintarVacio() {
  let titulo;
  let conBoton = true;

  if (estado.tallas.size) {
    titulo = 'No se encontraron productos con esa talla'; // CP006
  } else if (estado.categoria) {
    titulo = 'No se encontraron productos en esta categoría'; // CP007
  } else {
    titulo = 'Por el momento no hay productos en el catálogo'; // CP001
    conBoton = false;
  }

  el.estado.innerHTML = `
    <div class="vacio">
      <img class="monograma" src="/img/monograma.svg" alt="">
      <h2>${titulo}</h2>
      ${
        conBoton
          ? '<p>Pruebe con otra combinación o vuelva a ver todo el catálogo.</p><button type="button" class="boton boton-principal" data-limpiar>Limpiar filtro</button>'
          : '<p>Vuelva pronto: aquí aparecerán las prendas nuevas.</p>'
      }
    </div>`;

  el.estado.querySelector('[data-limpiar]')?.addEventListener('click', limpiarFiltros);
}

function pintarError(error) {
  el.rejilla.replaceChildren();
  estado.tarjetas.clear();
  el.estado.innerHTML = `
    <div class="vacio">
      <img class="monograma" src="/img/monograma.svg" alt="">
      <h2>No se pudo cargar el catálogo</h2>
      <p>${escapar(error.message || MENSAJE_INESPERADO)}</p>
      <button type="button" class="boton boton-principal" id="reintentar">Intentar de nuevo</button>
    </div>`;
  document.getElementById('reintentar').addEventListener('click', () => cargarCatalogo());
}

/* ---------------- Inicio ---------------- */

pintarEncabezadoPublico('catalogo');
pintarPie();
leerFiltrosDeLaDireccion();
guardarFiltrosEnLaDireccion();
cargarCatalogo();

// CP010: cuando la administradora cambia algo, se recarga con los mismos filtros
escucharCatalogo(
  (idProducto) => cargarCatalogo({ desdeTiempoReal: true, idCambiado: idProducto }),
  () => cargarCatalogo({ desdeTiempoReal: true })
);
